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


CONFIGS = ["hodgepodge29.json", "lenia_orbium.json"]


def _gen_cfg(out: Path, data_w: int, config: str = "hodgepodge29.json") -> None:
    subprocess.run(["python3", str(ROOT / "tools" / "gen_cfg.py"), "--config", str(ROOT / "configs" / config),
                    "--data-w", str(data_w), "--out", str(out)], check=True, capture_output=True)


@pytest.mark.parametrize("config", CONFIGS)
def test_xdma_module_reference_is_verilog(config, tmp_path):
    """Vivado module references need a Verilog or VHDL top (UG994: SystemVerilog is not supported)."""
    src, hdr = _xdma_sources()
    assert src.suffix == ".v", f"{src.name}: the block-design module reference must be a Verilog-2001 file"
    _gen_cfg(tmp_path / hdr, 512, config)
    r = subprocess.run([YOSYS or "yosys", "-q", "-p", f"read_verilog -I{tmp_path} {src}"],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


@pytest.mark.skipif(not HAS_SLANG, reason="yosys-slang not available")
def test_xdma_wrapper_uses_every_macro(tmp_path):
    """Every configuration macro of ca_cfg.vh reaches the core (a missing one silently takes a default)."""
    src, hdr = _xdma_sources()
    _gen_cfg(tmp_path / hdr, 512, "lenia_orbium.json")
    macros = set(re.findall(r"`define\s+(CA_\w+)", (tmp_path / hdr).read_text())) - {"CA_CFG_VH"}
    used = set(re.findall(r"`(CA_\w+)", src.read_text()))
    assert macros <= used, f"unused macros: {sorted(macros - used)}"


@pytest.mark.parametrize("config", CONFIGS)
@pytest.mark.parametrize("board", ["xdma_template", "nexys4ddr"])
def test_board_top_strict_lrm(board, config, tmp_path):
    """Elaborate each board top with slang, which (unlike Verilator) enforces declaration before use."""
    import gen_filelist
    if board == "xdma_template":
        top_file, hdr = _xdma_sources()
        _gen_cfg(tmp_path / hdr, 512, config)
        files = gen_filelist.sources_for("ca_core_flat") + [top_file]
    else:
        top_file = ROOT / "boards" / "nexys4ddr" / "top_nexys4ddr.sv"
        _gen_cfg(tmp_path / "ca_cfg.svh", 128, config)
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
    # The register map spans 64 KB (GROWTH_TABLE window at 0x8000); a smaller default range drops table writes.
    assert re.search(r"set_property range 64K \[get_bd_addr_segs \{xdma_0/M_AXI_LITE/SEG_ca_core_reg0\}\]", tcl)
    r = subprocess.run(["make", "lint-boards"], cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "ca_core_xdma" in (ROOT / "Makefile").read_text()


def test_ooc_lenia_script():
    """Out-of-context timing script for the Lenia datapath (run in Vivado by the user; unverified here)."""
    import gen_filelist
    here = ROOT / "boards" / "ooc_lenia"
    tcl = (here / "ooc_lenia.tcl").read_text()
    assert "xc7a100tcsg324-1" in tcl and "-mode out_of_context" in tcl
    for rel in re.findall(r"\$here/([\w/]+\.\w+)", tcl):
        assert (here / rel).is_file(), rel
    xdc = (here / "ooc_lenia.xdc").read_text()
    assert re.search(r"create_clock\s+-name\s+eclk\s+-period\s+5\.000\b", xdc)
    files = gen_filelist.sources_for("ooc_lenia_top", extra_dirs=("boards/ooc_lenia",))
    assert all(f.is_file() for f in files) and {"ca_rule_lenia.sv", "ooc_lenia_top.sv"} <= {f.name for f in files}
    r = subprocess.run(["verilator", "--lint-only", "-Wall", "--timing", "rtl/lint.vlt", "-f", "rtl/files.f",
                        "-y", "boards/ooc_lenia", "--top-module", "ooc_lenia_top", "boards/ooc_lenia/ooc_lenia_top.sv"],
                       cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
