"""Run a configuration for a number of generations and save PNG/NPY snapshots.

Example:
    python3 -m ca_model.run --config configs/hodgepodge29.json --gens 1000 --png-every 250
"""
import argparse
import time
from pathlib import Path

import numpy as np

from . import config
from .grids import load_seed, save_png
from .step import run


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--config", required=True)
    ap.add_argument("--gens", type=int, required=True)
    ap.add_argument("--png-every", type=int, default=0, help="snapshot period (default: last only)")
    ap.add_argument("--out", default=None, help="output directory (default build/exp/<name>)")
    args = ap.parse_args(argv)

    cfg = config.load(args.config)
    out = Path(args.out) if args.out else config.ROOT / "build" / "exp" / cfg["name"]
    out.mkdir(parents=True, exist_ok=True)
    grid = load_seed(cfg["seed"], cfg["seed_mode"], cfg.get("seed_value"))
    x, y = cfg["grid"]
    if grid.shape != (y, x):
        raise SystemExit(f"seed is {grid.shape[1]}x{grid.shape[0]}, config expects {x}x{y}")

    def snapshot(gen, g):
        np.save(out / f"gen_{gen:05d}.npy", g)
        save_png(g, cfg["cell_w"], cfg["palette"], out / f"gen_{gen:05d}.png")

    every = args.png_every

    def callback(gen, g):
        if gen == args.gens or (every and gen % every == 0):
            snapshot(gen, g)

    snapshot(0, grid)
    t0 = time.perf_counter()
    run(grid, cfg, args.gens, callback)
    dt = time.perf_counter() - t0
    msg = f"{cfg['name']}: {args.gens} generations in {dt:.1f} s ({dt / max(args.gens, 1) * 1e3:.1f} ms/gen) -> {out}"
    (out / "timing.txt").write_text(msg + "\n")
    print(msg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
