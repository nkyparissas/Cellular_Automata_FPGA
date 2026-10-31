"""CA core with the Lenia rule (design spec 2026-10-31, Section 9.4): every
generation bit-exact against the model, kernels and growth tables loaded
through the registers, and growth commits while passes run (the table
schedule follows GROWTH_GEN)."""
import re

import numpy as np
import pytest

import compose_seed
from ca_model import lenia
from core_harness import check_against_model, make_cfg, run_core


def random_kernel(nbh, ww, rng):
    w = rng.integers(0, 1 << ww, size=lenia.num_classes(nbh))
    w[0] = 0
    w[1] = (1 << ww) - 1
    return w


def random_table(cfg, w, rng):
    """Random entries over the whole range, with the shift that spreads S over the table."""
    _, sh = lenia.growth_table(0.15, 0.03, 10, w, cfg["nbh"], cfg["cell_w"], cfg["lut_idx_w"])
    cw = cfg["cell_w"]
    return rng.integers(-(1 << cw), 1 << cw, size=1 << cfg["lut_idx_w"]), sh


def growth_gen(log):
    return int(re.search(r"TB_GROWTH_GEN=(\d+)", log).group(1))


@pytest.mark.parametrize("bnd", ["toroidal", "zero"])
def test_lenia_core_random_kernels(bnd, tmp_path):
    rng = np.random.default_rng(11)
    cfg = make_cfg("lenia", bnd, 7, 16, grid=(64, 32))
    w = random_kernel(7, 6, rng)
    t, sh = random_table(cfg, w, rng)
    seed, frames = run_core(cfg, 128, 4, tmp_path, kernel=w, table=(t, sh))
    check_against_model(cfg, seed, frames, lenia_schedule={1: (w, t, sh)})


def test_lenia_core_orbium_defaults(tmp_path):
    """Power-up kernel and table (from the configuration), no uploads."""
    p = {"R": 13, "T": 10, "mu": 0.15, "sigma": 0.015, "beta": [1]}
    cfg = make_cfg("lenia", "toroidal", 27, 16, grid=(128, 128), params=p)
    states = compose_seed.compose((128, 128), [("orbium", 40, 40)])
    seed = np.clip(np.rint(states * 65536), 0, 65535).astype(np.uint16)
    seed, frames = run_core(cfg, 128, 3, tmp_path, seed_grid=seed)
    assert frames[3].max() > 0
    check_against_model(cfg, seed, frames)


@pytest.mark.parametrize("mode", ["host", "sink"])
def test_lenia_core_growth_commit_midrun(mode, tmp_path):
    rng = np.random.default_rng(12)
    cfg = make_cfg("lenia", "toroidal", 7, 16, grid=(64, 32))
    w = random_kernel(7, 6, rng)
    t1, sh = random_table(cfg, w, rng)
    t2, _ = random_table(cfg, w, rng)
    plus = {"sink_req": 1} if mode == "sink" else {}
    seed, frames, log = run_core(cfg, 128, 4, tmp_path, kernel=w, table=(t1, sh), table2=(t2, sh - 1), gen2=2,
                                 plusargs=plus, want_log=True)
    g = growth_gen(log)
    assert g == 2, f"the commit made during generation 2 took effect after generation {g}"
    check_against_model(cfg, seed, frames, lenia_schedule={1: (w, t1, sh), g + 1: (w, t2, sh - 1)})


def test_lenia_core_commit_with_fast_forward(tmp_path):
    """GENS_PER_FRAME = 3: the commit lands while fast-forward passes remain (BUSY high)."""
    rng = np.random.default_rng(13)
    cfg = make_cfg("lenia", "toroidal", 7, 16, grid=(64, 32))
    w = random_kernel(7, 6, rng)
    t1, sh = random_table(cfg, w, rng)
    t2, _ = random_table(cfg, w, rng)
    seed, frames, log = run_core(cfg, 128, 6, tmp_path, kernel=w, table=(t1, sh), table2=(t2, sh), gen2=2,
                                 plusargs={"gpf": 3}, want_log=True)
    g = growth_gen(log)
    assert g == 2, f"the commit made during generation 2 took effect after generation {g}"
    check_against_model(cfg, seed, frames, lenia_schedule={1: (w, t1, sh), g + 1: (w, t2, sh)})


