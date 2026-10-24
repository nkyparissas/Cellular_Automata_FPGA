"""In-process stand-in for a CA core: the register semantics of spec
Sections 9 and 10 with passes computed by the golden model. Passes run
synchronously when FRAME_REQ is written; CTRL.AUTO is not modelled."""
import numpy as np

from ca_model.grids import pack_frame, unpack_frame
from ca_model.rules import PARAM_INDEX, params_vector
from ca_model.step import step

from . import regs
from .device import Device

BOUNDARY_ID = {"toroidal": 0, "cylindrical": 1, "rectangular": 2, "zero": 3}
RULE_ID = {"hodgepodge": 0, "ghm": 1, "interval": 2}


class SimDevice(Device):
    def __init__(self, cfg: dict, data_w: int = 128):
        self.cfg = dict(cfg)
        gx, gy = cfg["grid"]
        self.frame_bytes = gx * gy * cfg["cell_w"] // 8
        self.data_w = data_w
        self.mem = bytearray()
        self.run = self.pause = self.auto = False
        self.frame_repeat, self.gens_per_frame = 0, 1
        self.buf = [0, ((self.frame_bytes + 4095) // 4096) * 4096]
        self.params = params_vector(cfg["rule"], cfg["params"])
        self.front = self.gen_count = self.pass_count = 0
        self.repeat_cnt = self.ff_left = 0
        self.pending = False

    # ----------------------------------------------------------- memory
    def _ensure(self, end: int) -> None:
        if len(self.mem) < end:
            self.mem.extend(bytes(end - len(self.mem)))

    def read_mem(self, addr: int, n: int) -> bytes:
        self._ensure(addr + n)
        return bytes(self.mem[addr:addr + n])

    def write_mem(self, addr: int, data: bytes) -> None:
        self._ensure(addr + len(data))
        self.mem[addr:addr + len(data)] = data

    # -------------------------------------------------------- registers
    def read_reg(self, off: int) -> int:
        c = self.cfg
        if off == regs.REG_ID:
            return regs.CA_ID
        if off == regs.REG_CTRL:
            return (self.run << regs.CTRL_RUN) | (self.pause << regs.CTRL_PAUSE) | (self.auto << regs.CTRL_AUTO)
        if off == regs.REG_STATUS:
            busy = self.ff_left > 0 and self.run and not self.pause
            return (busy << regs.ST_BUSY) | (self.front << regs.ST_FRONT) | (self.pending << regs.ST_PENDING)
        if off == regs.REG_FRAME_REPEAT:
            return self.frame_repeat
        if off == regs.REG_GENS_PER_FRAME:
            return self.gens_per_frame
        if off == regs.REG_GEN_COUNT:
            return self.gen_count & 0xFFFFFFFF
        if off == regs.REG_PASS_COUNT:
            return self.pass_count & 0xFFFFFFFF
        if off in (regs.REG_BUF0_LO, regs.REG_BUF0_HI, regs.REG_BUF1_LO, regs.REG_BUF1_HI):
            v = self.buf[(off - regs.REG_BUF0_LO) // 8]
            return (v >> 32) if (off % 8) else (v & 0xFFFFFFFF)
        if off == regs.REG_GRID_DIM:
            return (c["grid"][1] << 16) | c["grid"][0]
        if off == regs.REG_CORE_CFG:
            return ((self.data_w // 8) << 24) | (RULE_ID[c["rule"]] << 20) | \
                   (BOUNDARY_ID[c["boundary"]] << 16) | (c["nbh"] << 8) | c["cell_w"]
        if regs.REG_RULE_PARAM0 <= off < regs.REG_RULE_PARAM0 + 32:
            return self.params[(off - regs.REG_RULE_PARAM0) // 4]
        return 0

    def write_reg(self, off: int, val: int) -> None:
        val &= 0xFFFFFFFF
        if off == regs.REG_CTRL:
            self.run = bool(val >> regs.CTRL_RUN & 1)
            self.pause = bool(val >> regs.CTRL_PAUSE & 1)
            self.auto = bool(val >> regs.CTRL_AUTO & 1)
            if val >> regs.CTRL_RESET_STATE & 1:
                self.front = self.gen_count = self.pass_count = self.repeat_cnt = self.ff_left = 0
                self.pending = False
        elif off == regs.REG_FRAME_REQ:
            self.pending = True
        elif off == regs.REG_FRAME_REPEAT:
            self.frame_repeat = val & 0xFFFF
        elif off == regs.REG_GENS_PER_FRAME:
            self.gens_per_frame = val & 0xFFFF
        elif off in (regs.REG_BUF0_LO, regs.REG_BUF0_HI, regs.REG_BUF1_LO, regs.REG_BUF1_HI):
            k = (off - regs.REG_BUF0_LO) // 8
            if off % 8:
                self.buf[k] = (self.buf[k] & 0xFFFFFFFF) | (val << 32)
            else:
                self.buf[k] = (self.buf[k] & ~0xFFFFFFFF) | val
        elif regs.REG_RULE_PARAM0 <= off < regs.REG_RULE_PARAM0 + 32:
            self.params[(off - regs.REG_RULE_PARAM0) // 4] = val
        self._service()

    # ----------------------------------------------------------- passes
    def _service(self) -> None:
        while self.run:
            if self.pause:
                self.ff_left = 0
            if self.ff_left:
                self.ff_left -= 1
                self._pass(commit=True)
            elif self.pending:
                commit = not self.pause and self.repeat_cnt >= self.frame_repeat
                self.pending = False
                if commit:
                    self.repeat_cnt = 0
                    self.ff_left = max(self.gens_per_frame, 1) - 1
                elif not self.pause:
                    self.repeat_cnt = min(self.repeat_cnt + 1, 0xFFFF)
                self._pass(commit)
            else:
                break

    def _pass(self, commit: bool) -> None:
        self.pass_count += 1
        if not commit:
            return
        gx, gy = self.cfg["grid"]
        cw = self.cfg["cell_w"]
        names = {i: n for n, i in PARAM_INDEX[self.cfg["rule"]].items()}
        cfg = dict(self.cfg, params={names[i]: v for i, v in enumerate(self.params) if i in names})
        grid = unpack_frame(self.read_mem(self.buf[self.front], self.frame_bytes), gx, gy, cw)
        self.write_mem(self.buf[1 - self.front], pack_frame(step(grid, cfg), cw))
        self.front ^= 1
        self.gen_count += 1
