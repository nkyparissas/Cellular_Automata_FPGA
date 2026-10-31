"""The default grid of every RTL module is 1920x1080; tests pass small sizes explicitly."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULES = ["rtl/top/ca_core.sv", "rtl/top/ca_core_flat.sv", "rtl/top/ca_display_system.sv", "rtl/ctrl/ca_regs.sv",
           "rtl/mem/ca_frame_reader.sv", "rtl/mem/ca_frame_writer.sv", "rtl/engine/ca_line_buffer.sv"]


def test_rtl_grid_defaults_are_1080p():
    wrong = []
    for rel in MODULES:
        src = (ROOT / rel).read_text()
        for name, want in (("GRID_X", 1920), ("GRID_Y", 1080)):
            found = re.findall(rf"parameter\s+int\s+unsigned\s+{name}\s*=\s*(\d+)", src)
            if found != [str(want)]:
                wrong.append(f"{rel}: {name} = {found}")
    assert not wrong, wrong