@pytest.mark.parametrize("k", range(9))
def test_lenia_core_commit_sweep(k, tmp_path):
    """The commit lands from several cycles before to several cycles after the next pass start."""
    rng = np.random.default_rng(20 + k)
    cfg = make_cfg("lenia", "toroidal", 5, 16, grid=(32, 16))
    w = random_kernel(5, 6, rng)
    t1, sh = random_table(cfg, w, rng)
    t2, _ = random_table(cfg, w, rng)
    seed, frames, log = run_core(cfg, 128, 4, tmp_path, kernel=w, table=(t1, sh), table2=(t2, sh), gen2=2,
                                 plusargs={"growth2_sweep": k}, want_log=True)
    g = growth_gen(log)
    assert g in (2, 3)
    check_against_model(cfg, seed, frames, lenia_schedule={1: (w, t1, sh), g + 1: (w, t2, sh)})


def test_lenia_core_kernel_write_ignored_while_busy(tmp_path):
    rng = np.random.default_rng(14)
    cfg = make_cfg("lenia", "toroidal", 7, 16, grid=(64, 32))
    w = random_kernel(7, 6, rng)
    t, sh = random_table(cfg, w, rng)
    seed, frames = run_core(cfg, 128, 3, tmp_path, kernel=w, table=(t, sh), plusargs={"kernel_busy": 1})
    check_against_model(cfg, seed, frames, lenia_schedule={1: (w, t, sh)})


def test_lenia_core_no_pass_while_kernel_pending(tmp_path):
    """RUN and FRAME_REQ follow the kernel writes at once; the slow engine clock keeps
    KERNEL_PENDING set for a while and the testbench fails if a pass starts meanwhile."""
    rng = np.random.default_rng(15)
    cfg = make_cfg("lenia", "toroidal", 7, 16, grid=(64, 32))
    w = random_kernel(7, 6, rng)
    t, sh = random_table(cfg, w, rng)
    seed, frames = run_core(cfg, 128, 2, tmp_path, kernel=w, table=(t, sh),
                            plusargs={"no_wait_kernel": 1, "aclk_ps": 4000, "eclk_ps": 20000})
    check_against_model(cfg, seed, frames, lenia_schedule={1: (w, t, sh)})


def test_lenia_core_memory_stalls(tmp_path):
    cfg = make_cfg("lenia", "toroidal", 7, 16, grid=(64, 32))
    seed, frames = run_core(cfg, 128, 3, tmp_path, plusargs={"mem_stall": 70, "mem_lat": 40,
                                                             "aclk_ps": 4000, "eclk_ps": 6000})
    check_against_model(cfg, seed, frames)


def test_lenia_core_8bit(tmp_path):
    rng = np.random.default_rng(16)
    cfg = make_cfg("lenia", "toroidal", 5, 8, grid=(64, 24))
    w = random_kernel(5, 6, rng)
    t, sh = random_table(cfg, w, rng)
    seed, frames = run_core(cfg, 64, 3, tmp_path, kernel=w, table=(t, sh))
    check_against_model(cfg, seed, frames, lenia_schedule={1: (w, t, sh)})


def test_lenia_core_bad_params_fail_elab(tmp_path):
    cfg = make_cfg("lenia", "toroidal", 5, 16, grid=(32, 16))
    cfg["weight_w"] = 16
    with pytest.raises(RuntimeError) as e:
        run_core(cfg, 128, 1, tmp_path)
    assert "WEIGHT_W" in str(e.value)
