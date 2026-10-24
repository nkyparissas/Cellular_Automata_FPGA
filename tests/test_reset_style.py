"""Project RTL uses synchronous resets only (vendored third_party code excepted)."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASYNC = re.compile(r"always(_ff)?\s*@\s*\([^)]*\b(or|,)\s*(neg|pos)edge\b", re.S)


def test_rtl_resets_are_synchronous():
    offenders = []
    for d in ("rtl", "boards"):
        for f in (ROOT / d).rglob("*.sv"):
            for m in ASYNC.finditer(f.read_text()):
                line = f.read_text()[:m.start()].count("\n") + 1
                offenders.append(f"{f.relative_to(ROOT)}:{line}")
    assert not offenders, offenders
