"""Seed conversion, frame packing and palettes of the golden model."""
import zlib
from pathlib import Path

import numpy as np
import pytest

from ca_model.grids import cell_dtype, load_seed, pack_frame, unpack_frame, to_rgb

ROOT = Path(__file__).resolve().parents[2]
SEEDS = ROOT / "data" / "seeds"

# zlib.crc32 of the uint8 grids in the legacy text files produced by the
# legacy MATLAB bmp2ascii.m scripts from the same images.
# The legacy text grids are the seed patterns with non-black pixels mapped to
# 251 (Hodgepodge) and 1 (Artificial Physics), hence the "binary" mode.
LEGACY_SEED_CRCS = [
    ("hodgepodge29_seed.bmp", "binary", 251, 0x1E763A06),  # sw/8-bit (Hodgepodge 29x29)/grid.txt
    ("ghm_spirals.bmp", "index", None, 0x585B0D88),        # sw/4-bit (Greenberg-Hastings)/grid_spirals.txt
    ("ap_random.bmp", "binary", 1, 0xA5BF25FC),            # sw/4-bit (Artificial Physics)/random.txt
]
# hodgepodge19_seed.bmp: the legacy folder holds no text grid generated from it.

rng = np.random.default_rng(1)


@pytest.mark.parametrize("seed,mode,value,crc", LEGACY_SEED_CRCS)
def test_seed_conversion_matches_legacy(seed, mode, value, crc):
    g = load_seed(SEEDS / seed, mode, value)
    assert g.dtype == np.uint8
    assert g.shape == (1080, 1920) and zlib.crc32(g.tobytes()) == crc


def test_hodgepodge19_seed_loads():
    g = load_seed(SEEDS / "hodgepodge19_seed.bmp", "binary", 251)
    assert g.shape == (1080, 1920) and set(np.unique(g)) == {0, 251}


def test_grid_custom_raw_matches_legacy():
    # data/seeds/hodgepodge19_grid_custom.png stores sw/8-bit (Hodgepodge 19x19)/grid_custom.txt
    # losslessly; the legacy README names it as the seed that self-organises.
    g = load_seed(SEEDS / "hodgepodge19_grid_custom.png", "raw")
    assert g.shape == (1080, 1920) and zlib.crc32(g.tobytes()) == 0x368EC638


def test_gray8_follows_bmp2ascii():
    # Black/white palette: sorted grey levels 0.0 and 1.0 map to 0 and 255.
    g = load_seed(SEEDS / "hodgepodge29_seed.bmp", "gray8")
    assert set(np.unique(g)) == {0, 255}


def test_binary_mode_requires_value():
    with pytest.raises(ValueError):
        load_seed(SEEDS / "ap_random.bmp", "binary")


@pytest.mark.parametrize("cell_w", [1, 2, 4, 8, 16, 32])
def test_pack_roundtrip(cell_w):
    g = rng.integers(0, 2**cell_w, (6, 64), dtype=np.int64).astype(cell_dtype(cell_w))
    back = unpack_frame(pack_frame(g, cell_w), 64, 6, cell_w)
    assert back.dtype == cell_dtype(cell_w) and np.array_equal(back, g)
    assert len(pack_frame(g, cell_w)) == 6 * 64 * cell_w // 8


def test_pack_nibble_order():
    assert pack_frame(np.array([[1, 2]], np.uint8), 4) == bytes([0x21])


def test_pack_sub_nibble_and_wide_order():
    # cell x at bits [x*cell_w +: cell_w] of the little-endian row
    assert pack_frame(np.array([[1, 2, 3, 0]], np.uint8), 2) == bytes([0x39])
    assert pack_frame(np.array([[1, 0, 1, 1, 0, 0, 0, 1]], np.uint8), 1) == bytes([0x8D])
    assert pack_frame(np.array([[0x1234, 0xABCD]], np.uint16), 16) == bytes([0x34, 0x12, 0xCD, 0xAB])


def test_pack_byte_order():
    assert pack_frame(np.array([[1, 2], [3, 4]], np.uint8), 8) == bytes([1, 2, 3, 4])


def test_palette_legacy8():
    rgb = to_rgb(np.array([[0x00, 0x0A, 0x3C]], np.uint8), 8, "legacy8")
    assert rgb[0].tolist() == [[0, 0, 0], [170, 0, 0], [255, 51, 51]]


def test_palette_legacy4_windows():
    rgb = to_rgb(np.array([[0, 1, 9, 15]], np.uint8), 4, "legacy4_windows")
    assert rgb[0].tolist() == [[0, 0, 0], [187, 0, 0], [255, 34, 34], [255, 255, 255]]


def test_palette_gray():
    assert to_rgb(np.array([[0, 15]], np.uint8), 4, "gray")[0].tolist() == [[0, 0, 0], [255, 255, 255]]
    assert to_rgb(np.array([[0, 255]], np.uint8), 8, "gray")[0].tolist() == [[0, 0, 0], [255, 255, 255]]
