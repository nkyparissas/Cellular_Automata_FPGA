"""Host support for Lenia (design spec 2026-10-31, Section 7): kernel loading,
live growth changes with GROWTH_GEN, the simulated device and the CLI."""
import io
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

import compose_seed
from ca_host import cli, regs
from ca_host.controller import CAController
from ca_host.simdev import SimDevice
from ca_model import lenia
from ca_model.grids import load_seed, to_rgb
from ca_model.neigh import Boundary
from timed_device import TimedSimDevice

ROOT = Path(__file__).resolve().parents[2]
NEW_GROWTH = (0.2, 0.04, 5)


@pytest.fixture
def lcfg():
    return {"name": "lenia_tiny", "grid": [64, 32], "cell_w": 16, "nbh": 7, "boundary": "toroidal", "rule": "lenia",
            "mask": "moore", "params": {"R": 3, "T": 10, "mu": 0.15, "sigma": 0.03, "beta": [1]},
            "weight_w": 6, "lut_idx_w": 12, "palette": "viridis"}


@pytest.fixture
def lseed():
    rng = np.random.default_rng(4)
    q = rng.integers(0, 1 << 16, size=(32, 64))
    return np.where(rng.random((32, 64)) < 0.3, 0, q).astype(np.uint16)


def model(cfg, grid, w, growth):
    table, sh = lenia.growth_table(*growth, w, cfg["nbh"], cfg["cell_w"], cfg["lut_idx_w"])
    return lenia.step_lenia(grid, w, table, sh, cfg["nbh"], cfg["cell_w"], Boundary(cfg["boundary"]))


def start(ctl, seed, R, beta, growth):
    ctl.load_grid(seed)
    ctl.load_kernel(R, beta)
    g = ctl.set_growth(*growth)
    ctl.set_frame_repeat(0)
    ctl.start()
    return g


def test_info_lenia(lcfg):
    info = CAController(SimDevice(lcfg), lcfg).info()
    assert info["rule"] == "lenia"
    assert (info["classes"], info["weight_w"], info["lut_idx_w"], info["entry_w"]) == (7, 6, 12, 17)


def test_lenia_sim_matches_model(lcfg, lseed):
    ctl = CAController(SimDevice(lcfg), lcfg)
    assert start(ctl, lseed, 2, [1], NEW_GROWTH) == 0
    w = lenia.kernel_weights(2, [1], 7, 6)
    exp = lseed
    for g in range(1, 4):
        ctl.request_frame()
        assert ctl.wait_frame(timeout=1.0) == g
        exp = model(lcfg, exp, w, NEW_GROWTH)
        assert np.array_equal(ctl.read_frame(), exp), f"generation {g}"


def test_set_growth_mid_run_replays(lcfg, lseed):
    """A growth change while a pass runs takes effect after it; GROWTH_GEN marks the switch."""
    p = lcfg["params"]
    old = (p["mu"], p["sigma"], p["T"])
    dev = TimedSimDevice(lcfg, pass_len=5)
    ctl = CAController(dev, lcfg)
    start(ctl, lseed, p["R"], p["beta"], old)
    ctl.request_frame()
    assert dev.active_left, "a pass should be in flight"
    switch = ctl.set_growth(*NEW_GROWTH)
    assert switch >= 1
    w = lenia.kernel_weights(p["R"], p["beta"], 7, 6)
    exp, frames = lseed, {}
    while ctl.generation() < switch + 3:
        ctl.wait_frame(timeout=1.0)
        frames[ctl.generation()] = ctl.read_frame()
        ctl.request_frame()
    for g in range(1, switch + 4):
        exp = model(lcfg, exp, w, old if g <= switch else NEW_GROWTH)
        if g in frames:
            assert np.array_equal(frames[g], exp), f"generation {g} (switch after {switch})"


