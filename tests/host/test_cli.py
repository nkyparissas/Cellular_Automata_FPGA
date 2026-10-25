"""ca_host.cli in headless mode on the simulated device."""
import io
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from ca_host import cli
from ca_model.grids import load_seed, to_rgb
from ca_model.step import step
from timed_device import TimedSimDevice

ROOT = Path(__file__).resolve().parents[2]


def test_cli_display_board(tmp_path, small_cfg, monkeypatch, capsys):
    """The documented UART command on a display board, where the display requests
    a pass every frame so STATUS never reads idle: the CLI loads and starts the
    run, takes a consistent snapshot on 's', and on 'q' leaves the board running."""
    seed_img = Image.fromarray((np.random.default_rng(3).random((24, 32)) < 0.3).astype(np.uint8), "P")
    seed_img.putpalette([0, 0, 0, 255, 255, 255] + [0, 0, 0] * 254)
    seed_img.save(tmp_path / "seed.bmp")
    cfg = dict(small_cfg, seed=str(tmp_path / "seed.bmp"), seed_mode="binary", seed_value=200, palette="legacy8")
    (tmp_path / "cfg.json").write_text(json.dumps(cfg))
    dev = TimedSimDevice(cfg, pass_len=3, display=True)
    monkeypatch.setattr(cli, "open_device", lambda args, cfg: dev)
    monkeypatch.setattr(sys, "stdin", io.StringIO("+\ns\nq\n"))
    assert cli.main(["--transport", "uart", "--config", str(tmp_path / "cfg.json"), "--headless",
                     "--out", str(tmp_path / "out")]) == 0
    assert dev.run and not dev.pause, "quitting must leave the board running, unpaused"
    gen = int(re.search(r"snapshot 1: generation (\d+)", capsys.readouterr().out).group(1))
    assert gen > 0
    g = load_seed(tmp_path / "seed.bmp", "binary", 200)
    for _ in range(gen):
        g = step(g, cfg)
    img = np.array(Image.open(tmp_path / "out" / "frame_00001.png").convert("RGB"))
    assert np.array_equal(img, to_rgb(g, 8, "legacy8"))


def test_cli_headless_sim(tmp_path, small_cfg):
    seed_img = Image.fromarray((np.random.default_rng(2).random((24, 32)) < 0.3).astype(np.uint8), "P")
    seed_img.putpalette([0, 0, 0, 255, 255, 255] + [0, 0, 0] * 254)
    seed_img.save(tmp_path / "seed.bmp")
    cfg = dict(small_cfg, seed=str(tmp_path / "seed.bmp"), seed_mode="binary", seed_value=200, palette="legacy8")
    (tmp_path / "cfg.json").write_text(json.dumps(cfg))
    env = dict(os.environ, PYTHONPATH=f"{ROOT / 'host'}:{ROOT / 'model'}")
    r = subprocess.run([sys.executable, "-m", "ca_host.cli", "--transport", "sim", "--config", str(tmp_path / "cfg.json"),
                        "--frames", "4", "--headless", "--out", str(tmp_path / "out")],
                       capture_output=True, text=True, env=env)
    assert r.returncode == 0, r.stderr
    g = load_seed(tmp_path / "seed.bmp", "binary", 200)
    for k in range(1, 5):
        g = step(g, cfg)
        img = np.array(Image.open(tmp_path / "out" / f"frame_{k:05d}.png").convert("RGB"))
        assert np.array_equal(img, to_rgb(g, 8, "legacy8")), f"frame {k}"
