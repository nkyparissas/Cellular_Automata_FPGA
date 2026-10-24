"""Experiment configurations and the model command-line runner."""
import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from ca_model import config

ROOT = Path(__file__).resolve().parents[2]
CONFIGS = sorted((ROOT / "configs").glob("*.json"))


def test_expected_experiments_present():
    names = {p.stem for p in CONFIGS}
    assert {"hodgepodge29", "hodgepodge19", "ghm_circle_toroidal", "ghm_vn_toroidal",
            "ghm_moore_cylindrical", "ap_toroidal"} <= names


@pytest.mark.parametrize("path", CONFIGS, ids=lambda p: p.stem)
def test_all_configs_load(path):
    cfg = config.load(path)
    assert Path(cfg["seed"]).is_file()
    assert cfg["grid"] == [1920, 1080]


def test_load_rejects_missing_key(tmp_path):
    p = tmp_path / "bad.json"
    p.write_text(json.dumps({"name": "bad"}))
    with pytest.raises(ValueError):
        config.load(p)


def test_cli_small_run(tmp_path):
    seed = tmp_path / "seed.bmp"
    img = Image.fromarray((np.random.default_rng(0).random((24, 32)) < 0.3).astype(np.uint8), "P")
    img.putpalette([0, 0, 0, 255, 255, 255] + [0, 0, 0] * 254)
    img.save(seed)
    cfg = {"name": "tiny", "grid": [32, 24], "cell_w": 8, "nbh": 5, "boundary": "toroidal",
           "rule": "hodgepodge", "mask": "moore", "params": {"G": 20, "K": 3},
           "seed": str(seed), "seed_mode": "binary", "seed_value": 200, "palette": "legacy8"}
    cp = tmp_path / "tiny.json"
    cp.write_text(json.dumps(cfg))
    out = tmp_path / "out"
    env = dict(os.environ, PYTHONPATH=str(ROOT / "model"))
    r = subprocess.run([sys.executable, "-m", "ca_model.run", "--config", str(cp), "--gens", "3",
                        "--out", str(out)], capture_output=True, text=True, env=env)
    assert r.returncode == 0, r.stderr
    assert (out / "gen_00003.png").is_file() and (out / "gen_00000.png").is_file()
    g3 = np.load(out / "gen_00003.npy")
    assert g3.shape == (24, 32) and g3.dtype == np.uint8
