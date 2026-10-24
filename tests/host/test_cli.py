"""ca_host.cli in headless mode on the simulated device."""
import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from ca_model.grids import load_seed, to_rgb
from ca_model.step import step

ROOT = Path(__file__).resolve().parents[2]


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
