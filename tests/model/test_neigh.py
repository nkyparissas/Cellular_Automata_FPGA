"""Masks and boundary-aware window sums of the golden model."""
import numpy as np
import pytest

from ca_model import masks
from ca_model.neigh import Boundary, window_sum, naive_window_sum

rng = np.random.default_rng(3)


def mask_for(name, n):
    if name == "random":
        m = rng.random((n, n)) < 0.5
        m[n // 2, n // 2] = True
        return m
    return masks.by_name(name, n)


@pytest.mark.parametrize("bnd", list(Boundary))
@pytest.mark.parametrize("n,maskname", [(3, "moore"), (5, "von_neumann"), (7, "random"), (5, "moore")])
def test_window_sum_matches_naive(bnd, n, maskname):
    g = rng.integers(0, 256, (17, 23))
    m = mask_for(maskname, n)
    assert np.array_equal(window_sum(g, m, bnd), naive_window_sum(g, m, bnd))


@pytest.mark.parametrize("bnd,shape", [(Boundary.TOROIDAL, (17, 23)), (Boundary.ZERO, (17, 23)),
                                       (Boundary.CYLINDRICAL, (13, 23)), (Boundary.RECTANGULAR, (13, 23))])
def test_window_sum_region_shape(bnd, shape):
    assert window_sum(np.ones((17, 23), int), masks.moore(5), bnd).shape == shape


def test_toroidal_wraps_both_axes():
    g = np.zeros((9, 11), int)
    g[0, 0] = 1
    s = window_sum(g, masks.moore(3), Boundary.TOROIDAL)
    assert s[8, 10] == 1 and s[1, 1] == 1 and s[0, 0] == 1 and s[2, 2] == 0


def test_rectangular_zero_columns_cylindrical_wraps():
    g = np.zeros((9, 11), int)
    g[4, 0] = 1
    assert window_sum(g, masks.moore(3), Boundary.CYLINDRICAL)[3, 10] == 1   # row 4 is output row 3
    assert window_sum(g, masks.moore(3), Boundary.RECTANGULAR)[3, 10] == 0


def test_legacy_masks_shape():
    assert masks.circle29().shape == (29, 29) and masks.circle29().sum() == 697
    assert masks.ap21().shape == (21, 21) and masks.ap21().sum() == 145
    assert masks.von_neumann(29).sum() == 421
    assert masks.circle29()[14, 14] and masks.ap21()[10, 10]
    assert masks.ap21()[20, 9] and not masks.ap21()[9, 20]   # asymmetric mask kept as written


def test_sv_literal_bit_order():
    m = np.zeros((3, 3), bool)
    m[0, 1] = True          # bit 0*3+1 = 1
    m[2, 2] = True          # bit 8
    assert masks.to_sv_literal(m) == "9'b100000010"
