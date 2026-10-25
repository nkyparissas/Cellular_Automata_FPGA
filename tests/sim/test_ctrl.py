"""Register file + pass controller (spec Sections 9 and 10)."""
import pytest

import rtlsim

CASES = ["regs_rw", "repeat_cadence", "gens_per_frame", "pause", "req_merge", "auto",
         "run_clear_midpass", "midpass_changes", "reset_state"]


@pytest.fixture(scope="module")
def tb_ctrl():
    return rtlsim.build("tb_ctrl")


@pytest.mark.parametrize("case", CASES)
def test_ctrl(tb_ctrl, case):
    rtlsim.run(tb_ctrl, {"case": case})


@pytest.mark.parametrize("case", ["regs_rw", "repeat_cadence", "reset_state"])
def test_ctrl_axil_always_ready(tb_ctrl, case):
    """BREADY/RREADY held high from the start: responses must still follow the handshakes."""
    rtlsim.run(tb_ctrl, {"case": case, "axil_early": None})
