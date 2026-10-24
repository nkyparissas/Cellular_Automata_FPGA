"""Neighbourhood masks. ``mask[i, j]`` is window row ``i``, column ``j``."""
import numpy as np

# Legacy GHM engine, commented-out circular neighbourhood (cells listed there
# are outside the mask).
_CIRCLE29 = [
    "00000000011111111111000000000",
    "00000001111111111111110000000",
    "00000011111111111111111000000",
    "00001111111111111111111110000",
    "00011111111111111111111111000",
    "00011111111111111111111111000",
    "00111111111111111111111111100",
    "01111111111111111111111111110",
    "01111111111111111111111111110",
] + ["11111111111111111111111111111"] * 11 + [
    "01111111111111111111111111110",
    "01111111111111111111111111110",
    "00111111111111111111111111100",
    "00011111111111111111111111000",
    "00011111111111111111111111000",
    "00001111111111111111111110000",
    "00000011111111111111111000000",
    "00000001111111111111110000000",
    "00000000011111111111000000000",
]

# Legacy Artificial Physics engine weights, NEIGHBORHOOD_WEIGHT(i, j) as written.
_AP21 = [
    "000000000010000000000",
    "000000111000111000000",
    "000011000000000110000",
    "000100001111100001000",
    "001000110000011000100",
    "001001000111000100100",
    "010010011000110010010",
    "010010100111001010010",
    "010100101000101001010",
    "100101010111010101000",
    "100101010111010101001",
    "100101010111010101000",
    "010100101000101001010",
    "010010100111001010010",
    "010010011000110010010",
    "001001000111000100100",
    "001000110000011000100",
    "000100001111100001000",
    "000011000000000110000",
    "000000111000111000000",
    "000000000111000000000",
]


def _from_rows(rows):
    return np.array([[c == "1" for c in r] for r in rows], dtype=bool)


def moore(n: int) -> np.ndarray:
    return np.ones((n, n), dtype=bool)


def von_neumann(n: int) -> np.ndarray:
    r = (n - 1) // 2
    i, j = np.indices((n, n))
    return (np.abs(i - r) + np.abs(j - r)) <= r


def circle29() -> np.ndarray:
    return _from_rows(_CIRCLE29)


def ap21() -> np.ndarray:
    return _from_rows(_AP21)


def by_name(name: str, n: int) -> np.ndarray:
    if name == "moore":
        return moore(n)
    if name == "von_neumann":
        return von_neumann(n)
    fixed = {"circle29": circle29, "ap21": ap21}
    if name in fixed:
        m = fixed[name]()
        if m.shape != (n, n):
            raise ValueError(f"mask {name} is {m.shape[0]}x{m.shape[1]}, neighbourhood is {n}")
        return m
    raise ValueError(f"unknown mask {name!r}")


def to_sv_literal(mask: np.ndarray) -> str:
    """SystemVerilog literal with bit ``i*n+j`` set when ``mask[i, j]``."""
    flat = np.asarray(mask, dtype=bool).reshape(-1)
    return f"{flat.size}'b" + "".join("1" if b else "0" for b in flat[::-1])
