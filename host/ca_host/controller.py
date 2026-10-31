"""High-level control of a CA core over any Device transport."""
import time

import numpy as np

from ca_model import lenia
from ca_model.grids import pack_frame, unpack_frame
from ca_model.rules import params_vector

from . import regs
from .device import Device

BOUNDARIES = ["toroidal", "cylindrical", "rectangular", "zero"]
RULES = ["hodgepodge", "ghm", "interval", "lenia"]


class CAController:
    def __init__(self, dev: Device, cfg: dict):
        self.dev = dev
        self.cfg = cfg
        if dev.read_reg(regs.REG_ID) != regs.CA_ID:
            raise IOError("no CA core found (ID register mismatch)")
        info = self.info()
        if [info["grid_x"], info["grid_y"]] != list(cfg["grid"]) or info["cell_w"] != cfg["cell_w"] \
                or info["nbh"] != cfg["nbh"]:
            raise ValueError(f"core is {info}, configuration expects {cfg['grid']} / {cfg['cell_w']} / {cfg['nbh']}")
        self.frame_bytes = info["grid_x"] * info["grid_y"] * info["cell_w"] // 8
        if cfg["rule"] == "lenia":
            want = {"rule": "lenia", "classes": lenia.num_classes(cfg["nbh"]),
                    "weight_w": cfg.get("weight_w", lenia.DEFAULT_WEIGHT_W),
                    "lut_idx_w": cfg.get("lut_idx_w", lenia.DEFAULT_LUT_IDX_W)}
            got = {k: info.get(k) for k in want}
            if got != want:
                raise ValueError(f"core is {got}, configuration expects {want}")
            p = cfg["params"]
            # The power-up kernel and growth function of a core built for this configuration.
            self.weights = lenia.kernel_weights(p["R"], p["beta"], cfg["nbh"], want["weight_w"])
            self.growth = (p["mu"], p["sigma"], p["T"])

    def info(self) -> dict:
        dim = self.dev.read_reg(regs.REG_GRID_DIM)
        c = self.dev.read_reg(regs.REG_CORE_CFG)
        info = {"grid_x": dim & 0xFFFF, "grid_y": dim >> 16, "cell_w": c & 0xFF, "nbh": (c >> 8) & 0xFF,
                "boundary": BOUNDARIES[(c >> 16) & 3],
                "rule": RULES[(c >> 20) & 0xF] if (c >> 20) & 0xF < len(RULES) else "?",
                "data_bytes": c >> 24}
        if info["rule"] == "lenia":
            lc = self.dev.read_reg(regs.REG_LENIA_CFG)
            info.update(classes=lc & 0xFF, weight_w=(lc >> 8) & 0xF, lut_idx_w=(lc >> 12) & 0xF,
                        entry_w=(lc >> 16) & 0x1F)
        return info

    def _buffers(self) -> tuple[int, int]:
        r = self.dev.read_reg
        return (r(regs.REG_BUF0_LO) | r(regs.REG_BUF0_HI) << 32,
                r(regs.REG_BUF1_LO) | r(regs.REG_BUF1_HI) << 32)

    def _ctrl(self, run=None, pause=None, auto=None, reset_state=False) -> None:
        cur = self.dev.read_reg(regs.REG_CTRL)
        bits = {regs.CTRL_RUN: run, regs.CTRL_PAUSE: pause, regs.CTRL_AUTO: auto}
        for bit, v in bits.items():
            if v is not None:
                cur = (cur | 1 << bit) if v else (cur & ~(1 << bit))
        cur &= ~(1 << regs.CTRL_RESET_STATE)
        if reset_state:
            cur |= 1 << regs.CTRL_RESET_STATE
        self.dev.write_reg(regs.REG_CTRL, cur)

    def _status(self, bit: int) -> bool:
        return bool(self.dev.read_reg(regs.REG_STATUS) >> bit & 1)

    def _wait_clear(self, bit: int, timeout: float, what: str) -> None:
        end = time.monotonic() + timeout
        while self._status(bit):
            if time.monotonic() > end:
                raise TimeoutError(f"CA core: {what}")
            time.sleep(0.0005)

    def _wait_idle(self, timeout: float) -> None:
        """Wait until no pass is active (RUN must already be clear)."""
        end = time.monotonic() + timeout
        while self._status(regs.ST_BUSY):
            if time.monotonic() > end:
                raise TimeoutError("CA core did not finish its pass")
            time.sleep(0.0005)

    # ------------------------------------------------------------ setup
    def load_grid(self, grid: np.ndarray, timeout: float = 5.0) -> None:
        """Stop, wait for a pass in flight to end, reset the generation state
        and upload the seed (into both buffers for the legacy
        cylindrical/rectangular modes). RESET_STATE is honoured only when no
        pass runs, and a pass in flight would still read and write the
        buffers, so the upload waits for it."""
        gx, gy = self.cfg["grid"]
        if np.asarray(grid).shape != (gy, gx):
            raise ValueError(f"grid shape {np.asarray(grid).shape}, expected {(gy, gx)}")
        self._ctrl(run=False, auto=False)
        self._wait_idle(timeout)
        self._ctrl(reset_state=True)
        if self._status(regs.ST_FRONT) or self.dev.read_reg(regs.REG_GEN_COUNT) != 0:
            raise IOError("CA core did not accept RESET_STATE")
        data = pack_frame(grid, self.cfg["cell_w"])
        b0, b1 = self._buffers()
        self.dev.write_mem(b0, data)
        if self.cfg["boundary"] in ("cylindrical", "rectangular"):
            self.dev.write_mem(b1, data)

    def set_params(self, params: dict) -> None:
        for k, v in enumerate(params_vector(self.cfg["rule"], params)):
            self.dev.write_reg(regs.REG_RULE_PARAM0 + 4 * k, v)

    # ------------------------------------------------------------ Lenia
    def load_kernel(self, R: float, beta, timeout: float = 5.0) -> None:
        """Stop, wait until idle, write one weight per distance class (class 0
        first) and wait until the core has shifted them in. The growth table is
        normalised by the kernel, so it is rewritten for the current mu, sigma
        and T. The caller restarts the core."""
        cfg = self.cfg
        w = lenia.kernel_weights(R, beta, cfg["nbh"], cfg.get("weight_w", lenia.DEFAULT_WEIGHT_W))
        self._ctrl(run=False, auto=False)
        self._wait_idle(timeout)
        self.dev.write_regs([(regs.REG_KERNEL_DATA, int(v)) for v in w])
        self._wait_clear(regs.ST_KERNEL_PENDING, timeout, "kernel load did not finish")
        self.weights = w
        self.set_growth(*self.growth, timeout=timeout)

    def set_growth(self, mu: float, sigma: float, T: float, timeout: float = 5.0) -> int:
        """Write the growth table and its shift to the inactive bank and commit.
        The banks swap between two passes; returns GROWTH_GEN: generations up to
        it used the previous table, every later one uses this one."""
        cfg = self.cfg
        table, sh = lenia.growth_table(mu, sigma, T, self.weights, cfg["nbh"], cfg["cell_w"],
                                       cfg.get("lut_idx_w", lenia.DEFAULT_LUT_IDX_W))
        self._wait_clear(regs.ST_GROWTH_PENDING, timeout, "previous growth commit still pending")
        self.dev.write_reg(regs.REG_GROWTH_SHIFT, sh)
        mask = (1 << (cfg["cell_w"] + 1)) - 1
        self.dev.write_regs([(regs.REG_GROWTH_TABLE + 4 * i, int(e) & mask) for i, e in enumerate(table)])
        self.dev.write_reg(regs.REG_GROWTH_COMMIT, 1)
        self._wait_clear(regs.ST_GROWTH_PENDING, timeout, "growth commit did not take effect")
        self.growth = (mu, sigma, T)
        return self.dev.read_reg(regs.REG_GROWTH_GEN)

    def set_frame_repeat(self, n: int) -> None:
        self.dev.write_reg(regs.REG_FRAME_REPEAT, n)

    def set_gens_per_frame(self, n: int) -> None:
        self.dev.write_reg(regs.REG_GENS_PER_FRAME, n)

    def set_pause(self, pause: bool) -> None:
        self._ctrl(pause=pause)

    def start(self, auto: bool = False) -> None:
        self._ctrl(run=True, auto=auto)

    def stop(self) -> None:
        self._ctrl(run=False, auto=False)

    # ---------------------------------------------------------- running
    def request_frame(self) -> None:
        self.dev.write_reg(regs.REG_FRAME_REQ, 1)

    def wait_frame(self, timeout: float = 5.0) -> int:
        """Wait until no pass is running or pending; return GEN_COUNT. Only for
        host-paced cores (XDMA, simulation): where a consumer requests passes
        (display boards) STATUS is never idle while RUN is set, use snapshot()."""
        end = time.monotonic() + timeout
        while True:
            st = self.dev.read_reg(regs.REG_STATUS)
            if not (st >> regs.ST_BUSY & 1) and not (st >> regs.ST_PENDING & 1):
                return self.dev.read_reg(regs.REG_GEN_COUNT)
            if time.monotonic() > end:
                raise TimeoutError("CA core still busy")
            time.sleep(0.0005)

    def generation(self) -> int:
        return self.dev.read_reg(regs.REG_GEN_COUNT)

    def snapshot(self, timeout: float = 5.0) -> tuple[int, np.ndarray]:
        """Return (GEN_COUNT, frame) while passes keep running, as on display
        boards. PAUSE stops commits from the next pass on, so once no pass is
        active or the pass running when PAUSE was set has ended, the front
        buffer is stable for as long as the read takes. The previous PAUSE
        setting is restored afterwards."""
        was_paused = bool(self.dev.read_reg(regs.REG_CTRL) >> regs.CTRL_PAUSE & 1)
        self._ctrl(pause=True)
        try:
            p0 = self.dev.read_reg(regs.REG_PASS_COUNT)
            end = time.monotonic() + timeout
            while self._status(regs.ST_BUSY) and self.dev.read_reg(regs.REG_PASS_COUNT) == p0:
                if time.monotonic() > end:
                    raise TimeoutError("CA core pass did not end")
                time.sleep(0.0005)
            return self.generation(), self.read_frame()
        finally:
            if not was_paused:
                self._ctrl(pause=False)

    def read_frame(self) -> np.ndarray:
        front = self.dev.read_reg(regs.REG_STATUS) >> regs.ST_FRONT & 1
        addr = self._buffers()[front]
        gx, gy = self.cfg["grid"]
        return unpack_frame(self.dev.read_mem(addr, self.frame_bytes), gx, gy, self.cfg["cell_w"])
