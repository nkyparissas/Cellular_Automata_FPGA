"""ca_frame_writer: committed rows land at the right rows, discarded passes
leave memory untouched, under stalls and 4 KB splits."""
import numpy as np
import pytest

import rtlsim
from rowseq import BOUNDARIES

FILL = 0xA5
MODES = {
    #          grid_x, grid_y, cell_w, nbh, data_w, base, plusargs
    "basic":   (64, 8, 8, 5, 64, 0x2000, {}),
    "stall":   (64, 8, 4, 5, 64, 0x2000, {"mem_stall": 60, "mem_lat": 30, "src_gap": 50}),
    "4k":      (1000, 6, 8, 3, 64, 0x0FC8, {"mem_stall": 20}),
    "discard": (64, 8, 8, 3, 64, 0x2000, {"discard": 1}),
}
CASES = [(b, m) for b in BOUNDARIES for m in MODES]


def out_rows(gy, nbh, bnd_id):
    return gy if bnd_id in (0, 3) else gy - (nbh - 1)


@pytest.mark.parametrize("bnd_id,mode", CASES, ids=[f"{BOUNDARIES[b].value}-{m}" for b, m in CASES])
def test_writer(bnd_id, mode, tmp_path):
    gx, gy, cw, nbh, dw, base, plus = MODES[mode]
    o, first = out_rows(gy, nbh, bnd_id), (0 if bnd_id in (0, 3) else (nbh - 1) // 2)
    rng = np.random.default_rng(bnd_id * 11 + len(mode))
    rows = rng.integers(0, 1 << cw, (o, gx))
    words = [w for row in rows for w in rtlsim.row_words(row, cw, dw)]
    (tmp_path / "rows.hex").write_text(rtlsim.words_hex(words, dw))
    binary = rtlsim.build("tb_writer", {"GRID_X": gx, "GRID_Y": gy, "CELL_W": cw, "NBH": nbh, "DATA_W": dw,
                                        "BND_ID": bnd_id, "BASE": base, "MAX_BURST": 16})
    out = tmp_path / "mem.hex"
    rtlsim.run(binary, {"rows_hex": tmp_path / "rows.hex", "out_file": out, **plus})
    row_bytes = gx * cw // 8
    got = bytearray()
    for line in out.read_text().split():
        got += int(line, 16).to_bytes(dw // 8, "little")
    # Dump covers [base - 64, base + gy*row_bytes + 64).
    exp = bytearray([FILL]) * len(got)
    if "discard" not in plus:
        packed = b"".join(int(w).to_bytes(dw // 8, "little") for w in words)
        start = 64 + first * row_bytes
        exp[start:start + len(packed)] = packed
    assert got == exp, f"first difference at byte {next(i for i in range(len(got)) if got[i] != exp[i]) - 64} from base"
