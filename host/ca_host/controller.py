"""High-level control of a CA core over any Device transport."""
import time

import numpy as np

from ca_model.grids import pack_frame, unpack_frame
from ca_model.rules import params_vector

from . import regs
from .device import Device

BOUNDARIES = ["toroidal", "cylindrical", "rectangular", "zero"]
RULES = ["hodgepodge", "ghm", "interval"]


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

    def info(self) -> dict:
        dim = self.dev.read_reg(regs.REG_GRID_DIM)
        c = self.dev.read_reg(regs.REG_CORE_CFG)
        return {"grid_x": dim & 0xFFFF, "grid_y": dim >> 16, "cell_w": c & 0xFF, "nbh": (c >> 8) & 0xFF,
                "boundary": BOUNDARIES[(c >> 16) & 3], "rule": RULES[(c >> 20) & 0xF] if (c >> 20) & 0xF < 3 else "?",
                "data_bytes": c >> 24}

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
