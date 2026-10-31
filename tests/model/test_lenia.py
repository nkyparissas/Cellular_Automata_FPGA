"""Lenia golden model (design spec 2026-10-31, Sections 5 and 9.1)."""
import json
import time

import numpy as np
import pytest

from ca_model import config, lenia, step
from ca_model.neigh import Boundary, _pad

BOUNDARIES = list(Boundary)


def test_class_counts():
    for n, c in {5: 4, 7: 7, 9: 10, 27: 69, 29: 78, 37: 121}.items():
        assert lenia.num_classes(n) == c, n
    for n, cells in {27: 529, 29: 613, 37: 1009}.items():
        counts = lenia.class_counts(n)
        assert counts.max() == 16 and counts.sum() == cells, n
        r = (n - 1) // 2
        assert lenia.class_map(n)[r, r] == 0
    assert lenia.class_map(5)[0, 0] == -1


def test_kernel_weights_creatures():
    w = lenia.kernel_weights(13, [1], 27, 6)
    counts = lenia.class_counts(27)
    assert len(w) == 69 and w.max() == 63 and w[0] == 0
    assert np.count_nonzero(w) == 64 and counts[w > 0].sum() == 496
    w = lenia.kernel_weights(18, [0.5, 1, 0.667], 37, 6)
    counts = lenia.class_counts(37)
    assert np.count_nonzero(w) == 106 and counts[w > 0].sum() == 904
    for bad in (0, 14):
        with pytest.raises(ValueError):
            lenia.kernel_weights(bad, [1], 27, 6)


def test_growth_table_shift_and_range():
    w = lenia.kernel_weights(13, [1], 27, 6)
    wsum = int((w * lenia.class_counts(27)).sum())
    table, sh = lenia.growth_table(0.15, 0.015, 10, w, 27, 16, 12)
    assert sh == max(0, (wsum * 65535).bit_length() - 12)
    assert len(table) == 4096 and table.min() >= -65536 and table.max() <= 65535
    idx_mu = int(0.15 * wsum * 65536) >> sh
    assert abs(int(table[idx_mu]) - 6554) <= 1 and table.max() <= 6554
    assert table[0] == -6554
    table, _ = lenia.growth_table(0.15, 0.015, 1, w, 27, 16, 12)
    assert table.min() == -65536 and table.max() <= 65535
    flat, _ = lenia.growth_table(0.5, 1e9, 1, w, 27, 16, 12)   # bell = 1 everywhere: +2^cw clamps
    assert flat.max() == 65535


def _random_weights(rng, n, ww):
    w = rng.integers(0, 1 << ww, size=lenia.num_classes(n))
    w[0] = 0
    w[rng.integers(1, len(w))] = (1 << ww) - 1
    return w


@pytest.mark.parametrize("bnd", BOUNDARIES, ids=lambda b: b.value)
@pytest.mark.parametrize("n", [5, 7, 9])
@pytest.mark.parametrize("cw", [8, 16])
@pytest.mark.parametrize("ww", [4, 8])
def test_sum_fft_matches_naive(bnd, n, cw, ww):
    rng = np.random.default_rng(n * 100 + cw * 10 + ww)
    grid = rng.integers(0, 1 << cw, size=(23, 31))
    w = _random_weights(rng, n, ww)
    assert np.array_equal(lenia.lenia_sum(grid, w, n, bnd), lenia.naive_sum(grid, w, n, bnd))


@pytest.mark.parametrize("bnd", [Boundary.TOROIDAL, Boundary.CYLINDRICAL, Boundary.ZERO], ids=lambda b: b.value)
@pytest.mark.parametrize("sh,lb,cw,n", [(0, 8, 16, 5), (3, 10, 8, 7), (40, 12, 16, 5)])
def test_step_matches_windows(bnd, sh, lb, cw, n):
    rng = np.random.default_rng(sh + lb + cw + n)
    grid = rng.integers(0, 1 << cw, size=(13, 17))
    grid[0, :4] = [0, 0, (1 << cw) - 1, (1 << cw) - 1]
    w = _random_weights(rng, n, 6)
    table = rng.integers(-(1 << cw), 1 << cw, size=1 << lb)
    out = lenia.step_lenia(grid, w, table, sh, n, cw, bnd)
    r = (n - 1) // 2
    p = _pad(grid, r, bnd)
    rows = range(13) if bnd in (Boundary.TOROIDAL, Boundary.ZERO) else range(r, 13 - r)
    for k, y in enumerate(rows):
        for x in range(17):
            assert out[y, x] == lenia.cell_from_window(p[k:k + n, x:x + n], w, table, sh, cw), (y, x)
    if bnd is Boundary.CYLINDRICAL:
        assert np.array_equal(out[:r], grid[:r]) and np.array_equal(out[13 - r:], grid[13 - r:])
    assert out.min() >= 0 and out.max() <= (1 << cw) - 1


