"""Bit-exact Lenia rule (design spec 2026-10-31, Section 5).

This module is the only implementation of the distance-class map, the
quantised class weights and the growth table; the model, the host and
tools/gen_cfg.py all use it. A cell holds q in [0, 2^cw - 1] (state q / 2^cw).

    S   = sum over window cells of w[class(i, j)] * q            (exact)
    idx = min(S >> sh, len(table) - 1)
    q'  = clamp(q_centre + table[idx], 0, 2^cw - 1)

The class of window offset (i, j) is the rank of d = i^2 + j^2 among the
distinct values of d <= R_max^2 (class 0 is the centre); offsets outside
that disk belong to no class.
"""
import functools
import json
from pathlib import Path

import numpy as np

from .grids import cell_dtype
from .neigh import Boundary, _pad

LENIA_PARAMS = ("R", "T", "mu", "sigma", "beta")
DEFAULT_WEIGHT_W = 6
DEFAULT_LUT_IDX_W = 12
PATTERNS = Path(__file__).resolve().parents[2] / "data" / "patterns"


def bell(x, m, s):
    return np.exp(-((x - m) / s) ** 2 / 2)


@functools.lru_cache(maxsize=None)
def _classes(nbh: int):
    r = (nbh - 1) // 2
    i = np.arange(nbh) - r
    d = i[:, None] ** 2 + i[None, :] ** 2
    inside = d <= r * r
    ds = np.unique(d[inside])
    cmap = np.full((nbh, nbh), -1, dtype=np.int64)
    cmap[inside] = np.searchsorted(ds, d[inside])
    return cmap, ds


def class_map(nbh: int) -> np.ndarray:
    """(nbh, nbh) class index of every window offset, -1 outside the disk."""
    return _classes(nbh)[0].copy()


def num_classes(nbh: int) -> int:
    return len(_classes(nbh)[1])


def class_counts(nbh: int) -> np.ndarray:
    """Number of window cells in each class."""
    cmap = _classes(nbh)[0]
    return np.bincount(cmap[cmap >= 0], minlength=num_classes(nbh)).astype(np.int64)


def kernel_weights(R: float, beta, nbh: int, ww: int) -> np.ndarray:
    """One ww-bit weight per class: the tutorial kernel, rounded relative to its maximum."""
    r = (nbh - 1) // 2
    if not 1 <= R <= r:
        raise ValueError(f"kernel radius {R} outside 1 .. {r} for a {nbh}x{nbh} window")
    b = np.asarray(beta, dtype=np.float64)
    D = np.sqrt(_classes(nbh)[1]) / R * len(b)
    K = (D < len(b)) * b[np.minimum(D.astype(np.int64), len(b) - 1)] * bell(D % 1, 0.5, 0.15)
    return np.rint(K / K.max() * ((1 << ww) - 1)).astype(np.int64)


def growth_table(mu: float, sigma: float, T: float, w, nbh: int, cw: int, lb: int) -> tuple[np.ndarray, int]:
    """Signed table entries (2^lb of them) and the shift SH; the kernel
    normalisation and dt = 1/T live in the table."""
    w = np.asarray(w, dtype=np.int64)
    wsum = int((w * class_counts(nbh)).sum())
    if wsum == 0:
        raise ValueError("the kernel has no non-zero weight")
    smax = wsum * ((1 << cw) - 1)
    sh = max(0, smax.bit_length() - lb)
    idx = np.arange(1 << lb, dtype=np.float64)
    U = (idx * 2.0 ** sh + (2.0 ** sh - 1) / 2) / (wsum * 2.0 ** cw)
    e = np.rint((1.0 / T) * (2 * bell(U, mu, sigma) - 1) * 2.0 ** cw)
    return np.clip(e, -(1 << cw), (1 << cw) - 1).astype(np.int64), sh


def kernel_grid(w, nbh: int) -> np.ndarray:
    """(nbh, nbh) integer kernel: the weight of each offset's class, 0 outside the disk."""
    cmap = _classes(nbh)[0]
    return np.where(cmap >= 0, np.asarray(w, dtype=np.int64)[np.maximum(cmap, 0)], 0)


def lenia_sum(grid, w, nbh: int, bnd: Boundary) -> np.ndarray:
    """S for every computed cell (as neigh.window_sum), by FFT correlation of the
    padded grid, rounded to integers; the rounding is asserted to be exact."""
    r = (nbh - 1) // 2
    p = _pad(grid, r, bnd).astype(np.float64)
    k = kernel_grid(w, nbh).astype(np.float64)
    c = np.fft.irfft2(np.fft.rfft2(p) * np.conj(np.fft.rfft2(k, s=p.shape)), s=p.shape)
    c = c[:p.shape[0] - 2 * r, :p.shape[1] - 2 * r]
    s = np.rint(c)
    err = float(np.abs(c - s).max()) if c.size else 0.0
    if err >= 0.25:
        raise AssertionError(f"FFT sum not exact (fractional error {err:.3f})")
    return s.astype(np.int64)


