"""Directed GHDL checks of findings documented in docs/legacy_vhdl_findings.md.
Each testbench prints FINDING<n> CONFIRMED or FINDING<n> NOT_REPRODUCED."""
import os
import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
LEGACY = Path(os.environ.get("LEGACY_DIR", ROOT.parent / "Cellular_Automata_FPGA")) / "src" / "vhdl"
HERE = Path(__file__).parent
pytestmark = pytest.mark.skipif(not LEGACY.is_dir(), reason="legacy VHDL repository not found")


def run_tb(tb: str, sources, tmp: Path) -> str:
    opts = ["--std=08", "-frelaxed", f"--workdir={tmp}"]
    for s in [*sources, HERE / f"{tb}.vhd"]:
        subprocess.run(["ghdl", "-a", *opts, str(s)], check=True, capture_output=True, text=True, cwd=tmp)
    subprocess.run(["ghdl", "-e", *opts, tb], check=True, capture_output=True, text=True, cwd=tmp)
    r = subprocess.run(["ghdl", "-r", *opts, tb, "--stop-time=1ms", "--ieee-asserts=disable"],
                       capture_output=True, text=True, cwd=tmp, timeout=600)
    m = re.search(r"(FINDING\d (?:CONFIRMED|NOT_REPRODUCED).*)", r.stdout + r.stderr)
    assert m, (r.stdout + r.stderr)[-2000:]
    print(m.group(1))
    return m.group(1)


def test_finding2_initializer_third_beat(tmp_path):
    verdict = run_tb("tb_finding_init", [LEGACY / "MEMORY_INITIALIZER.vhd"], tmp_path)
    assert "CONFIRMED" in verdict


def test_finding3_writeback_grant(tmp_path):
    verdict = run_tb("tb_finding_writeback", [LEGACY / "WRITE_BACK.vhd"], tmp_path)
    assert "CONFIRMED" in verdict


def test_finding1_speed_desync(tmp_path):
    verdict = run_tb("tb_finding_speed", [LEGACY / "GRAPHICS_FEEDER.vhd", LEGACY / "WRITE_BACK.vhd"], tmp_path)
    assert "CONFIRMED" in verdict