def test_update_saturates():
    table = np.array([5, -5, 0, 7])
    assert lenia.update(np.array([65535]), np.array([0]), table, 0, 16)[0] == 65535
    assert lenia.update(np.array([0]), np.array([1]), table, 0, 16)[0] == 0
    assert lenia.update(np.array([10]), np.array([10 ** 9]), table, 0, 16)[0] == 17   # index clamps to 3


def _lenia_cfg(tmp_path, **over):
    cfg = {"name": "l", "grid": [64, 32], "nbh": 27, "boundary": "toroidal", "rule": "lenia",
           "params": {"R": 13, "T": 10, "mu": 0.15, "sigma": 0.015, "beta": [1]},
           "seed": "x.png", "seed_mode": "unit16", "palette": "viridis"}
    cfg.update(over)
    p = tmp_path / "l.json"
    p.write_text(json.dumps(cfg))
    return p


def test_config_lenia_validation(tmp_path):
    cfg = config.load(_lenia_cfg(tmp_path))
    assert (cfg["cell_w"], cfg["weight_w"], cfg["lut_idx_w"], cfg["mask"]) == (16, 6, 12, "moore")
    good = {"R": 13, "T": 10, "mu": 0.15, "sigma": 0.015, "beta": [1]}
    bad = [{"params": dict(good, R=14)}, {"params": dict(good, R=0)}, {"cell_w": 4},
           {"params": {k: v for k, v in good.items() if k != "beta"}}, {"params": dict(good, G=3)},
           {"weight_w": 16}, {"lut_idx_w": 14}]
    for over in bad:
        with pytest.raises(ValueError):
            config.load(_lenia_cfg(tmp_path, **over))


def test_step_dispatch_lenia():
    cfg = {"grid": [24, 20], "cell_w": 16, "nbh": 9, "boundary": "toroidal", "rule": "lenia", "mask": "moore",
           "params": {"R": 4, "T": 10, "mu": 0.15, "sigma": 0.03, "beta": [1]}, "weight_w": 6, "lut_idx_w": 12}
    grid = np.random.default_rng(3).integers(0, 1 << 16, size=(20, 24)).astype(np.uint16)
    w, table, sh = lenia.cfg_kernel(cfg)
    want = lenia.step_lenia(grid, w, table, sh, 9, 16, Boundary.TOROIDAL)
    got = step.step(grid, cfg)
    assert got.dtype == np.uint16 and np.array_equal(got, want)


def test_1080p_step_is_fast():
    w = lenia.kernel_weights(13, [1], 27, 6)
    table, sh = lenia.growth_table(0.15, 0.015, 10, w, 27, 16, 12)
    grid = np.random.default_rng(0).integers(0, 1 << 16, size=(1080, 1920)).astype(np.uint16)
    t0 = time.perf_counter()
    lenia.step_lenia(grid, w, table, sh, 27, 16, Boundary.TOROIDAL)
    assert time.perf_counter() - t0 < 20.0


def test_degenerate_beta_rejected(tmp_path):
    for beta in ([0], [1, -0.5], [float("nan")], []):
        with pytest.raises(ValueError):
            lenia.kernel_weights(13, beta, 27, 6)
    good = {"R": 13, "T": 10, "mu": 0.15, "sigma": 0.015}
    for beta in ([0], [1, -0.5], [float("inf")]):
        with pytest.raises(ValueError):
            config.load(_lenia_cfg(tmp_path, params=dict(good, beta=beta)))
