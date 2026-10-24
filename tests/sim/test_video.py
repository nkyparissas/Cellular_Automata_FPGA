"""ca_video_out: displayed pixels equal the model palette of the streamed frames."""
import numpy as np
import pytest

import rtlsim
from ca_model.grids import to_rgb

PALETTES = {0: ("gray", 8), 1: ("legacy4_windows", 4), 2: ("legacy4_gradient", 4), 3: ("legacy8", 8)}
HA, VA, NFRAMES, DW = 16, 8, 6, 32


def run_video(pal_id, tmp_path, starve=None):
    name, cw = PALETTES[pal_id]
    rng = np.random.default_rng(pal_id)
    frames = [rng.integers(0, 1 << cw, (VA, HA)) for _ in range(NFRAMES)]
    words = [w for f in frames for row in f for w in rtlsim.row_words(row, cw, DW)]
    (tmp_path / "frames.hex").write_text(rtlsim.words_hex(words, DW))
    binary = rtlsim.build("tb_video", {"DATA_W": DW, "CELL_W": cw, "PAL_ID": pal_id, "NFRAMES": NFRAMES})
    plus = {"frames_hex": tmp_path / "frames.hex", "out_file": tmp_path / "pix.txt"}
    if starve is not None:
        plus["starve_req"] = starve
    log = rtlsim.run(binary, plus)
    shown = {}
    for line in (tmp_path / "pix.txt").read_text().splitlines():
        k, v = line.split()
        shown.setdefault(int(k), []).append(int(v, 16))
    disp = {k: np.array([[(p >> 16) & 255, (p >> 8) & 255, p & 255] for p in v]).reshape(VA, HA, 3)
            for k, v in shown.items() if len(v) == HA * VA}
    return name, cw, frames, disp, log


@pytest.mark.parametrize("pal_id", list(PALETTES), ids=[p[0] for p in PALETTES.values()])
def test_video(pal_id, tmp_path):
    name, cw, frames, disp, log = run_video(pal_id, tmp_path)
    # Video frames are counted from vsync; the request made in the blanking
    # before video frame k delivers source frame k.
    for k in range(NFRAMES):
        assert np.array_equal(disp[k], to_rgb(frames[k], cw, name)), f"video frame {k}"
    assert not disp[-1].any(), "nothing is shown before the first frame arrives"
    assert "underflow=0" in log


def test_video_underflow_recovers(tmp_path):
    name, cw, frames, disp, log = run_video(0, tmp_path, starve=2)
    assert "underflow=1" in log
    assert np.array_equal(disp[0], to_rgb(frames[0], cw, name))
    assert np.array_equal(disp[1], to_rgb(frames[1], cw, name))
    assert not disp[2].any(), "starved frame must be black"
    assert np.array_equal(disp[3], to_rgb(frames[2], cw, name))
