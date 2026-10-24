"""CA core integration: every generation bit-exact against the golden model."""
import pytest

import rtlsim
from core_harness import check_against_model, make_cfg, run_core

RULE_CELL = {"hodgepodge": 8, "ghm": 4, "interval": 4}
MATRIX = [(rule, bnd, nbh, RULE_CELL[rule], 64 if (nbh + len(bnd)) % 2 else 128)
          for rule in RULE_CELL for bnd in ("toroidal", "cylindrical", "rectangular", "zero") for nbh in (3, 5, 7)]
CROSS = [("hodgepodge", "toroidal", 5, 4, 128), ("ghm", "zero", 5, 8, 64), ("interval", "cylindrical", 3, 8, 128)]


@pytest.mark.parametrize("rule,bnd,nbh,cell_w,data_w", MATRIX + CROSS,
                         ids=[f"{r}-{b}-n{n}-c{c}-d{d}" for r, b, n, c, d in MATRIX + CROSS])
def test_core_matrix(rule, bnd, nbh, cell_w, data_w, tmp_path):
    cfg = make_cfg(rule, bnd, nbh, cell_w)
    seed, frames = run_core(cfg, data_w, 4, tmp_path)
    check_against_model(cfg, seed, frames)


@pytest.mark.parametrize("aclk_ps,eclk_ps", [(4000, 6000), (6000, 4000)])
def test_core_memory_stalls(aclk_ps, eclk_ps, tmp_path):
    cfg = make_cfg("hodgepodge", "toroidal", 5, 8)
    seed, frames = run_core(cfg, 128, 3, tmp_path, plusargs={"mem_stall": 70, "mem_lat": 40,
                                                             "aclk_ps": aclk_ps, "eclk_ps": eclk_ps})
    check_against_model(cfg, seed, frames)


def test_core_consumer_backpressure(tmp_path):
    cfg = make_cfg("ghm", "zero", 5, 4)
    seed, frames = run_core(cfg, 64, 3, tmp_path, plusargs={"sink_req": 1, "sink_stall": 90})
    check_against_model(cfg, seed, frames)


def test_core_param_change_between_passes(tmp_path):
    cfg = make_cfg("hodgepodge", "toroidal", 3, 8)
    new = {"G": cfg["params"]["G"] + 7, "K": cfg["params"]["K"]}
    seed, frames = run_core(cfg, 128, 4, tmp_path, plusargs={"midpass_param": 1})
    check_against_model(cfg, seed, frames, param_schedule={1: cfg["params"], 3: new})


def test_core_bad_params_fail_elab(tmp_path):
    cfg = make_cfg("hodgepodge", "toroidal", 3, 8, grid=(30, 8))
    with pytest.raises(RuntimeError) as e:
        run_core(cfg, 128, 1, tmp_path)
    assert "GRID_X*CELL_W" in str(e.value)
