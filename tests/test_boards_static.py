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


# ------------------------------------------------------------ ALINX AXAU25
AXAU25 = ROOT / "boards" / "alinx_axau25"
XDC_SET = re.compile(r"set_property\s+(?:-dict\s+\{(?P<dict>[^}]*)\}|(?P<key>\S+)\s+(?P<val>\S+))"
                     r"\s+\[get_ports\s+(?P<ports>\{[^}]*\}|[^\]\s]+)\]")


def xdc_pins(xdc: str) -> dict[str, tuple[str, str | None]]:
    """Port -> (package pin, I/O standard or None) from an XDC file; I/O standards may
    name ports with Vivado wildcards (*)."""
    sets = []
    for m in XDC_SET.finditer(xdc):
        props = dict(zip(*[iter(m["dict"].split())] * 2)) if m["dict"] else {m["key"]: m["val"]}
        sets.append((props, m["ports"].strip("{}").split()))
    pins = {}
    for props, ports in sets:
        if "PACKAGE_PIN" in props:
            assert len(ports) == 1 and ports[0] not in pins, f"{ports} placed twice or together"
            pins[ports[0]] = props["PACKAGE_PIN"]
    std = {}
    for props, patterns in sets:
        if "IOSTANDARD" in props:
            for pat in patterns:
                rx = ".*".join(map(re.escape, pat.split("*")))
                hits = [p for p in pins if re.fullmatch(rx, p)]
                assert hits, f"IOSTANDARD pattern {pat} matches no placed port"
                std.update({p: props["IOSTANDARD"] for p in hits})
    return {p: (pin, std.get(p)) for p, pin in pins.items()}


def axau25_ddr4_ports() -> set[str]:
    bits = {"adr": 17, "dq": 16, "dqs_t": 2, "dqs_c": 2, "dm_n": 2, "ba": 2, "bg": 1, "ck_t": 1, "ck_c": 1,
            "cke": 1, "cs_n": 1, "odt": 1}
    return {f"c0_ddr4_{s}[{i}]" for s, n in bits.items() for i in range(n)} | {"c0_ddr4_act_n", "c0_ddr4_reset_n"}


def test_axau25_constraints():
    """Every external pin of the AXAU25 design is placed exactly once, on a distinct
    package pin, as in the ALINX user manuals (ACAU25 V1.0 Tables 2.3.1 and 2.4.2,
    AXAU25 V1.0 Tables 3.3.1 and 3.11.1)."""
    xdc = (AXAU25 / "axau25.xdc").read_text()
    pins = xdc_pins(xdc)
    used = [pin for pin, _ in pins.values()]
    assert len(used) == len(set(used)), sorted({p for p in used if used.count(p) > 1})
    expected = axau25_ddr4_ports() | {"sys_clk_200_clk_p", "sys_clk_200_clk_n", "pcie_refclk_clk_p",
                                      "pcie_refclk_clk_n", "pcie_perstn", "led_ddr_calib", "led_pcie_link"}
    assert set(pins) == expected, (sorted(expected - set(pins)), sorted(set(pins) - expected))
    manual = {"sys_clk_200_clk_p": "T24", "sys_clk_200_clk_n": "U24", "pcie_refclk_clk_p": "AB7",
              "pcie_refclk_clk_n": "AB6", "pcie_perstn": "T19", "led_ddr_calib": "W21", "led_pcie_link": "AC16",
              "c0_ddr4_adr[0]": "G25", "c0_ddr4_adr[13]": "H24", "c0_ddr4_adr[14]": "K26",   # A14 = WE_B
              "c0_ddr4_adr[15]": "H22", "c0_ddr4_adr[16]": "H21",                            # CAS_B, RAS_B
              "c0_ddr4_dq[0]": "F23", "c0_ddr4_dq[8]": "M20", "c0_ddr4_dq[15]": "K21", "c0_ddr4_dqs_t[0]": "D23",
              "c0_ddr4_dqs_c[1]": "L19", "c0_ddr4_dm_n[1]": "L18", "c0_ddr4_odt[0]": "M24", "c0_ddr4_reset_n": "G24"}
    for port, pin in manual.items():
        assert pins[port][0] == pin, f"{port}: {pins[port][0]}, manual {pin}"
    for port in ("pcie_perstn", "led_ddr_calib", "led_pcie_link"):    # 1.8 V banks 64 and 65
        assert pins[port][1] == "LVCMOS18", port
    assert pins["pcie_refclk_clk_p"][1] is None                       # GT reference clock
    assert all(pins[p][1] for p in axau25_ddr4_ports()), "every DDR4 pin needs its I/O standard"
    for key in ("CONFIG_VOLTAGE 1.8", "CONFIG_MODE SPIx4", "BITSTREAM.CONFIG.SPI_BUSWIDTH 4",
                "BITSTREAM.GENERAL.COMPRESS TRUE"):
        assert f"set_property {key} [current_design]" in xdc, key
    assert re.search(r"create_clock\s+-period\s+10\.000\s+-name\s+pcie_refclk\s+\[get_ports\s+pcie_refclk_clk_p\]", xdc)


