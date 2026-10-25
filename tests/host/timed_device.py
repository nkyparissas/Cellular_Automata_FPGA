"""A SimDevice whose passes take time, as on hardware (test utility).

A pass started by the controller logic stays active for ``pass_len`` register
accesses and commits when it ends; a RESET_STATE written meanwhile is ignored,
as in rtl/ctrl/ca_controller.sv. With ``display=True`` a consumer requests a
pass continuously (a video output asks for one every frame), so passes run
back to back while RUN is set and PENDING never clears.
"""
from ca_host import regs
from ca_host.simdev import SimDevice


class TimedSimDevice(SimDevice):
    def __init__(self, cfg: dict, pass_len: int = 5, display: bool = False, **kw):
        super().__init__(cfg, **kw)
        self.pass_len, self.display = pass_len, display
        self.active_left, self.active_commit = 0, False

    def read_reg(self, off: int) -> int:
        self._tick()
        v = super().read_reg(off)
        if off == regs.REG_STATUS and self.active_left:
            v |= 1 << regs.ST_BUSY
        return v

    def write_reg(self, off: int, val: int) -> None:
        self._tick()
        if off == regs.REG_CTRL and self.active_left:
            val &= ~(1 << regs.CTRL_RESET_STATE)
        super().write_reg(off, val)

    def _tick(self) -> None:
        if self.display:
            self.pending = True
        if self.active_left:
            self.active_left -= 1
            if self.active_left == 0:
                self._pass(self.active_commit)
        self._service()

    def _service(self) -> None:
        """Start at most one pass (same decisions as SimDevice); it ends in _tick."""
        if self.active_left or not self.run:
            return
        if self.pause:
            self.ff_left = 0
        if self.ff_left:
            self.ff_left -= 1
            commit = True
        elif self.pending:
            commit = not self.pause and self.repeat_cnt >= self.frame_repeat
            self.pending = False
            if commit:
                self.repeat_cnt = 0
                self.ff_left = max(self.gens_per_frame, 1) - 1
            elif not self.pause:
                self.repeat_cnt = min(self.repeat_cnt + 1, 0xFFFF)
        else:
            return
        self.active_commit, self.active_left = commit, self.pass_len
