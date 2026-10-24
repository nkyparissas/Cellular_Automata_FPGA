"""host/ca_host/regs.py mirrors rtl/ctrl/ca_regs_pkg.sv."""
import re
from pathlib import Path

from ca_host import regs

ROOT = Path(__file__).resolve().parents[2]


def sv_constants():
    src = (ROOT / "rtl" / "ctrl" / "ca_regs_pkg.sv").read_text()
    out = {}
    for name, width, base, val in re.findall(
            r"localparam\s+(?:logic\s*\[[^\]]*\]|int\s+unsigned)?\s*(\w+)\s*=\s*(?:(\d+)'([hdb]))?([0-9A-Fa-f_]+)\s*;", src):
        v = val.replace("_", "")
        out[name] = int(v, {"h": 16, "b": 2}.get(base, 10))
    return out


def test_regs_parity():
    sv = sv_constants()
    assert sv, "no constants parsed"
    py = {k: v for k, v in vars(regs).items() if k.isupper()}
    assert sv == py
