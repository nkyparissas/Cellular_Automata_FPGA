"""One generation of the CA for a configuration dictionary (spec Section 17)."""
import numpy as np

from . import masks
from .grids import cell_dtype
from .neigh import Boundary
from .rules import apply_grid, params_vector


def step(grid: np.ndarray, cfg: dict) -> np.ndarray:
    """Return the next generation; frozen rows of legacy modes are copied."""
    n = cfg["nbh"]
    r = (n - 1) // 2
    bnd = Boundary(cfg["boundary"])
    mask = masks.by_name(cfg["mask"], n)
    params = params_vector(cfg["rule"], cfg["params"])
    region = apply_grid(cfg["rule"], grid, mask, params, cfg["cell_w"], bnd)
    out = np.array(grid, dtype=cell_dtype(cfg["cell_w"]), copy=True)
    if bnd in (Boundary.TOROIDAL, Boundary.ZERO):
        out[:] = region
    else:
        out[r:out.shape[0] - r] = region
    return out


def run(grid: np.ndarray, cfg: dict, gens: int, callback=None) -> np.ndarray:
    """Advance ``gens`` generations; ``callback(gen, grid)`` after each one."""
    g = np.array(grid, dtype=cell_dtype(cfg["cell_w"]), copy=True)
    for k in range(1, gens + 1):
        g = step(g, cfg)
        if callback is not None:
            callback(k, g)
    return g
