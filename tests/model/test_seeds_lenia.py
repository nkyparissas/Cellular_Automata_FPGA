"""16-bit seeds (seed_mode "unit16") and the Lenia seed composer (tools/compose_seed.py)."""
import numpy as np
import pytest
from PIL import Image

import compose_seed
from ca_model import lenia
from ca_model.grids import load_seed


def test_unit16_roundtrip(tmp_path):
    states = compose_seed.compose((64, 48), [("orbium", 10, 12)])
    cells = lenia.load_pattern("orbium")["cells"]
    assert states.shape == (48, 64)
    assert np.array_equal(states[10:10 + cells.shape[0], 12:12 + cells.shape[1]], cells)
    p = tmp_path / "s.png"
    compose_seed.save_unit16(states, p)
    v = np.rint(states * 65535)                       # the stored 16-bit grey values
    g16 = load_seed(p, "unit16", cell_w=16)
    assert g16.dtype == np.uint16 and np.array_equal(g16, np.clip(np.rint(v / 65535 * 65536), 0, 65535))
    g8 = load_seed(p, "unit16", cell_w=8)
    assert g8.dtype == np.uint8 and np.array_equal(g8, np.clip(np.rint(v / 65535 * 256), 0, 255))


def test_unit16_rejects_8bit_png(tmp_path):
    p = tmp_path / "g.png"
    Image.fromarray(np.zeros((8, 8), dtype=np.uint8), "L").save(p)
    with pytest.raises(ValueError):
        load_seed(p, "unit16", cell_w=16)


def test_compose_wraps_and_soup():
    cells = lenia.load_pattern("orbium")["cells"]
    s = compose_seed.compose((40, 30), [("orbium", 25, 35)])
    expect = np.zeros((30, 40))
    for i in range(cells.shape[0]):
        for j in range(cells.shape[1]):
            expect[(25 + i) % 30, (35 + j) % 40] = cells[i, j]
    assert np.array_equal(s, expect)
    s = compose_seed.compose((200, 100), [], soups=[(10, 20, 50, 80, 0.4)], rng_seed=1)
    region = s[10:60, 20:100]
    assert abs((region > 0).mean() - 0.4) < 0.05 and region.max() <= 1.0
    assert s.sum() == region.sum()


def test_compose_cli(tmp_path):
    out = tmp_path / "c.png"
    assert compose_seed.main(["--canvas", "64x48", "--pattern", "orbium@5,6", "--out", str(out)]) == 0
    g = load_seed(out, "unit16", cell_w=16)
    assert g.shape == (48, 64) and g[5:25, 6:26].max() > 0 and g[30:, 40:].max() == 0
