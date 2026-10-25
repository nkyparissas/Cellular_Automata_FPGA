"""Static checks of the board folders (no Vivado available)."""
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
YOSYS = shutil.which("yosys")
HAS_SLANG = bool(YOSYS) and (Path(YOSYS).resolve().parents[1] / "share" / "yosys" / "plugins" / "slang.so").exists()
INCDIRS = [ROOT / "third_party" / "axi" / "include", ROOT / "third_party" / "common_cells" / "include"]


def _xdma_sources():
    """The module-reference source and configuration header named by bd_ca_xdma.tcl."""
    tcl = (ROOT / "boards" / "xdma_template" / "bd_ca_xdma.tcl").read_text()
    src = re.search(r"add_files -norecurse \$root/(boards/xdma_template/ca_core_xdma\.\w+)", tcl).group(1)
    hdr = re.search(r"gen_cfg\.py [^\n]*--out \$out/(ca_cfg\.\w+)", tcl).group(1)
    return ROOT / src, hdr


def _gen_cfg(out: Path, data_w: int) -> None:
    subprocess.run(["python3", str(ROOT / "tools" / "gen_cfg.py"), "--config", str(ROOT / "configs" / "hodgepodge29.json"),
                    "--data-w", str(data_w), "--out", str(out)], check=True, capture_output=True)


def test_xdma_module_reference_is_verilog(tmp_path):
    """Vivado module references need a Verilog or VHDL top (UG994: SystemVerilog is not supported)."""
    src, hdr = _xdma_sources()
    assert src.suffix == ".v", f"{src.name}: the block-design module reference must be a Verilog-2001 file"
    _gen_cfg(tmp_path / hdr, 512)
    r = subprocess.run([YOSYS or "yosys", "-q", "-p", f"read_verilog -I{tmp_path} {src}"],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


@pytest.mark.skipif(not HAS_SLANG, reason="yosys-slang not available")
@pytest.mark.parametrize("board", ["xdma_template", "nexys4ddr"])
def test_board_top_strict_lrm(board, tmp_path):
    """Elaborate each board top with slang, which (unlike Verilator) enforces declaration before use."""
    import gen_filelist
    if board == "xdma_template":
        top_file, hdr = _xdma_sources()
        _gen_cfg(tmp_path / hdr, 512)
        files = gen_filelist.sources_for("ca_core_flat") + [top_file]
    else:
        top_file = ROOT / "boards" / "nexys4ddr" / "top_nexys4ddr.sv"
        _gen_cfg(tmp_path / "ca_cfg.svh", 128)
        files = (gen_filelist.sources_for("ca_display_system") + sorted((ROOT / "boards" / board / "stubs").glob("*.sv"))
                 + [top_file])
    incs = " ".join(f"-I {d}" for d in [tmp_path, *INCDIRS])
    cmd = f"read_slang --ast-compilation-only {incs} --top {top_file.stem} " + " ".join(str(f) for f in files)
    r = subprocess.run([YOSYS, "-q", "-m", "slang", "-p", cmd], capture_output=True, text=True, timeout=600)
    assert r.returncode == 0, (r.stdout + r.stderr)[-3000:]


def test_nexys4ddr_top_lints():
    r = subprocess.run(["make", "lint-boards"], cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


def mmcm_best_error(f_in: float, outs: list[float]) -> float:
    """Smallest worst-case relative error with which one 7-series MMCM (Artix-7 -1:
    VCO 600-1200 MHz, PFD 10-450 MHz, M 2-64 and CLKOUT0 2-128 in 1/8 steps, other
    outputs integer 1-128) produces ``outs``; clk_out1 of the wizard is CLKOUT0."""
    best = float("inf")
    for d in range(1, 107):
        pfd = f_in / d
        if pfd < 10:
            break
        if pfd > 450:
            continue
        for m8 in range(16, 513):
            vco = pfd * m8 / 8
            if not 600 <= vco <= 1200:
                continue
            worst = 0.0
            for k, f in enumerate(outs):
                if k == 0:
                    divs = [o8 / 8 for o8 in (int(vco * 8 / f), int(vco * 8 / f) + 1) if 16 <= o8 <= 1024]
                else:
                    divs = [o for o in (int(vco / f), int(vco / f) + 1) if 1 <= o <= 128]
                worst = max(worst, min((abs(vco / o - f) / f for o in divs), default=float("inf")))
            best = min(best, worst)
    return best


def nexys_clock_wizards() -> dict[str, tuple[float, list[float]]]:
    """Input and requested output frequencies of every clk_wiz created by build.tcl."""
    tcl = (ROOT / "boards" / "nexys4ddr" / "build.tcl").read_text()
    wiz = {}
    for m in re.finditer(r"create_ip -name clk_wiz .*-module_name (\w+)", tcl):
        name = m.group(1)
        block = re.compile(r"set_property -dict \[list(.*?)\] \[get_ips " + name + r"\]", re.S).search(tcl, m.end()).group(1)
        f_in = float(re.search(r"PRIM_IN_FREQ \{([\d.]+)\}", block).group(1))
        outs = [float(re.search(rf"CLKOUT{k}_REQUESTED_OUT_FREQ \{{([\d.]+)\}}", block).group(1))
                for k in range(1, 8) if k == 1 or f"CLKOUT{k}_USED {{true}}" in block]
        wiz[name] = (f_in, outs)
    return wiz


def test_nexys4ddr_clocks_feasible():
    """Each clocking wizard must be able to produce its frequencies: the MIG system
    clock (325 MHz), its 200 MHz reference and the 148.5 MHz 1080p60 pixel clock."""
    wiz = nexys_clock_wizards()
    requested = sorted(f for _, outs in wiz.values() for f in outs)
    assert requested == [148.5, 200.0, 325.0], requested
    top = (ROOT / "boards" / "nexys4ddr" / "top_nexys4ddr.sv").read_text()
    for name, (f_in, outs) in wiz.items():
        err = mmcm_best_error(f_in, outs)
        assert err <= 1e-3, f"{name}: {outs} MHz from {f_in} MHz is off by {err:.2%} at best on one MMCM"
        assert re.search(rf"^\s*{name}\s+\w+\s*\(", top, re.M), f"{name} is not instantiated in the top level"
        assert (ROOT / "boards" / "nexys4ddr" / "stubs" / f"{name}.sv").exists(), f"lint stub for {name} missing"


def test_nexys4ddr_mig_project_uses_axi():
    prj = (ROOT / "boards" / "nexys4ddr" / "ip" / "mig_ddr2_axi.prj").read_text()
    for key in ("<PortInterface>AXI</PortInterface>", "<C0_S_AXI_DATA_WIDTH>128</C0_S_AXI_DATA_WIDTH>",
                "<ModuleName>mig_ddr2_axi</ModuleName>", "<SysResetPolarity>ACTIVE LOW</SysResetPolarity>"):
        assert key in prj


XDMA_VARS = ("part", "board_part", "pcie_lanes", "pcie_gen", "ddr_interface", "eclk_mhz", "grid_x", "grid_y",
             "config", "data_w")


def test_xdma_template_static():
    tcl = (ROOT / "boards" / "xdma_template" / "bd_ca_xdma.tcl").read_text()
    for v in XDMA_VARS:
        assert f"set {v} " in tcl, f"template variable {v} missing"
    for needle in ("ca_core_xdma", "xilinx.com:ip:xdma", "xilinx.com:ip:smartconnect", "assign_bd_address"):
        assert needle in tcl
    r = subprocess.run(["make", "lint-boards"], cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "ca_core_xdma" in (ROOT / "Makefile").read_text()
