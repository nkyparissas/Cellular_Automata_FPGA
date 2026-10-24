"""Experiment configuration files (spec Section 17)."""
import json
from pathlib import Path

from .neigh import Boundary
from .rules import PARAM_INDEX

ROOT = Path(__file__).resolve().parents[2]
REQUIRED = ("name", "grid", "cell_w", "nbh", "boundary", "rule", "mask", "params",
            "seed", "seed_mode", "palette")


def load(path) -> dict:
    """Read and validate a configuration; the seed path is made absolute."""
    cfg = json.loads(Path(path).read_text())
    missing = [k for k in REQUIRED if k not in cfg]
    if missing:
        raise ValueError(f"{path}: missing keys {missing}")
    Boundary(cfg["boundary"])
    if cfg["rule"] not in PARAM_INDEX:
        raise ValueError(f"{path}: unknown rule {cfg['rule']!r}")
    unknown = set(cfg["params"]) - set(PARAM_INDEX[cfg["rule"]])
    if unknown:
        raise ValueError(f"{path}: unknown parameters {sorted(unknown)}")
    if cfg["nbh"] % 2 == 0 or cfg["nbh"] < 3:
        raise ValueError(f"{path}: nbh must be odd and >= 3")
    if cfg["seed_mode"] == "binary" and "seed_value" not in cfg:
        raise ValueError(f"{path}: binary seed mode needs seed_value")
    seed = Path(cfg["seed"])
    cfg["seed"] = str(seed if seed.is_absolute() else ROOT / seed)
    return cfg
