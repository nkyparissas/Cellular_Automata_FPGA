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
