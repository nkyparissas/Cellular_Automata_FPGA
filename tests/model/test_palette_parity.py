"""rtl/consumers/ca_palette.sv mirrors the viridis table of model/ca_model/viridis.py."""
import re
from pathlib import Path

from ca_model.viridis import VIRIDIS

ROOT = Path(__file__).resolve().parents[2]


def test_viridis_table_matches_rtl():
    src = (ROOT / "rtl" / "consumers" / "ca_palette.sv").read_text()
    body = re.search(r"localparam\s+logic\s*\[23:0\]\s+VIRIDIS\s*\[256\]\s*=\s*'\{(.*?)\};", src, re.S).group(1)
    sv = [int(v, 16) for v in re.findall(r"24'h([0-9A-Fa-f]{6})", body)]
    assert len(VIRIDIS) == 256 and VIRIDIS[0] == 0x440154 and VIRIDIS[-1] == 0xFDE725
    assert sv == VIRIDIS
