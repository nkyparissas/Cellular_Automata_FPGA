"""Self-checks of the SystemVerilog verification models."""
import pytest

import rtlsim


@pytest.fixture(scope="module")
def tb_models():
    return rtlsim.build("tb_models")


@pytest.mark.parametrize("stall", [0, 50])
def test_models_selfcheck(tb_models, stall):
    out = rtlsim.run(tb_models, {"mem_stall": stall, "mem_lat": 20, "sink_stall": stall})
    assert "frames=2" in out


def test_mem_model_flags_4k_crossing(tb_models):
    with pytest.raises(AssertionError) as e:
        rtlsim.run(tb_models, {"bad_burst": 1})
    assert "4KB" in str(e.value)
