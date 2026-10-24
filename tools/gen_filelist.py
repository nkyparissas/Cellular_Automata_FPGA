"""Write the ordered list of SystemVerilog sources needed by a top module
(project RTL plus the vendored files it uses), for Vivado and other tools.

Example:
    python3 tools/gen_filelist.py --top ca_display_system --out build/files_ca_display_system.f
"""
import argparse
import subprocess
import tempfile
from pathlib import Path

import rtlsim

ROOT = rtlsim.ROOT


def sources_for(top: str, extra_dirs=()) -> list[Path]:
    """Ask Verilator which files elaborating `top` reads (packages first)."""
    with tempfile.TemporaryDirectory() as tmp:
        top_file = next(p for d in ("rtl", *extra_dirs) for p in (ROOT / d).rglob(f"{top}.sv"))
        cmd = ["verilator", "--lint-only", "-Wno-fatal", "-Wno-lint", "-Wno-style", "--MMD", "--Mdir", tmp,
               *rtlsim._filelist_args(), "--top-module", top, str(top_file)]
        for d in extra_dirs:
            cmd += ["-y", str(ROOT / d)]
        subprocess.run(cmd, check=True, capture_output=True, text=True)
        dep = next(Path(tmp).glob("*.d")).read_text()
    files = [Path(t) for t in dep.replace("\\\n", " ").split() if t.endswith(".sv")]
    files = [p for p in dict.fromkeys(p.resolve() for p in files) if ROOT in p.parents]
    # Packages first: vendored ones, then the project's (ca_pkg before ca_regs_pkg).
    pkgs = sorted((p for p in files if p.name.endswith("_pkg.sv")),
                  key=lambda p: ("third_party" not in p.parts, p.name != "cf_math_pkg.sv", p.name))
    return pkgs + [p for p in files if p not in pkgs]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--top", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    files = sources_for(args.top)
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text("".join(f"{p.relative_to(ROOT)}\n" for p in files))
    print(f"{len(files)} files -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
