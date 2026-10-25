"""Rule semantics (spec Section 11) and the generation step of the golden model."""
import numpy as np
import pytest

from ca_model.masks import moore, by_name
from ca_model.neigh import Boundary, _pad
from ca_model.rules import cell_from_window, interval_cells, params_vector
from ca_model.step import step


def pv(rule, **kw):
    return params_vector(rule, kw)


def test_params_vector_layout():
    assert pv("hodgepodge", G=105, K=5) == [105, 5, 0, 0, 0, 0, 0, 0]
    assert pv("interval", LO1=20, HI1=23, LO2=59, HI2=100, ALIVE=1)[:5] == [20, 23, 59, 100, 1]
    with pytest.raises(KeyError):
        pv("ghm", Q=1)


def test_hodgepodge_cases():
    hp = pv("hodgepodge", G=10, K=2)
    w = np.array([[0, 5, 0], [0, 100, 7], [255, 0, 0]])
    assert cell_from_window("hodgepodge", w, moore(3), hp, 8) == 101   # 367//4 + 10
    w[1, 1] = 0
    assert cell_from_window("hodgepodge", w, moore(3), hp, 8) == 1     # A=3, 3//2
    w[1, 1] = 255
    assert cell_from_window("hodgepodge", w, moore(3), hp, 8) == 0
    w = np.full((3, 3), 250)
    w[1, 1] = 200
    assert cell_from_window("hodgepodge", w, moore(3), pv("hodgepodge", G=20, K=2), 8) == 255  # saturates
    assert cell_from_window("hodgepodge", np.zeros((3, 3), int), moore(3),
                            pv("hodgepodge", G=0, K=0), 8) == 255     # healthy cell, K=0 -> MAX


def test_ghm_cases():
    gp = pv("ghm", T=2, STATES=15, E=1)
    w = np.zeros((3, 3), int)
    w[0, 0] = w[2, 2] = 1
    assert cell_from_window("ghm", w, moore(3), gp, 4) == 1
    w[2, 2] = 2
    assert cell_from_window("ghm", w, moore(3), gp, 4) == 0
    w[1, 1] = 14
    assert cell_from_window("ghm", w, moore(3), gp, 4) == 0
    w[1, 1] = 3
    assert cell_from_window("ghm", w, moore(3), gp, 4) == 4


def test_ghm_excited_range_and_mask():
    w = np.zeros((3, 3), int)
    w[0, 0] = 2
    w[0, 1] = 1
    assert cell_from_window("ghm", w, moore(3), pv("ghm", T=2, STATES=15, E=2), 4) == 1
    m = moore(3)
    m[0, 0] = False
    assert cell_from_window("ghm", w, m, pv("ghm", T=2, STATES=15, E=2), 4) == 0


@pytest.mark.parametrize("S,out", [(19, 0), (20, 1), (23, 1), (24, 0), (58, 0), (59, 1), (100, 1), (101, 0)])
def test_interval_edges(S, out):
    assert interval_cells(np.array([S]), 20, 23, 59, 100, 1)[0] == out


CASES = {
    "hodgepodge": dict(cell_w=8, params={"G": 7, "K": 2}),
    "ghm": dict(cell_w=4, params={"T": 2, "STATES": 15, "E": 1}),
    "interval": dict(cell_w=4, params={"LO1": 2, "HI1": 3, "LO2": 5, "HI2": 6, "ALIVE": 1}),
}


def small_random_case(rule, bnd, grid_xy=(12, 10), nbh=3, seed=7):
    rng = np.random.default_rng(seed)
    x, y = grid_xy
    c = CASES[rule]
    if rule == "hodgepodge":
        g = rng.choice([0, 0, 0, 1, 50, 128, 200, 254, 255], size=(y, x))
    elif rule == "ghm":
        g = rng.choice([0, 0, 0, 1, 1, 2, 7, 14], size=(y, x))
    else:
        g = rng.integers(0, 2, size=(y, x))
    cfg = {"rule": rule, "nbh": nbh, "mask": "moore", "boundary": bnd.value,
           "cell_w": c["cell_w"], "params": c["params"]}
    return cfg, g.astype(np.uint8)


def reference_step(g, cfg):
    n = cfg["nbh"]
    r = (n - 1) // 2
    bnd = Boundary(cfg["boundary"])
    p = _pad(g, r, bnd)
    m = by_name(cfg["mask"], n)
    params = params_vector(cfg["rule"], cfg["params"])
    out = g.astype(np.int64).copy()
    off = 0 if bnd in (Boundary.TOROIDAL, Boundary.ZERO) else r
    for y in range(p.shape[0] - 2 * r):
        for x in range(g.shape[1]):
            out[y + off, x] = cell_from_window(cfg["rule"], p[y:y + n, x:x + n], m, params, cfg["cell_w"])
    return out


@pytest.mark.parametrize("rule", ["hodgepodge", "ghm", "interval"])
@pytest.mark.parametrize("bnd", list(Boundary))
def test_step_equals_window_reference(rule, bnd):
    cfg, g = small_random_case(rule, bnd)
    assert np.array_equal(step(g, cfg), reference_step(g, cfg))


def test_step_keeps_frozen_rows():
    cfg, g = small_random_case("ghm", Boundary.CYLINDRICAL)
    nxt = step(g, cfg)
    assert np.array_equal(nxt[0], g[0]) and np.array_equal(nxt[-1], g[-1])
    assert nxt.dtype == np.uint8


def test_step_keeps_wide_cells():
    """16-bit cells (e.g. fixed-point Lenia states) keep their full range."""
    g = np.random.default_rng(4).choice([0, 1, 300, 40000, 65535], size=(10, 12)).astype(np.uint16)
    hp = {"rule": "hodgepodge", "nbh": 3, "mask": "moore", "boundary": "toroidal", "cell_w": 16,
          "params": {"G": 1000, "K": 2}}
    nxt = step(g, hp)
    assert nxt.dtype == np.uint16 and np.array_equal(nxt, reference_step(g, hp))
    assert nxt.max() > 255
    iv = {"rule": "interval", "nbh": 3, "mask": "moore", "boundary": "toroidal", "cell_w": 16,
          "params": {"LO1": 0, "HI1": 10**6, "LO2": 0, "HI2": 0, "ALIVE": 1000}}
    assert (step(g, iv) == 1000).all()
