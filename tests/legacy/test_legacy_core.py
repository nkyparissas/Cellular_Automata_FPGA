"""The legacy VHDL core (GHDL, behavioural IP models) against the golden model
for one generation of a small toroidal grid. Skipped when the legacy
repository is not available ($LEGACY_DIR, default ../Cellular_Automata_FPGA)."""
import os
import subprocess
from pathlib import Path

import numpy as np
import pytest

import rtlsim
from ca_model.step import step

ROOT = Path(__file__).resolve().parents[2]
LEGACY = Path(os.environ.get("LEGACY_DIR", ROOT.parent / "Cellular_Automata_FPGA")) / "src" / "vhdl"
HERE = Path(__file__).parent
pytestmark = pytest.mark.skipif(not LEGACY.is_dir(), reason="legacy VHDL repository not found")

CASES = {
    # name: (engine directory, cell_w, nbh, model configuration)
    "hodgepodge29": ("Hodgepodge n29", 8, 29, {"rule": "hodgepodge", "mask": "moore", "params": {"G": 105, "K": 5}}),
    "ghm29_moore": ("GHM", 4, 29, {"rule": "ghm", "mask": "moore", "params": {"T": 5, "STATES": 15, "E": 1}}),
    "ap21": ("Artificial Physics", 4, 21, {"rule": "interval", "mask": "ap21",
                                           "params": {"LO1": 20, "HI1": 23, "LO2": 59, "HI2": 100, "ALIVE": 1}}),
}


def seed_for(rule, cw, shape, rng):
    if rule == "hodgepodge":
        return rng.choice([0, 0, 0, 1, 50, 128, 200, 254, 255], size=shape)
    if rule == "ghm":
        return rng.choice([0, 0, 0, 0, 1, 1, 2, 7, 14], size=shape)
    return (rng.random(shape) < 0.25).astype(int)


def synthesised_buffer(tmp: Path) -> Path:
    """Copy of the legacy toroidal buffer patched so that simulation behaves
    like the synthesised circuit (docs/legacy_vhdl_findings.md, #13 and #14):
    the line-index type gets the range of the 6-bit register Vivado builds
    (the original declares 0 .. 2N-1 but increments past it), and the BRAM
    outputs get their own signal (in the original both the BRAM instances and
    the READ process drive LINE_DATA, so simulation turns every 1 into X).
    Timing is unchanged: RAM_OUT(I) is exactly the former LINE_DATA(0, I)."""
    src = (LEGACY / "GRID_LINES_TOROIDAL_BUFFER.vhd").read_text()
    edits = [
        ("OF INTEGER RANGE 0 TO NEIGHBORHOOD_SIZE+NEIGHBORHOOD_SIZE-1;", "OF INTEGER RANGE 0 TO 63;", 1),
        ("doutb => LINE_DATA(0, I)", "doutb => RAM_OUT(I)", 2),
        ("LINE_DATA(J, I) <= LINE_DATA(J-1, I);",
         "IF J = 1 THEN LINE_DATA(J, I) <= RAM_OUT(I); ELSE LINE_DATA(J, I) <= LINE_DATA(J-1, I); END IF;", 1),
        ("SIGNAL LINE_DATA : STD_LOGIC_ARRAY",
         "TYPE RAM_OUT_TYPE IS ARRAY (NEIGHBORHOOD_SIZE+NEIGHBORHOOD_SIZE-1 DOWNTO 0) OF "
         "STD_LOGIC_VECTOR(CELL_SIZE-1 DOWNTO 0);\n\tSIGNAL RAM_OUT : RAM_OUT_TYPE;\n\tSIGNAL LINE_DATA : STD_LOGIC_ARRAY", 1),
    ]
    for old, new, count in edits:
        assert src.count(old) == count, old
        src = src.replace(old, new)
    dst = tmp / "GRID_LINES_TOROIDAL_BUFFER_synth.vhd"
    dst.write_text(src)
    return dst


def run_legacy(name, grid, tmp: Path, col_file: Path | None = None):
    engine_dir, cw, nbh, _ = CASES[name]
    gy, gx = grid.shape
    words = [w for row in grid for w in rtlsim.row_words(row, cw, 128)]
    (tmp / "bursts.hex").write_text(rtlsim.words_hex(words, 128))
    work = tmp / "work"
    work.mkdir()
    srcs = [HERE / "models" / "line_buffer_model.vhd", HERE / "models" / "divider_model.vhd",
            LEGACY / "SYNCHRONIZER.vhd", synthesised_buffer(tmp),
            LEGACY / engine_dir / "CA_ENGINE.vhd", HERE / "tb_legacy_core.vhd"]
    opts = ["--std=08", "-frelaxed", f"--workdir={work}"]
    for s in srcs:
        subprocess.run(["ghdl", "-a", *opts, str(s)], check=True, capture_output=True, text=True, cwd=tmp)
    subprocess.run(["ghdl", "-e", *opts, "tb_legacy_core"], check=True, capture_output=True, text=True, cwd=tmp)
    r = subprocess.run(["ghdl", "-r", *opts, "tb_legacy_core", f"-gCELL_SIZE={cw}", f"-gNBH={nbh}",
                        f"-gGRID_X={gx}", f"-gGRID_Y={gy}", f"-gIN_FILE={tmp / 'bursts.hex'}",
                        f"-gOUT_FILE={tmp / 'cells.txt'}", *([f"-gCOL_FILE={col_file}"] if col_file else []),
                        "--stop-time=20ms", "--ieee-asserts=disable"],
                       capture_output=True, text=True, cwd=tmp, timeout=1800)
    assert "TB_PASS" in r.stdout + r.stderr, (r.stdout + r.stderr)[-3000:]
    return np.array([int(v) for v in (tmp / "cells.txt").read_text().split()]).reshape(gy, gx)


@pytest.mark.parametrize("name", list(CASES))
def test_legacy_core(name, tmp_path):
    _, cw, nbh, model = CASES[name]
    grid = seed_for(model["rule"], cw, (64, 64), np.random.default_rng(len(name))).astype(np.uint8)
    got = run_legacy(name, grid, tmp_path)
    cfg = dict(model, nbh=nbh, cell_w=cw, boundary="toroidal")
    exp = step(grid, cfg)
    diff = np.argwhere(got != exp)
    assert len(diff) == 0, (f"{len(diff)} cells differ, first at {tuple(diff[0])}: "
                            f"legacy {got[tuple(diff[0])]} model {exp[tuple(diff[0])]}")
