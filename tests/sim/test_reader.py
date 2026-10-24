"""ca_frame_reader: line-buffer rows follow the virtual-row sequence and the
consumer stream carries the front buffer, under stalls and 4 KB splits."""
import numpy as np
import pytest

import rtlsim
from rowseq import BOUNDARIES, virtual_rows

MODES = {
    #          grid_x, grid_y, cell_w, nbh, data_w, base,   plusargs
    "basic":  (64, 8, 8, 5, 64, 0x2000, {}),
    "stall":  (64, 8, 4, 5, 64, 0x2000, {"mem_stall": 60, "mem_lat": 30, "sink_stall": 60}),
    "4k":     (1000, 6, 8, 3, 64, 0x0FC8, {"mem_stall": 20}),
    "nofwd":  (64, 8, 8, 3, 64, 0x2000, {"nofwd": 1}),
}
CASES = [(b, m) for b in BOUNDARIES for m in MODES]


@pytest.mark.parametrize("bnd_id,mode", CASES, ids=[f"{BOUNDARIES[b].value}-{m}" for b, m in CASES])
def test_reader(bnd_id, mode, tmp_path):
    gx, gy, cw, nbh, dw, base, plus = MODES[mode]
    bnd = BOUNDARIES[bnd_id]
    rng = np.random.default_rng(bnd_id * 7 + len(mode))
    grid = rng.integers(0, 1 << cw, (gy, gx))
    words = [w for row in grid for w in rtlsim.row_words(row, cw, dw)]
    (tmp_path / "frame.hex").write_text(rtlsim.words_hex(words, dw))
    binary = rtlsim.build("tb_reader", {"GRID_X": gx, "GRID_Y": gy, "CELL_W": cw, "NBH": nbh,
                                        "DATA_W": dw, "BND_ID": bnd_id, "BASE": base, "MAX_BURST": 16})
    out = tmp_path / "rows.txt"
    rtlsim.run(binary, {"frame_hex": tmp_path / "frame.hex", "out_file": out, **plus})
    exp = [rtlsim.row_words(r, cw, dw) for r in virtual_rows(grid, nbh, bnd)] * 2   # two passes
    got = [[int(t, 16) for t in line.split()] for line in out.read_text().splitlines()]
    assert len(got) == len(exp)
    for k, (g, e) in enumerate(zip(got, exp)):
        assert g == e, f"virtual row {k % len(exp)} of pass {k // (len(exp) // 2)} differs"
