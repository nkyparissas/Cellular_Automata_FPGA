"""Row sequence of one pass (spec Section 5), shared by the SV test drivers."""
import numpy as np

from ca_model.neigh import Boundary

BOUNDARIES = {0: Boundary.TOROIDAL, 1: Boundary.CYLINDRICAL, 2: Boundary.RECTANGULAR, 3: Boundary.ZERO}


def virtual_rows(grid, nbh, bnd):
    r = (nbh - 1) // 2
    y = grid.shape[0]
    if bnd is Boundary.TOROIDAL:
        return [grid[(v - r) % y] for v in range(y + 2 * r)]
    if bnd is Boundary.ZERO:
        z = np.zeros_like(grid[0])
        return [z if (v < r or v >= y + r) else grid[v - r] for v in range(y + 2 * r)]
    return [grid[v] for v in range(y)]
