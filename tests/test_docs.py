"""Documentation stays consistent with the repository."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ["README.md", "docs/architecture.md", "docs/adding_a_rule.md", "docs/register_map.md"]
PATHLIKE = re.compile(r"^[\w.\-]+(/[\w.\-*]+)+/?$|^[\w\-]+\.(sv|py|json|md|tcl|xdc|prj|f|vlt)$")


def inline_code(text: str):
    text = re.sub(r"```.*?```", "", text, flags=re.S)        # fenced blocks may show files to create
    return re.findall(r"`([^`\n]+)`", text)


def test_docs_reference_existing_files():
    missing = []
    for doc in DOCS:
        text = (ROOT / doc).read_text()
        for ref in inline_code(text):
            ref = ref.split("::")[0].split(":")[0] if not ref.startswith("/") else ref
            if PATHLIKE.match(ref):
                if not list(ROOT.glob(ref)) and not (ROOT / ref).exists():
                    missing.append(f"{doc}: {ref}")
    assert not missing, missing


def test_register_map_doc_matches_pkg():
    pkg = (ROOT / "rtl" / "ctrl" / "ca_regs_pkg.sv").read_text()
    sv = {name: int(val, 16) for name, val in re.findall(r"REG_(\w+)\s*=\s*8'h([0-9A-Fa-f]+)", pkg)}
    doc = (ROOT / "docs" / "register_map.md").read_text()
    rows = {name: int(off, 16) for off, name in re.findall(r"^\|\s*0x([0-9A-Fa-f]+)\s*\|\s*([A-Z_0-9]+)\s*\|", doc, re.M)}
    assert rows, "no register rows found"
    for name, off in sv.items():
        assert rows.get(name) == off, f"{name}: doc {rows.get(name)} vs pkg 0x{off:02x}"
