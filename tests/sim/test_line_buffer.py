"""ca_line_buffer: windows streamed to the engine equal the model's padded grid."""
import numpy as np
import pytest

import rtlsim
from ca_model.neigh import Boundary

from rowseq import BOUNDARIES, virtual_rows


def expected_windows(vrows, nbh, bnd):
    r = (nbh - 1) // 2
    x = len(vrows[0])
    hzero = bnd in (Boundary.RECTANGULAR, Boundary.ZERO)
    out = []
    for o in range(len(vrows) - nbh + 1):
        for cx in range(x):
            w = np.zeros((nbh, nbh), dtype=np.int64)
            for i in range(nbh):
                for j in range(nbh):
                    c = cx - r + j
                    if 0 <= c < x:
                        w[i, j] = vrows[o + i][c]
                    elif not hzero:
                        w[i, j] = vrows[o + i][c % x]
            out.append(w)
    return out


CASES = [(b, n, c) for b in BOUNDARIES for n in (3, 5, 7) for c in (4, 8)]


@pytest.mark.parametrize("bnd_id,nbh,cell_w", CASES,
                         ids=[f"{BOUNDARIES[b].value}-n{n}-c{c}" for b, n, c in CASES])
def test_line_buffer(bnd_id, nbh, cell_w, tmp_path):
    gx, gy, dw, passes = 32, 12, 32, 2
    bnd = BOUNDARIES[bnd_id]
    rng = np.random.default_rng(bnd_id * 100 + nbh * 10 + cell_w)
    grids = [rng.integers(0, 1 << cell_w, (gy, gx)) for _ in range(passes)]
    seq = [row for g in grids for row in virtual_rows(g, nbh, bnd)]
    words = [w for row in seq for w in rtlsim.row_words(row, cell_w, dw)]
    (tmp_path / "rows.hex").write_text(rtlsim.words_hex(words, dw))
    exp = [w for g in grids for w in expected_windows(virtual_rows(g, nbh, bnd), nbh, bnd)]
    binary = rtlsim.build("tb_line_buffer", {"GRID_X": gx, "GRID_Y": gy, "CELL_W": cell_w, "NBH": nbh,
                                             "DATA_W": dw, "BND_ID": bnd_id, "PASSES": passes})
    for aclk_ps, eclk_ps in ((5000, 5000), (4000, 6000), (6000, 4000)):
        out = tmp_path / f"win_{aclk_ps}_{eclk_ps}.txt"
        rtlsim.run(binary, {"grid_hex": tmp_path / "rows.hex", "out_file": out,
                            "aclk_ps": aclk_ps, "eclk_ps": eclk_ps, "gap": 30})
        got = [np.array([int(t, 16) for t in line.split()]).reshape(nbh, nbh)
               for line in out.read_text().splitlines()]
        assert len(got) == len(exp)
        bad = next((k for k, (a, b) in enumerate(zip(got, exp)) if not np.array_equal(a, b)), None)
        assert bad is None, f"window {bad} (row {bad // gx}, col {bad % gx}) differs:\n{got[bad]}\nvs\n{exp[bad]}"