def naive_sum(grid, w, nbh: int, bnd: Boundary) -> np.ndarray:
    """Per-cell reference implementation of :func:`lenia_sum`."""
    r = (nbh - 1) // 2
    p = _pad(grid, r, bnd)
    k = kernel_grid(w, nbh)
    out = np.zeros((p.shape[0] - 2 * r, np.asarray(grid).shape[1]), dtype=np.int64)
    for y in range(out.shape[0]):
        for x in range(out.shape[1]):
            out[y, x] = int((k * p[y:y + nbh, x:x + nbh]).sum())
    return out


def update(centre, S, table, sh: int, cw: int) -> np.ndarray:
    table = np.asarray(table, dtype=np.int64)
    idx = np.minimum(np.asarray(S, dtype=np.int64) >> sh, len(table) - 1)
    return np.clip(np.asarray(centre, dtype=np.int64) + table[idx], 0, (1 << cw) - 1)


def cell_from_window(win, w, table, sh: int, cw: int) -> int:
    """Next state of the centre cell of one N x N window."""
    win = np.asarray(win, dtype=np.int64)
    n = win.shape[0]
    r = (n - 1) // 2
    S = int((kernel_grid(w, n) * win).sum())
    return int(update(win[r, r], S, table, sh, cw))


def step_lenia(grid, w, table, sh: int, nbh: int, cw: int, bnd: Boundary) -> np.ndarray:
    """One generation; frozen rows of the legacy modes are copied."""
    r = (nbh - 1) // 2
    g = np.asarray(grid, dtype=np.int64)
    full = bnd in (Boundary.TOROIDAL, Boundary.ZERO)
    centre = g if full else g[r:g.shape[0] - r]
    region = update(centre, lenia_sum(g, w, nbh, bnd), table, sh, cw)
    out = np.array(grid, dtype=cell_dtype(cw), copy=True)
    if full:
        out[:] = region
    else:
        out[r:out.shape[0] - r] = region
    return out


@functools.lru_cache(maxsize=64)
def _cfg_kernel(R, beta, T, mu, sigma, nbh, cw, ww, lb):
    w = kernel_weights(R, list(beta), nbh, ww)
    table, sh = growth_table(mu, sigma, T, w, nbh, cw, lb)
    return w, table, sh


def cfg_kernel(cfg: dict) -> tuple[np.ndarray, np.ndarray, int]:
    """(weights, table, SH) of a Lenia configuration."""
    p = cfg["params"]
    w, table, sh = _cfg_kernel(float(p["R"]), tuple(float(b) for b in p["beta"]), float(p["T"]), float(p["mu"]),
                               float(p["sigma"]), cfg["nbh"], cfg["cell_w"],
                               cfg.get("weight_w", DEFAULT_WEIGHT_W), cfg.get("lut_idx_w", DEFAULT_LUT_IDX_W))
    return w.copy(), table.copy(), sh


def apply_defaults(cfg: dict) -> None:
    cfg.setdefault("cell_w", 16)
    cfg.setdefault("mask", "moore")
    cfg.setdefault("weight_w", DEFAULT_WEIGHT_W)
    cfg.setdefault("lut_idx_w", DEFAULT_LUT_IDX_W)


def validate(cfg: dict, where: str = "") -> None:
    """Raise ValueError unless cfg is a valid Lenia configuration."""
    p = cfg["params"]
    if set(p) != set(LENIA_PARAMS):
        raise ValueError(f"{where}: Lenia parameters must be exactly {list(LENIA_PARAMS)}, got {sorted(p)}")
    r = (cfg["nbh"] - 1) // 2
    if not 1 <= p["R"] <= r:
        raise ValueError(f"{where}: R = {p['R']} outside 1 .. {r}")
    if not p["beta"] or p["T"] <= 0 or p["sigma"] <= 0:
        raise ValueError(f"{where}: beta must be non-empty and T, sigma positive")
    if cfg["cell_w"] not in (8, 16):
        raise ValueError(f"{where}: Lenia needs 8- or 16-bit cells, got {cfg['cell_w']}")
    if not 1 <= cfg["weight_w"] <= 15:
        raise ValueError(f"{where}: weight_w must be 1 .. 15")
    if not 1 <= cfg["lut_idx_w"] <= 13:
        raise ValueError(f"{where}: lut_idx_w must be 1 .. 13")



def load_pattern(name: str) -> dict:
    """A creature from data/patterns/<name>.json (Lenia tutorial, MIT); cells as a float array."""
    pat = json.loads((PATTERNS / f"{name}.json").read_text())
    pat["cells"] = np.asarray(pat["cells"], dtype=np.float64)
    return pat
