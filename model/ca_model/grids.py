"""Grid input/output for the golden model.

Seeds are indexed BMP images. Frames in memory follow the layout of the
hardware (spec Section 4): rows are contiguous, cell ``x`` occupies bits
``[x*cell_w +: cell_w]`` of the row read as a little-endian bit vector.
"""
from pathlib import Path

import numpy as np
from PIL import Image

# MATLAB rgb2gray coefficients (first row of the inverse NTSC/YIQ matrix).
_RGB2GRAY = np.array([0.298936021293775, 0.587043074451121, 0.114020904255103])

# Legacy FHD_COLOR_CTRL.vhd palettes, 4-bit DAC values (0..15) per channel.
_WINDOWS16 = [
    (0, 0, 0), (11, 0, 0), (0, 11, 0), (11, 6, 0),
    (0, 0, 11), (11, 0, 11), (0, 11, 11), (11, 11, 11),
    (6, 6, 6), (15, 2, 2), (6, 15, 6), (15, 15, 2),
    (2, 2, 15), (15, 6, 15), (6, 15, 15), (15, 15, 15),
]


def load_seed(path, mode: str, value: int | None = None) -> np.ndarray:
    """Load an indexed BMP seed as a uint8 grid.

    ``mode="index"`` returns the raw palette indices (legacy 4-bit scripts).
    ``mode="binary"`` maps every non-zero index to ``value`` (the legacy text
    grids of the Hodgepodge and Artificial Physics experiments use 251 and 1).
    ``mode="raw"`` returns the pixel values of a greyscale or indexed image
    unchanged (used for seeds stored losslessly from legacy text grids).
    ``mode="gray8"`` reproduces the legacy 8-bit ``bmp2ascii.m``: the grey
    levels of the palette are sorted ascending and pixel index ``i`` maps to
    ``round(sorted_grey[i] * 255)``.
    """
    img = Image.open(Path(path))
    if mode == "raw":
        if img.mode not in ("L", "P"):
            raise ValueError(f"{path}: raw seeds must be greyscale or indexed, got mode {img.mode}")
        return np.array(img, dtype=np.uint8)
    if img.mode != "P":
        raise ValueError(f"{path}: expected an indexed (palette) BMP, got mode {img.mode}")
    idx = np.array(img, dtype=np.uint8)
    if mode == "index":
        return idx
    if mode == "binary":
        if value is None:
            raise ValueError("binary seed mode needs a value for non-zero pixels")
        return np.where(idx > 0, value, 0).astype(np.uint8)
    if mode != "gray8":
        raise ValueError(f"unknown seed mode {mode!r}")
    pal = np.array(img.getpalette(), dtype=np.float64).reshape(-1, 3) / 255.0
    grey = np.clip(pal @ _RGB2GRAY, 0.0, 1.0)
    lut = np.floor(np.sort(grey) * 255.0 + 0.5)  # MATLAB round(): half away from zero
    return lut[idx].astype(np.uint8)


# Cell widths for which DATA_W / CELL_W can be a power of two (rtl/top/ca_core.sv).
CELL_WIDTHS = (1, 2, 4, 8, 16, 32)


def cell_dtype(cell_w: int):
    """Smallest unsigned numpy type that holds one ``cell_w``-bit cell."""
    if cell_w not in CELL_WIDTHS:
        raise ValueError(f"unsupported cell width {cell_w} (supported: {CELL_WIDTHS})")
    return np.uint8 if cell_w <= 8 else np.uint16 if cell_w == 16 else np.uint32


def pack_frame(grid: np.ndarray, cell_w: int) -> bytes:
    """Pack a (Y, X) grid into the memory layout used by the hardware."""
    dt = cell_dtype(cell_w)
    if cell_w >= 8:
        return np.ascontiguousarray(grid, dtype=np.dtype(dt).newbyteorder("<")).tobytes()
    per = 8 // cell_w
    g = np.asarray(grid).astype(np.uint8)
    if g.shape[1] % per:
        raise ValueError(f"{cell_w}-bit frames need a multiple of {per} columns")
    shifts = (np.arange(per) * cell_w).astype(np.uint8)
    cells = (g & ((1 << cell_w) - 1)).reshape(g.shape[0], -1, per) << shifts
    return np.bitwise_or.reduce(cells, axis=2).astype(np.uint8).tobytes()


def unpack_frame(data: bytes, grid_x: int, grid_y: int, cell_w: int) -> np.ndarray:
    """Inverse of :func:`pack_frame`."""
    dt = cell_dtype(cell_w)
    if cell_w >= 8:
        raw = np.frombuffer(data, dtype=np.dtype(dt).newbyteorder("<"), count=grid_x * grid_y)
        return raw.reshape(grid_y, grid_x).astype(dt)
    per = 8 // cell_w
    raw = np.frombuffer(data, dtype=np.uint8, count=grid_x * grid_y // per).reshape(grid_y, grid_x // per, 1)
    shifts = (np.arange(per) * cell_w).astype(np.uint8)
    return ((raw >> shifts) & ((1 << cell_w) - 1)).reshape(grid_y, grid_x).astype(np.uint8)


def palette_lut(cell_w: int, palette: str) -> np.ndarray:
    """Return a (2**cell_w, 3) uint8 colour table."""
    n = 1 << cell_w
    if palette == "gray":
        v = np.round(np.arange(n) * 255.0 / (n - 1)).astype(np.uint8)
        return np.stack([v, v, v], axis=1)
    if palette == "legacy4_windows" and cell_w == 4:
        return (np.array(_WINDOWS16) * 17).astype(np.uint8)
    if palette == "legacy4_gradient" and cell_w == 4:
        v = (np.arange(16) * 17).astype(np.uint8)
        return np.stack([v, v, v], axis=1)
    if palette == "legacy8" and cell_w == 8:
        c = np.arange(256)
        hi, lo = c >> 4, c & 0x0F
        r = np.where(hi == 0, lo, 15)
        gb = np.where(hi == 0, 0, hi)
        return (np.stack([r, gb, gb], axis=1) * 17).astype(np.uint8)
    raise ValueError(f"palette {palette!r} not defined for {cell_w}-bit cells")


def to_rgb(grid: np.ndarray, cell_w: int, palette: str) -> np.ndarray:
    """Map a grid to RGB with one of the palettes of the display consumer."""
    return palette_lut(cell_w, palette)[np.asarray(grid, dtype=np.intp)]


def save_png(grid: np.ndarray, cell_w: int, palette: str, path) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(to_rgb(grid, cell_w, palette), "RGB").save(path)
