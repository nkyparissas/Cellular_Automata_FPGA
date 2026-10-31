"""Drives sim/tb/tb_core.sv for a configuration and compares every dumped
generation with the golden model."""
import hashlib
import json
from pathlib import Path

import numpy as np

import rtlsim
from ca_model import lenia
from ca_model.grids import cell_dtype
from ca_model.neigh import Boundary
from ca_model.step import step
from gen_cfg import gen_cfg_svh, frame_to_hex, hex_to_frame

BND = {"toroidal": 0, "cylindrical": 1, "rectangular": 2, "zero": 3}


def default_params(rule, nbh):
    if rule == "hodgepodge":
        return {"G": 20, "K": 3}
    if rule == "ghm":
        return {"T": 2, "STATES": 15, "E": 1}
    if rule == "lenia":
        return {"R": (nbh - 1) // 2, "T": 10, "mu": 0.15, "sigma": 0.03, "beta": [1]}
    nn = nbh * nbh
    return {"LO1": nn // 4, "HI1": nn // 4 + 2, "LO2": nn // 2, "HI2": nn // 2 + nbh, "ALIVE": 1}


def random_seed(rule, cell_w, shape, rng):
    maxv = (1 << cell_w) - 1
    if rule == "hodgepodge":
        return rng.choice([0, 0, 0, 1, maxv // 5, maxv // 2, maxv - 1, maxv], size=shape).astype(cell_dtype(cell_w))
    if rule == "ghm":
        return rng.choice([0, 0, 0, 1, 1, 2, 7, min(14, maxv)], size=shape).astype(cell_dtype(cell_w))
    if rule == "lenia":
        q = rng.integers(0, maxv + 1, size=shape)
        return np.where(rng.random(shape) < 0.3, 0, q).astype(cell_dtype(cell_w))
    return rng.integers(0, 2, size=shape).astype(cell_dtype(cell_w))


def make_cfg(rule, bnd, nbh, cell_w, grid=(64, 24), mask="moore", params=None):
    cfg = {"name": f"{rule}_{bnd}_n{nbh}_c{cell_w}", "grid": list(grid), "cell_w": cell_w, "nbh": nbh,
           "boundary": bnd, "rule": rule, "mask": mask, "params": params or default_params(rule, nbh)}
    if rule == "lenia":
        cfg.update(weight_w=lenia.DEFAULT_WEIGHT_W, lut_idx_w=lenia.DEFAULT_LUT_IDX_W)
    return cfg


def _table_hex(entries, cell_w):
    ew = cell_w + 1
    return "".join(f"{int(e) & ((1 << ew) - 1):0{(ew + 3) // 4}x}\n" for e in entries)


def run_core(cfg, data_w, gens, tmp: Path, seed_grid=None, plusargs=None, dump_gens=None,
             rng_seed=1, timeout_s=1800, kernel=None, table=None, table2=None, gen2=None, want_log=False):
    """Build tb_core for cfg, run `gens` generations, return (seed, dict gen -> frame), plus the
    testbench log when want_log. Lenia uploads: kernel (class weights, class 0 first) and
    table = (entries, sh) are written before RUN; table2 = (entries, sh) goes to the inactive
    bank as well and is committed during generation gen2."""
    tmp.mkdir(parents=True, exist_ok=True)
    gx, gy = cfg["grid"]
    if seed_grid is None:
        seed_grid = random_seed(cfg["rule"], cfg["cell_w"], (gy, gx), np.random.default_rng(rng_seed))
    key = hashlib.sha1(json.dumps([cfg, data_w], sort_keys=True).encode()).hexdigest()[:12]
    cfg_dir = rtlsim.ROOT / "build" / "core_cfg" / key
    cfg_dir.mkdir(parents=True, exist_ok=True)
    gen_cfg_svh(cfg, data_w, cfg_dir / "ca_cfg.svh")
    (tmp / "seed.hex").write_text("\n".join(frame_to_hex(seed_grid, cfg["cell_w"], data_w)) + "\n")
    binary = rtlsim.build("tb_core", extra=("+incdir+" + str(cfg_dir),))
    dump_gens = list(range(1, gens + 1)) if dump_gens is None else dump_gens
    dump_dir = tmp / "dumps"
    dump_dir.mkdir(exist_ok=True)
    args = {"seed_hex": tmp / "seed.hex", "gens": gens, "dump_gens": ",".join(map(str, dump_gens)) + ",",
            "dump_dir": str(dump_dir) + "/"}
    if kernel is not None:
        (tmp / "kernel.hex").write_text("".join(f"{int(v):x}\n" for v in kernel))
        args["kernel_hex"] = tmp / "kernel.hex"
    for name, tab in (("growth", table), ("growth2", table2)):
        if tab is not None:
            (tmp / f"{name}.hex").write_text(_table_hex(tab[0], cfg["cell_w"]))
            args[f"{name}_hex"] = tmp / f"{name}.hex"
            args[f"{name}_sh"] = tab[1]
    if gen2 is not None:
        args["growth2_gen"] = gen2
    args.update(plusargs or {})
    log = rtlsim.run(binary, args, timeout_s=timeout_s)
    out = {}
    for g in dump_gens:
        lines = (dump_dir / f"gen_{g:05d}.hex").read_text().split()
        out[g] = hex_to_frame(lines, gx, gy, cfg["cell_w"], data_w)
    return (seed_grid, out, log) if want_log else (seed_grid, out)


def check_against_model(cfg, seed_grid, frames, param_schedule=None, lenia_schedule=None):
    """param_schedule: optional dict gen -> params dict applied from that generation on.
    lenia_schedule: optional dict gen -> (weights, table, sh) applied from that generation on."""
    g = seed_grid.copy()
    for gen in range(1, max(frames) + 1):
        c = dict(cfg)
        if param_schedule:
            for start in sorted(param_schedule):
                if gen >= start:
                    c["params"] = param_schedule[start]
        if lenia_schedule:
            w, table, sh = lenia_schedule[max(s for s in lenia_schedule if s <= gen)]
            g = lenia.step_lenia(g, w, table, sh, cfg["nbh"], cfg["cell_w"], Boundary(cfg["boundary"]))
        else:
            g = step(g, c)
        if gen in frames and not np.array_equal(frames[gen], g):
            diff = np.argwhere(frames[gen] != g)
            y, x = diff[0]
            raise AssertionError(f"generation {gen}: {len(diff)} cells differ, first at row {y} col {x}: "
                                 f"rtl {frames[gen][y, x]} model {g[y, x]}")
