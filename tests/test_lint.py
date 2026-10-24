"""Lint gate: every RTL top listed in the Makefile lints clean under Verilator -Wall."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(cmd):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)


def test_rtl_lint_clean():
    r = run(["make", "lint"])
    assert r.returncode == 0, r.stdout + r.stderr