def test_set_growth_display_paced(lcfg, lseed):
    """Passes requested back to back by a display: the commit still lands between two passes."""
    p = lcfg["params"]
    dev = TimedSimDevice(lcfg, pass_len=3, display=True)
    ctl = CAController(dev, lcfg)
    start(ctl, lseed, p["R"], p["beta"], (p["mu"], p["sigma"], p["T"]))
    switch = ctl.set_growth(*NEW_GROWTH, timeout=2.0)
    assert switch <= ctl.generation()
    assert not dev.read_reg(regs.REG_STATUS) >> regs.ST_GROWTH_PENDING & 1


def test_kernel_ignored_while_running(lcfg, lseed):
    dev = SimDevice(lcfg)
    ctl = CAController(dev, lcfg)
    start(ctl, lseed, 2, [1], NEW_GROWTH)
    dev.write_reg(regs.REG_KERNEL_DATA, 0x3F)          # RUN is set: ignored
    w = lenia.kernel_weights(2, [1], 7, 6)
    ctl.request_frame()
    ctl.wait_frame(timeout=1.0)
    assert np.array_equal(ctl.read_frame(), model(lcfg, lseed, w, NEW_GROWTH))
    ctl.load_kernel(3, [1])
    assert not dev.run, "load_kernel stops the core"


def test_reset_state_keeps_lenia_configuration(lcfg, lseed):
    dev = SimDevice(lcfg)
    ctl = CAController(dev, lcfg)
    start(ctl, lseed, 2, [1], NEW_GROWTH)
    gen_before = dev.read_reg(regs.REG_GROWTH_GEN)
    ctl.load_grid(lseed)                                # writes RESET_STATE
    assert dev.read_reg(regs.REG_GROWTH_GEN) == gen_before
    ctl.start()
    ctl.request_frame()
    ctl.wait_frame(timeout=1.0)
    assert np.array_equal(ctl.read_frame(), model(lcfg, lseed, lenia.kernel_weights(2, [1], 7, 6), NEW_GROWTH))


def _cfg_file(tmp_path, cfg):
    states = compose_seed.compose((64, 32), [("orbium", 4, 10)], soups=[(0, 40, 32, 20, 0.5)], rng_seed=3)
    compose_seed.save_unit16(states, tmp_path / "seed.png")
    cfg = dict(cfg, seed=str(tmp_path / "seed.png"), seed_mode="unit16")
    (tmp_path / "cfg.json").write_text(json.dumps(cfg))
    return cfg


def test_cli_lenia_headless(tmp_path, lcfg):
    cfg = _cfg_file(tmp_path, lcfg)
    env = dict(os.environ, PYTHONPATH=f"{ROOT / 'host'}:{ROOT / 'model'}")
    r = subprocess.run([sys.executable, "-m", "ca_host.cli", "--transport", "sim", "--config", str(tmp_path / "cfg.json"),
                        "--frames", "2", "--headless", "--out", str(tmp_path / "out")],
                       capture_output=True, text=True, env=env)
    assert r.returncode == 0, r.stderr
    g = load_seed(tmp_path / "seed.png", "unit16", cell_w=16)
    w, table, sh = lenia.cfg_kernel(cfg)
    for k in range(1, 3):
        g = lenia.step_lenia(g, w, table, sh, 7, 16, Boundary.TOROIDAL)
        img = np.array(Image.open(tmp_path / "out" / f"frame_{k:05d}.png").convert("RGB"))
        assert np.array_equal(img, to_rgb(g, 16, "viridis")), f"frame {k}"


def test_cli_lenia_nudge(tmp_path, lcfg, monkeypatch, capsys):
    cfg = _cfg_file(tmp_path, lcfg)
    dev = TimedSimDevice(cfg, pass_len=3, display=True)
    monkeypatch.setattr(cli, "open_device", lambda args, c: dev)
    monkeypatch.setattr(sys, "stdin", io.StringIO("]\ns\nq\n"))
    assert cli.main(["--transport", "uart", "--config", str(tmp_path / "cfg.json"), "--headless",
                     "--out", str(tmp_path / "out")]) == 0
    out = capsys.readouterr().out
    assert re.search(r"mu=0\.151\b", out) and re.search(r"from generation \d+", out)