def dry_run_vivado_script(script: Path, argv=()) -> list[list[str]]:
    """Run a Vivado Tcl script in a plain Tcl interpreter: every Vivado command is
    recorded and returns an empty string (get_* commands return the object name they
    were given), and only python3 subprocesses really run. Catches Tcl syntax errors,
    misspelt variables and missing files."""
    tkinter = pytest.importorskip("tkinter")
    tcl = tkinter.Tcl()
    tcl.eval("rename exec _exec; proc exec {args} { if {[lindex $args 0] eq {python3}} { return [_exec {*}$args] }; return {} }")
    tcl.eval("set ::calls {}; proc unknown {args} { lappend ::calls $args; "
             "if {[string match get_* [lindex $args 0]]} { return [lindex $args end] }; return {} }")
    tcl.call("set", "argv", tcl.call("list", *argv))
    tcl.call("set", "argc", len(argv))
    tcl.call("source", str(script))
    return [list(tcl.splitlist(c)) for c in tcl.splitlist(tcl.eval("set ::calls"))]


def bd_properties(calls, cell: str) -> dict[str, str]:
    """CONFIG.* values set on a block-design cell with set_property -dict."""
    out = {}
    for c in calls:
        if c[:2] == ["set_property", "-dict"] and len(c) == 4:
            kv = c[2].split() if " " in c[2] else []
            if kv and cell in c[3]:
                out.update(zip(kv[0::2], kv[1::2]))
    return out


@pytest.mark.parametrize("core_aclk", ["0", "125"])
def test_axau25_build_script_dry_run(core_aclk):
    """build.tcl runs through in a plain Tcl interpreter with stub Vivado commands (with the
    core's AXI side on the XDMA user clock and on its own clock), configures the IP for the
    board, exports only the ports the XDC places, and ends with a bitstream and a flash image."""
    calls = dry_run_vivado_script(AXAU25 / "build.tcl", ["configs/lenia_orbium.json", core_aclk])
    names = [c[0] for c in calls]
    assert ["create_project", "ca_axau25"] == calls[names.index("create_project")][:2]
    assert any(c[0] == "create_project" and "xcau25p-ffvb676-2-i" in c for c in calls)
    cells = {c[-1]: c[c.index("-vlnv") + 1] for c in calls if c[0] == "create_bd_cell" and "-vlnv" in c}
    for ip in ("xdma", "ddr4", "smartconnect", "clk_wiz", "util_ds_buf", "proc_sys_reset"):
        assert any(v.split(":")[2] == ip for v in cells.values()), ip
    xdma = bd_properties(calls, "xdma_0")
    assert xdma["CONFIG.pl_link_cap_max_link_width"] == "X4" and xdma["CONFIG.pl_link_cap_max_link_speed"] == "8.0_GT/s"
    assert xdma["CONFIG.axi_data_width"] == "128_bit" and xdma["CONFIG.select_quad"] == "GTY_Quad_224"
    ddr = bd_properties(calls, "ddr4_0")
    assert ddr["CONFIG.C0.DDR4_MemoryPart"] == "MT40A512M16LY-062E" and ddr["CONFIG.C0.DDR4_DataWidth"] == "16"
    assert ddr["CONFIG.C0.DDR4_AxiDataWidth"] == "128" and ddr["CONFIG.C0.DDR4_InputClockPeriod"] == "5000"
    assert ddr["CONFIG.C0.DDR4_TimePeriod"] == "833" and ddr["CONFIG.C0.DDR4_AxiSelection"] == "true"
    smc_mem = bd_properties(calls, "smc_mem")
    assert smc_mem["CONFIG.NUM_CLKS"] == ("2" if core_aclk == "0" else "3")
    assert any(c[:3] == ["set_property", "range", "64K"] and "SEG_ca_core_reg0" in c[3] for c in calls)
    # Exported ports: exactly what axau25.xdc places (the GT lanes are placed by the XDMA IP).
    ports = {c[-1] for c in calls if c[0] in ("create_bd_port", "create_bd_intf_port")}
    assert ports == {"pcie_refclk", "pcie_mgt", "pcie_perstn", "sys_clk_200", "c0_ddr4", "led_ddr_calib",
                     "led_pcie_link"}
    owner = {p: [q for q in ports if p == q or p.startswith(q + "_")] for p in xdc_pins((AXAU25 / "axau25.xdc").read_text())}
    assert all(len(o) == 1 for o in owner.values()), {p: o for p, o in owner.items() if len(o) != 1}
    assert {o[0] for o in owner.values()} == ports - {"pcie_mgt"}
    assert any(c[0] == "launch_runs" and "impl_1" in c and "write_bitstream" in c for c in calls)
    assert any(c[0] == "write_cfgmem" and "SPIx4" in c for c in calls)
    out = ROOT / "build" / "alinx_axau25"
    assert re.search(r"`define CA_DATA_W\s+128\b", (out / "ca_cfg.vh").read_text())
    groups = (out / "clocks.xdc").read_text()
    assert groups.count("-group") == (2 if core_aclk == "0" else 3)
    assert any(c[:3] == ["set_property", "USED_IN_SYNTHESIS", "false"] and c[3].endswith("clocks.xdc") for c in calls)
    r = subprocess.run(["verilator", "--lint-only", "-Wall", "--timing", "rtl/lint.vlt", "-f", "rtl/files.f",
                        f"+incdir+{out}", "--top-module", "ca_core_xdma", "boards/xdma_template/ca_core_xdma.v"],
                       cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
