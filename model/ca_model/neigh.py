"""Boundary-aware weighted window sums (spec Section 5).

TOROIDAL and ZERO compute every row; the legacy CYLINDRICAL and RECTANGULAR
modes compute rows ``r .. Y-1-r`` only. Horizontal edges wrap for TOROIDAL
and CYLINDRICAL and read zeros for RECTANGULAR and ZERO.
"""
from enum import Enum

import numpy as np


class Boundary(Enum):
    TOROIDAL = "toroidal"
    CYLINDRICAL = "cylindrical"
    RECTANGULAR = "rectangular"
    ZERO = "zero"


def _pad(values: np.ndarray, r: int, bnd: Boundary) -> np.ndarray:
    """Pad so that output cell (y, x) sees window rows y..y+2r, columns x..x+2r."""
    v = np.asarray(values, dtype=np.int64)
    hmode = "wrap" if bnd in (Boundary.TOROIDAL, Boundary.CYLINDRICAL) else "constant"
    v = np.pad(v, ((0, 0), (r, r)), mode=hmode)
    if bnd is Boundary.TOROIDAL:
        v = np.pad(v, ((r, r), (0, 0)), mode="wrap")
    elif bnd is Boundary.ZERO:
        v = np.pad(v, ((r, r), (0, 0)), mode="constant")
    return v


def _runs(row: np.ndarray):
    """Contiguous runs of True in a 1-D boolean array as (start, stop) pairs."""
    d = np.diff(np.concatenate([[0], row.astype(np.int8), [0]]))
    return list(zip(np.flatnonzero(d == 1), np.flatnonzero(d == -1)))


def window_sum(values: np.ndarray, mask: np.ndarray, bnd: Boundary) -> np.ndarray:
    """Sum of ``values`` over ``mask`` for every computed cell (int64)."""
    n = mask.shape[0]
    r = (n - 1) // 2
    p = _pad(values, r, bnd)
    out_y = p.shape[0] - 2 * r
    out_x = values.shape[1]
    prefix = np.zeros((p.shape[0], p.shape[1] + 1), dtype=np.int64)
    np.cumsum(p, axis=1, out=prefix[:, 1:])
    acc = np.zeros((out_y, out_x), dtype=np.int64)
    for i in range(n):
        rows = prefix[i:i + out_y]
        for a, b in _runs(mask[i]):
            acc += rows[:, b:b + out_x] - rows[:, a:a + out_x]
    return acc


def naive_window_sum(values: np.ndarray, mask: np.ndarray, bnd: Boundary) -> np.ndarray:
    """Per-cell reference implementation of :func:`window_sum`."""
    n = mask.shape[0]
    r = (n - 1) // 2
    p = _pad(values, r, bnd)
    out_y, out_x = p.shape[0] - 2 * r, values.shape[1]
    out = np.zeros((out_y, out_x), dtype=np.int64)
    for y in range(out_y):
        for x in range(out_x):
            s = 0
            for i in range(n):
                for j in range(n):
                    if mask[i, j]:
                        s += int(p[y + i, x + j])
            out[y, x] = s
    return out
