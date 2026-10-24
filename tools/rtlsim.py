"""Build and run SystemVerilog testbenches with Verilator (--binary --timing)."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _filelist_args():
    args = []
    for raw in (ROOT / "rtl" / "files.f").read_text().splitlines():
        line = raw.split("//")[0].strip()
        if not line:
            continue
        if line.startswith("+incdir+"):
            args.append("+incdir+" + str(ROOT / line[len("+incdir+"):]))
        elif line.startswith("-y "):
            args += ["-y", str(ROOT / line[3:].strip())]
        else:
            args.append(str(ROOT / line))
    return args


def build(tb_top: str, params: dict | None = None, defines: dict | None = None,
          out_dir: Path | None = None, extra=()) -> Path:
    """Compile ``sim/**/<tb_top>.sv`` into a binary and return its path."""
    params = dict(params or {})
    defines = dict(defines or {})
    tag = hashlib.sha1(json.dumps([tb_top, params, defines, list(extra)], sort_keys=True).encode()).hexdigest()[:10]
    out_dir = Path(out_dir or ROOT / "build" / "sim" / f"{tb_top}_{tag}")
    out_dir.mkdir(parents=True, exist_ok=True)
    top_file = next((ROOT / "sim").rglob(f"{tb_top}.sv"))
    cmd = ["verilator", "--binary", "--timing", "-O2", "-Wno-fatal", "-Wno-lint", "-Wno-style",
           "--x-assign", "unique", "--x-initial", "unique",
           str(ROOT / "rtl" / "lint.vlt"), *_filelist_args(), "-y", str(ROOT / "sim" / "tb"),
           "-y", str(ROOT / "sim" / "models"), "+incdir+" + str(ROOT / "sim" / "models"),
           "--top-module", tb_top, "-Mdir", str(out_dir / "obj"), "-o", tb_top,
           "-j", str(os.cpu_count() or 4), *extra, str(top_file)]
    cmd += [f"-G{k}={v}" for k, v in params.items()]
    cmd += [f"+define+{k}={v}" for k, v in defines.items()]
    log = out_dir / "build.log"
    with open(log, "w") as fh:
        r = subprocess.run(cmd, cwd=out_dir, stdout=fh, stderr=subprocess.STDOUT)
    if r.returncode != 0:
        raise RuntimeError(f"verilator build failed for {tb_top}; see {log}\n" + log.read_text()[-3000:])
    return out_dir / "obj" / tb_top


def run(binary: Path, plusargs: dict | None = None, timeout_s: float = 600, cwd: Path | None = None) -> str:
    """Run a testbench binary; raise unless its output contains TB_PASS."""
    args = [str(binary), "+verilator+rand+reset+2", "+verilator+seed+7"]
    for k, v in (plusargs or {}).items():
        args.append(f"+{k}" if v is None else f"+{k}={v}")
    r = subprocess.run(args, cwd=cwd or binary.parent, capture_output=True, text=True, timeout=timeout_s)
    out = r.stdout + r.stderr
    (Path(cwd or binary.parent) / "run.log").write_text(out)
    if r.returncode != 0 or "TB_PASS" not in out:
        raise AssertionError(f"testbench failed (rc={r.returncode}):\n{out[-4000:]}")
    return out


def words_hex(words, data_w: int) -> str:
    digits = data_w // 4
    return "".join(f"{w:0{digits}x}\n" for w in words)


def row_words(row, cell_w: int, data_w: int):
    """Pack one row of cells into DATA_W-bit words (first cell in the low bits)."""
    per = data_w // cell_w
    out = []
    for b in range(0, len(row), per):
        out.append(sum(int(c) << (k * cell_w) for k, c in enumerate(row[b:b + per])))
    return out
