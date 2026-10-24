"""UART bridge, buttons and the display system (Nexys 4 DDR variant without the MIG)."""
import re

import numpy as np
import pytest

import rtlsim
from ca_model.step import step


@pytest.fixture(scope="module")
def tb_display():
    return rtlsim.build("tb_display")


def test_uart_bridge_protocol(tb_display):
    rtlsim.run(tb_display, {"case": "protocol"})


def test_buttons_debounce(tb_display):
    rtlsim.run(tb_display, {"case": "debounce"})


def test_nexys4ddr_system(tb_display, tmp_path):
    gx, gy = 64, 24
    cfg = {"rule": "hodgepodge", "nbh": 5, "mask": "moore", "boundary": "toroidal", "cell_w": 8,
           "params": {"G": 20, "K": 3}}
    rng = np.random.default_rng(5)
    seed = rng.choice([0, 0, 0, 1, 50, 128, 254, 255], size=(gy, gx)).astype(np.uint8)
    (tmp_path / "seed.hex").write_text("".join(f"{b:02x}\n" for b in seed.tobytes()))
    log = rtlsim.run(tb_display, {"case": "system", "seed_hex": tmp_path / "seed.hex",
                                  "out_file": tmp_path / "frame.hex"}, timeout_s=1800)
    gens = int(re.search(r"TB_GEN (\d+)", log).group(1))
    assert gens >= 3
    got = np.array([int(t, 16) for t in (tmp_path / "frame.hex").read_text().split()], np.uint8).reshape(gy, gx)
    exp = seed
    for _ in range(gens):
        exp = step(exp, cfg)
    assert np.array_equal(got, exp), f"frame after {gens} generations differs from the model"
