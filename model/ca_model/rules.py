"""Bit-exact rule semantics (spec Section 11).

Every rule is written once as an elementwise function of the window
statistics, so the same code serves whole grids and single windows.
"""
import numpy as np

from .neigh import Boundary, window_sum

NUM_RULE_PARAMS = 8

PARAM_INDEX = {
    "hodgepodge": {"G": 0, "K": 1},
    "ghm": {"T": 0, "STATES": 1, "E": 2},
    "interval": {"LO1": 0, "HI1": 1, "LO2": 2, "HI2": 3, "ALIVE": 4},
}


def params_vector(rule: str, params: dict) -> list[int]:
    """Map named parameters to the 8 RULE_PARAM registers."""
    vec = [0] * NUM_RULE_PARAMS
    index = PARAM_INDEX[rule]
    for name, value in params.items():
        vec[index[name]] = int(value)
    return vec


def _floordiv_sat(num, den, maxv):
    """Unsigned floor division, a zero divisor yields maxv (as the RTL divider)."""
    num = np.asarray(num, dtype=np.int64)
    den = np.asarray(den, dtype=np.int64)
    safe = np.where(den == 0, 1, den)
    return np.where(den == 0, maxv, num // safe)


def hodgepodge_cells(c, S, A, cell_w, G, K):
    maxv = (1 << cell_w) - 1
    c = np.asarray(c, dtype=np.int64)
    healthy = np.minimum(maxv, _floordiv_sat(A, np.full_like(c, K), maxv))
    infected = np.minimum(maxv, _floordiv_sat(S, np.asarray(A) + 1, maxv) + G)
    return np.where(c == 0, healthy, np.where(c == maxv, 0, infected))


def ghm_cells(c, X, T, STATES):
    c = np.asarray(c, dtype=np.int64)
    return np.where(c > 0, np.where(c + 1 >= STATES, 0, c + 1), np.where(np.asarray(X) >= T, 1, 0))


def interval_cells(S, LO1, HI1, LO2, HI2, ALIVE):
    S = np.asarray(S, dtype=np.int64)
    hit = ((S >= LO1) & (S <= HI1)) | ((S >= LO2) & (S <= HI2))
    return np.where(hit, ALIVE, 0)


def _without_centre(mask):
    m = np.array(mask, dtype=bool)
    r = (m.shape[0] - 1) // 2
    m[r, r] = False
    return m


def apply(rule: str, values: np.ndarray, centre: np.ndarray, mask, params: list[int],
          cell_w: int, stats) -> np.ndarray:
    """Evaluate ``rule`` given a statistics function ``stats(values, mask)``."""
    if rule == "hodgepodge":
        S = stats(values, mask)
        A = stats((values > 0).astype(np.int64), _without_centre(mask))
        return hodgepodge_cells(centre, S, A, cell_w, params[0], params[1])
    if rule == "ghm":
        T, STATES, E = params[0], params[1], params[2]
        X = stats(((values >= 1) & (values <= E)).astype(np.int64), _without_centre(mask))
        return ghm_cells(centre, X, T, STATES)
    if rule == "interval":
        S = stats(values, mask)
        return interval_cells(S, *params[:5])
    raise ValueError(f"unknown rule {rule!r}")


def cell_from_window(rule: str, win: np.ndarray, mask, params: list[int], cell_w: int) -> int:
    """Next state of the centre cell of one N x N window."""
    w = np.asarray(win, dtype=np.int64)
    r = (w.shape[0] - 1) // 2
    out = apply(rule, w, w[r, r], mask, params, cell_w,
                lambda v, m: np.sum(v * np.asarray(m, dtype=np.int64)))
    return int(out)


def apply_grid(rule: str, grid: np.ndarray, mask, params: list[int], cell_w: int,
               bnd: Boundary) -> np.ndarray:
    """Next states of the computed region of ``grid`` (see neigh.window_sum)."""
    g = np.asarray(grid, dtype=np.int64)
    r = (mask.shape[0] - 1) // 2
    centre = g if bnd in (Boundary.TOROIDAL, Boundary.ZERO) else g[r:g.shape[0] - r]
    return apply(rule, g, centre, mask, params, cell_w,
                 lambda v, m: window_sum(v, m, bnd))
