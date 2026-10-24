"""Static checks of the board folders (no Vivado available)."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_nexys4ddr_top_lints():
    r = subprocess.run(["make", "lint-boards"], cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


def test_nexys4ddr_mig_project_uses_axi():
    prj = (ROOT / "boards" / "nexys4ddr" / "ip" / "mig_ddr2_axi.prj").read_text()
    for key in ("<PortInterface>AXI</PortInterface>", "<C0_S_AXI_DATA_WIDTH>128</C0_S_AXI_DATA_WIDTH>",
                "<ModuleName>mig_ddr2_axi</ModuleName>", "<SysResetPolarity>ACTIVE LOW</SysResetPolarity>"):
        assert key in prj
