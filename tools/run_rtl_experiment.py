"""Run an experiment configuration on the RTL (tb_core, Verilator) at full size.

Every dumped generation is compared with the golden model, which is either
recomputed or taken from build/exp/<name>/gen_<n>.npy when available.

Example:
    python3 tools/run_rtl_experiment.py --config configs/hodgepodge29.json --gens 3 --dump-every 1
"""
import argparse
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "model"), str(ROOT / "tools")]

import numpy as np  # noqa: E402

import rtlsim  # noqa: E402
from ca_model import config  # noqa: E402
from ca_model.grids import load_seed, save_png  # noqa: E402
from ca_model.step import step  # noqa: E402
from gen_cfg import frame_to_hex, gen_cfg_svh, hex_to_frame  # noqa: E402


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--config", required=True)
    ap.add_argument("--gens", type=int, required=True)
    ap.add_argument("--dump-every", type=int, default=0, help="dump period (default: last generation only)")
    ap.add_argument("--data-w", type=int, default=128)
    ap.add_argument("--threads", type=int, default=1, help="Verilator --threads")
    args = ap.parse_args(argv)

    cfg = config.load(args.config)
    gx, gy = cfg["grid"]
    out = ROOT / "build" / "rtl_exp" / cfg["name"]
    (out / "dumps").mkdir(parents=True, exist_ok=True)
    cfg_dir = out / "cfg"
    cfg_dir.mkdir(exist_ok=True)
    gen_cfg_svh(cfg, args.data_w, cfg_dir / "ca_cfg.svh")
    seed = load_seed(cfg["seed"], cfg["seed_mode"], cfg.get("seed_value"))
    (out / "seed.hex").write_text("\n".join(frame_to_hex(seed, cfg["cell_w"], args.data_w)) + "\n")

    dumps = sorted({args.gens} | (set(range(args.dump_every, args.gens + 1, args.dump_every))
                                  if args.dump_every else set()))
    extra = ["+incdir+" + str(cfg_dir)]
    if args.threads > 1:
        extra += ["--threads", str(args.threads)]
    t0 = time.perf_counter()
    binary = rtlsim.build("tb_core", extra=tuple(extra), out_dir=out / "sim")
    t_build = time.perf_counter() - t0
    t0 = time.perf_counter()
    rtlsim.run(binary, {"seed_hex": out / "seed.hex", "gens": args.gens,
                        "dump_gens": ",".join(map(str, dumps)) + ",", "dump_dir": str(out / "dumps") + "/",
                        "max_kcycles": args.gens * 8_000 + 1_000},
               timeout_s=10 * 24 * 3600)
    t_run = time.perf_counter() - t0
    msg = [f"{cfg['name']}: build {t_build:.0f} s, {args.gens} generations in {t_run:.0f} s "
           f"({t_run / args.gens:.1f} s/gen)"]

    model = seed.copy()
    ref_dir = ROOT / "build" / "exp" / cfg["name"]
    ok = True
    for g in range(1, args.gens + 1):
        cached = ref_dir / f"gen_{g:05d}.npy"
        if g in dumps and cached.is_file():
            model = np.load(cached)
        else:
            model = step(model, cfg)
        if g not in dumps:
            continue
        lines = (out / "dumps" / f"gen_{g:05d}.hex").read_text().split()
        rtl = hex_to_frame(lines, gx, gy, cfg["cell_w"], args.data_w)
        np.save(out / f"gen_{g:05d}.npy", rtl)
        save_png(rtl, cfg["cell_w"], cfg["palette"], out / f"gen_{g:05d}.png")
        diff = np.argwhere(rtl != model)
        if len(diff):
            ok = False
            y, x = diff[0]
            msg.append(f"gen {g}: MISMATCH ({len(diff)} cells, first at row {y} col {x}: "
                       f"rtl {rtl[y, x]} model {model[y, x]})")
        else:
            msg.append(f"gen {g}: MATCH")
    (out / "timing.txt").write_text("\n".join(msg) + "\n")
    print("\n".join(msg))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
