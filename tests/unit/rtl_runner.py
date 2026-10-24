"""Build and run cocotb unit tests on Verilator with the project file list."""
import hashlib
import json
import xml.etree.ElementTree as ET
from pathlib import Path

from cocotb_tools.runner import get_runner

ROOT = Path(__file__).resolve().parents[2]


def filelist(path: Path = ROOT / "rtl" / "files.f"):
    """Parse rtl/files.f into (sources, includes, build_args) with absolute paths."""
    sources, includes, args = [], [], []
    lines = path.read_text().splitlines()
    for raw in lines:
        line = raw.split("//")[0].strip()
        if not line:
            continue
        if line.startswith("+incdir+"):
            includes.append(ROOT / line[len("+incdir+"):])
        elif line.startswith("-y "):
            args += ["-y", str(ROOT / line[3:].strip())]
        else:
            sources.append(ROOT / line)
    return sources, includes, args


def run_cocotb(toplevel: str, test_module: str, parameters: dict | None = None,
               extra_sources=(), testcase=None, seed: int = 1, plusargs=()):
    """Compile ``toplevel`` (found through files.f and ``extra_sources``) and run
    the cocotb tests of ``tests/unit/<test_module>.py``; raise on any failure."""
    parameters = dict(parameters or {})
    sources, includes, args = filelist()
    sources += [ROOT / s for s in extra_sources]
    top_files = [p for d in ("rtl", "sim") for p in (ROOT / d).rglob(f"{toplevel}.sv")]
    if top_files and top_files[0] not in sources:
        sources.append(top_files[0])
    tag = hashlib.sha1(json.dumps([toplevel, parameters, [str(s) for s in extra_sources]],
                                  sort_keys=True).encode()).hexdigest()[:10]
    build_dir = ROOT / "build" / "unit" / f"{toplevel}_{tag}"
    runner = get_runner("verilator")
    runner.build(sources=sources, includes=includes, parameters=parameters,
                 build_args=args + ["-y", str(ROOT / "sim" / "tb"), "-Wno-fatal", "--x-assign", "unique",
                                    "--x-initial", "unique", str(ROOT / "rtl" / "lint.vlt")],
                 hdl_toplevel=toplevel, build_dir=build_dir, always=True,
                 log_file=build_dir / "build.log")
    xml = runner.test(test_module=test_module, hdl_toplevel=toplevel, build_dir=build_dir,
                      test_dir=Path(__file__).parent, testcase=testcase, seed=seed,
                      plusargs=list(plusargs) + ["+verilator+rand+reset+2"],
                      results_xml=str(build_dir / f"{testcase or test_module}.results.xml"),
                      log_file=build_dir / f"{test_module}.log")
    root = ET.parse(xml).getroot()
    cases = root.findall(".//testcase")
    failed = [c.get("name") for c in cases if c.find("failure") is not None or c.find("error") is not None]
    assert cases, f"no cocotb tests ran for {toplevel} (see {build_dir})"
    assert not failed, f"cocotb failures in {toplevel}: {failed} (log: {build_dir / (test_module + '.log')})"
