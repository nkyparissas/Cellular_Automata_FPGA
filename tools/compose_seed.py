"""Compose a Lenia seed from creatures (data/patterns) and random soups and save
it as a 16-bit greyscale PNG (seed_mode "unit16": grey value / 65535 = state).

Example:
    python3 tools/compose_seed.py --pattern orbium@150,200 --pattern orbium@650,1150 \\
        --soup 400,1400,200,300,0.3 --out data/seeds/my_seed.png
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "model"))

from ca_model.lenia import load_pattern  # noqa: E402


def _stamp(states: np.ndarray, block: np.ndarray, row: int, col: int) -> None:
    """Place block with its top-left cell at (row, col), wrapping around the canvas;
    overlapping cells keep the larger state."""
    ys = (row + np.arange(block.shape[0])) % states.shape[0]
    xs = (col + np.arange(block.shape[1])) % states.shape[1]
    states[np.ix_(ys, xs)] = np.maximum(states[np.ix_(ys, xs)], block)


def compose(canvas: tuple[int, int], placements: list[tuple[str, int, int]],
            soups: list[tuple[int, int, int, int, float]] = (), rng_seed: int = 0) -> np.ndarray:
    """States in [0, 1] on a canvas of (width, height). placements: (pattern, row, col);
    soups: (row, col, height, width, density), a fraction density of the cells set
    to uniform random states in (0, 1]."""
    width, height = canvas
    states = np.zeros((height, width))
    for name, row, col in placements:
        _stamp(states, load_pattern(name)["cells"], row, col)
    rng = np.random.default_rng(rng_seed)
    for row, col, h, w, density in soups:
        block = np.where(rng.random((h, w)) < density, 1.0 - rng.random((h, w)), 0.0)
        _stamp(states, block, row, col)
    return states


def save_unit16(states: np.ndarray, path) -> None:
    v = np.clip(np.rint(np.asarray(states) * 65535), 0, 65535).astype(np.uint16)
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(v).save(path)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--canvas", default="1920x1080", help="WIDTHxHEIGHT (default 1920x1080)")
    ap.add_argument("--pattern", action="append", default=[], metavar="NAME@ROW,COL",
                    help="place data/patterns/NAME.json with its top-left cell at ROW,COL (repeatable)")
    ap.add_argument("--soup", action="append", default=[], metavar="ROW,COL,H,W,DENSITY",
                    help="random soup block (repeatable)")
    ap.add_argument("--rng-seed", type=int, default=0)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    width, height = (int(v) for v in args.canvas.lower().split("x"))
    placements = []
    for spec in args.pattern:
        name, pos = spec.split("@")
        row, col = (int(v) for v in pos.split(","))
        placements.append((name, row, col))
    soups = []
    for spec in args.soup:
        row, col, h, w, density = spec.split(",")
        soups.append((int(row), int(col), int(h), int(w), float(density)))
    save_unit16(compose((width, height), placements, soups, args.rng_seed), args.out)
    print(f"wrote {args.out} ({width}x{height}, {len(placements)} creatures, {len(soups)} soups)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
