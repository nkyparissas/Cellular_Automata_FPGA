"""Lenia rule datapath (ca_rule_lenia inside ca_engine, sim/tb/tb_lenia.sv)
against the golden model (design spec 2026-10-31, Section 9.3)."""
import json
import random
import shutil
import subprocess
from collections import Counter
from pathlib import Path

import cocotb
import numpy as np
import pytest
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from ca_model import lenia
from rtl_runner import run_cocotb

ROOT = Path(__file__).resolve().parents[2]
YOSYS = shutil.which("yosys")
HAS_SLANG = bool(YOSYS) and (Path(YOSYS).resolve().parents[1] / "share" / "yosys" / "plugins" / "slang.so").exists()


class Dut:
    """Parameters of the instantiated tb_lenia and the state the model needs."""

    def __init__(self, dut):
        self.dut = dut
        self.n, self.cw = int(dut.N.value), int(dut.CELL_W.value)
        self.ww, self.lb = int(dut.WEIGHT_W.value), int(dut.LUT_IDX_W.value)
        self.c = lenia.num_classes(self.n)
        self.chain = [0] * self.c
        self.banks = [np.zeros(1 << self.lb, dtype=np.int64), np.zeros(1 << self.lb, dtype=np.int64)]
        self.maxq = (1 << self.cw) - 1
        self.cyc = 0              # clock cycles since the reset release
        self.presented = []       # cycles with kern_valid_i high
        self.done = []            # cycles with kern_done_o high

    def natural_sh(self):
        wsum = int((np.array(self.chain) * lenia.class_counts(self.n)).sum())
        return max(0, (max(wsum, 1) * self.maxq).bit_length() - self.lb)


async def start(dut):
    dut.vld_i.value = 0
    dut.kern_valid_i.value = 0
    dut.gt_we_i.value = 0
    dut.sel_i.value = 0
    dut.rst_ni.value = 0
    Clock(dut.clk_i, 10, unit="ns").start()
    Clock(dut.gt_clk_i, 7, unit="ns").start()
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    d, got = Dut(dut), []

    async def collect():
        while True:
            await RisingEdge(dut.clk_i)
            await Timer(1, unit="ns")
            d.cyc += 1
            if int(dut.vld_o.value):
                got.append(int(dut.cell_o.value))
            if int(dut.kern_valid_i.value) and int(dut.rst_ni.value):
                d.presented.append(d.cyc)
            if int(dut.kern_done_o.value):
                d.done.append(d.cyc)

    cocotb.start_soon(collect())
    await RisingEdge(dut.clk_i)      # inputs driven from here on are seen by collect()
    return d, got


async def present(d, words, gap=lambda: 0):
    """Drive one word per kern_valid_i cycle, with gap() idle cycles after each;
    the model chain shifts once per word."""
    await RisingEdge(d.dut.clk_i)    # align with clk_i (write_table returns on gt_clk_i)
    for w in words:
        d.dut.kern_data_i.value = int(w)
        d.dut.kern_valid_i.value = 1
        await RisingEdge(d.dut.clk_i)
        d.chain = d.chain[1:] + [int(w)]
        d.dut.kern_valid_i.value = 0
        for _ in range(gap()):
            await RisingEdge(d.dut.clk_i)
    d.dut.kern_valid_i.value = 0


async def load_kernel(d, words, gap=lambda: 0):
    """Shift words into the chain (class 0 first) and wait until the last shift has
    reached class 0: exactly one kern_done_o pulse per word (the controller's
    KERNEL_PENDING count), and none after them."""
    first = len(d.done)
    await present(d, words, gap)
    for _ in range(d.c + 4):
        await RisingEdge(d.dut.clk_i)
    assert len(d.done) - first == len(words), f"{len(d.done) - first} kern_done_o pulses for {len(words)} words"


async def write_table(d, bank, table):
    mask = (1 << (d.cw + 1)) - 1
    for i, e in enumerate(table):
        d.dut.gt_addr_i.value = (bank << d.lb) | i
        d.dut.gt_data_i.value = int(e) & mask
        d.dut.gt_we_i.value = 1
        await RisingEdge(d.dut.gt_clk_i)
    d.dut.gt_we_i.value = 0
    await RisingEdge(d.dut.gt_clk_i)
    d.banks[bank] = np.asarray(table, dtype=np.int64)


def random_cell(d, rng, high=False):
    if high:
        return d.maxq
    return rng.choice([0, 0, d.maxq, rng.randint(0, d.maxq), rng.randint(0, d.maxq)])


async def check_windows(d, rng, bank, sh, cycles, got, high=False):
    """Stream random columns with selection (bank, sh) and compare every output with the model."""
    n = d.n
    d.dut.sel_i.value = (bank << 6) | sh
    await RisingEdge(d.dut.clk_i)
    first, hist, expected = len(got), [], []
    w = np.array(d.chain)
    for t in range(cycles + n):
        col = [random_cell(d, rng, high) for _ in range(n)]
        hist.append(col)
        d.dut.col_i.value = sum(c << (i * d.cw) for i, c in enumerate(col))
        vld = n - 1 <= t < cycles and rng.random() < 0.8
        d.dut.vld_i.value = int(vld)
        if vld:
            win = np.array([[hist[t - (n - 1 - j)][i] for j in range(n)] for i in range(n)])
            expected.append(lenia.cell_from_window(win, w, d.banks[bank], sh, d.cw))
        await RisingEdge(d.dut.clk_i)
    d.dut.vld_i.value = 0
    for _ in range(120):
        await RisingEdge(d.dut.clk_i)
    out = got[first:]
    assert len(out) == len(expected), f"{len(out)} outputs for {len(expected)} valid inputs"
    bad = [k for k, (a, b) in enumerate(zip(out, expected)) if a != b]
    assert not bad, f"first mismatch at output {bad[0]}: rtl {out[bad[0]]} model {expected[bad[0]]} (bank {bank}, sh {sh})"


def random_kernel(d, rng):
    w = [rng.randint(0, (1 << d.ww) - 1) for _ in range(d.c)]
    w[rng.randrange(d.c)] = 0
    w[rng.randrange(d.c)] = (1 << d.ww) - 1
    return w


def random_table(d, rng):
    return [rng.randint(-(1 << d.cw), (1 << d.cw) - 1) for _ in range(1 << d.lb)]


@cocotb.test()
async def cocotb_lenia_random_windows(dut):
    rng = random.Random(int(cocotb.plusargs.get("seed", "1")))
    cycles = int(cocotb.plusargs.get("cycles", "300"))
    d, got = await start(dut)
    await load_kernel(d, random_kernel(d, rng))
    await write_table(d, 0, random_table(d, rng))
    await write_table(d, 1, random_table(d, rng))
    nat = d.natural_sh()
    for bank, sh in ((0, nat), (1, max(0, nat - 2)), (rng.randint(0, 1), nat + 1)):
        await check_windows(d, rng, bank, sh, cycles, got)


@cocotb.test()
async def cocotb_lenia_powerup_defaults(dut):
    """No loads: the chain holds KERNEL_DEFAULT and both banks the GROWTH_INIT file."""
    rng = random.Random(5)
    d, got = await start(dut)
    kd = int(dut.KERNEL_DEFAULT.value)
    d.chain = [(kd >> (c * d.ww)) & ((1 << d.ww) - 1) for c in range(d.c)]
    words = [int(t, 16) for t in open(cocotb.plusargs["init_file"]).read().split()]
    ew = d.cw + 1
    signed = [v - (1 << ew) if v >> (ew - 1) else v for v in words]
    half = 1 << d.lb
    d.banks = [np.array(signed[:half]), np.array(signed[half:])]
    nat = d.natural_sh()
    await check_windows(d, rng, 0, nat, 150, got)
    await check_windows(d, rng, 1, nat, 150, got)


@cocotb.test()
async def cocotb_lenia_edges(dut):
    rng = random.Random(int(cocotb.plusargs.get("seed", "3")))
    d, got = await start(dut)
    await write_table(d, 0, random_table(d, rng))
    await write_table(d, 1, random_table(d, rng))
    # All-maximum weights and cells, SH = 0: the index saturates at 2^LB - 1.
    await load_kernel(d, [(1 << d.ww) - 1] * d.c)
    await check_windows(d, rng, 0, 0, 60, got, high=True)
    # SH = 63: the index is always 0.
    await check_windows(d, rng, 1, 63, 60, got)
    # All-zero weights.
    await load_kernel(d, [0] * d.c)
    await check_windows(d, rng, 0, 0, 60, got)
    # C + 1 words: the first one shifts out of class 0; banks selected alternately.
    words = random_kernel(d, rng)
    await load_kernel(d, [(1 << d.ww) - 1] + words)
    assert d.chain == words
    nat = d.natural_sh()
    await check_windows(d, rng, 1, nat, 80, got)
    await check_windows(d, rng, 0, nat, 80, got)


@cocotb.test()
async def cocotb_lenia_chain_ripple(dut):
    """A word's shift travels down the chain and reaches class 0 (kern_done_o) C
    cycles after the word was presented, for words in consecutive cycles and with
    gaps between them; the chain then holds the last C words."""
    rng = random.Random(int(cocotb.plusargs.get("seed", "9")))
    d, got = await start(dut)
    await write_table(d, 0, random_table(d, rng))
    await load_kernel(d, random_kernel(d, rng))
    assert [b - a for a, b in zip(d.presented, d.done)] == [d.c] * d.c
    await check_windows(d, rng, 0, d.natural_sh(), 80, got)
    # C + 3 words with gaps of 0 to 3 cycles: the first three shift out of class 0.
    p0, d0 = len(d.presented), len(d.done)
    words = [rng.randint(0, (1 << d.ww) - 1) for _ in range(d.c + 3)]
    await load_kernel(d, words, gap=lambda: rng.randint(0, 3))
    assert [b - a for a, b in zip(d.presented[p0:], d.done[d0:])] == [d.c] * len(words)
    assert d.chain == words[3:]
    await check_windows(d, rng, 0, d.natural_sh(), 80, got)


@cocotb.test()
async def cocotb_lenia_reset_during_load(dut):
    """A one-cycle reset while shifts are in flight: the shifts complete without
    kern_done_o pulses (the controller's count restarts at the reset), and the
    words presented from the first cycle after the reset are counted and loaded."""
    rng = random.Random(int(cocotb.plusargs.get("seed", "4")))
    d, got = await start(dut)
    await write_table(d, 1, random_table(d, rng))
    await present(d, random_kernel(d, rng)[:5])
    d0 = len(d.done)
    dut.rst_ni.value = 0
    await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    await load_kernel(d, random_kernel(d, rng))
    assert len(d.done) - d0 == d.c, f"{len(d.done) - d0} kern_done_o pulses after the reset for {d.c} new words"
    await check_windows(d, rng, 1, d.natural_sh(), 80, got)


# ---------------------------------------------------------------- pytest ---
CASES = [(5, 8), (5, 16), (7, 16), (9, 8), (9, 16)]


@pytest.mark.parametrize("n,cw", CASES, ids=[f"n{n}-c{c}" for n, c in CASES])
def test_lenia_random_windows(n, cw):
    run_cocotb("tb_lenia", "test_rule_lenia", {"N": n, "CELL_W": cw}, testcase="cocotb_lenia_random_windows",
               plusargs=[f"+seed={n * 10 + cw}"])


def test_lenia_full_size_n27():
    run_cocotb("tb_lenia", "test_rule_lenia", {"N": 27, "CELL_W": 16}, testcase="cocotb_lenia_random_windows",
               plusargs=["+cycles=150", "+seed=27"])


def test_lenia_powerup_defaults(tmp_path):
    n, cw, ww, lb = 7, 16, 6, 12
    rng = np.random.default_rng(7)
    c = lenia.num_classes(n)
    kernel = rng.integers(0, 1 << ww, size=c)
    literal = f"{c * ww}'h{sum(int(w) << (k * ww) for k, w in enumerate(kernel)):x}"
    entries = rng.integers(-(1 << cw), 1 << cw, size=2 << lb)
    init = tmp_path / "growth_init.hex"
    init.write_text("".join(f"{int(e) & ((1 << (cw + 1)) - 1):05x}\n" for e in entries))
    run_cocotb("tb_lenia", "test_rule_lenia", {"N": n, "CELL_W": cw, "WEIGHT_W": ww, "LUT_IDX_W": lb,
                                          "KERNEL_DEFAULT": literal, "GROWTH_INIT": f'"{init}"'},
               testcase="cocotb_lenia_powerup_defaults", plusargs=[f"+init_file={init}"])


@pytest.mark.parametrize("cw", [8, 16])
def test_lenia_edges(cw):
    run_cocotb("tb_lenia", "test_rule_lenia", {"N": 5, "CELL_W": cw}, testcase="cocotb_lenia_edges",
               plusargs=[f"+seed={cw}"])


@pytest.mark.parametrize("n", [7, 27])
def test_lenia_chain_ripple(n):
    run_cocotb("tb_lenia", "test_rule_lenia", {"N": n, "CELL_W": 16}, testcase="cocotb_lenia_chain_ripple",
               plusargs=[f"+seed={n}"])


@pytest.mark.parametrize("n", [7, 27])
def test_lenia_reset_during_load(n):
    run_cocotb("tb_lenia", "test_rule_lenia", {"N": n, "CELL_W": 16}, testcase="cocotb_lenia_reset_during_load",
               plusargs=[f"+seed={n + 1}"])


@pytest.mark.skipif(not HAS_SLANG, reason="yosys-slang not available")
def test_lenia_clock_enables_are_local(tmp_path):
    """After synthesis for the 7-series, no net drives the clock enables of more than
    one class (its weight register and the hand-off copy, 2 x WEIGHT_W flip-flops):
    an enable shared along the weight chain cost 5 ns of routing at 37 x 37."""
    import gen_filelist
    n, ww = 9, 6
    files = gen_filelist.sources_for("tb_lenia", extra_dirs=("sim/tb",))
    net = tmp_path / "tb_lenia.json"
    cmd = (f"read_slang -G N={n} -G WEIGHT_W={ww} --top tb_lenia " + " ".join(map(str, files))
           + f"; synth_xilinx -flatten -top tb_lenia; write_json {net}")
    r = subprocess.run([YOSYS, "-q", "-m", "slang", "-p", cmd], capture_output=True, text=True, timeout=900)
    assert r.returncode == 0, (r.stdout + r.stderr)[-3000:]
    cells = json.loads(net.read_text())["modules"]["tb_lenia"]["cells"].values()
    loads = Counter(c["connections"]["CE"][0] for c in cells
                    if c["type"] in ("FDRE", "FDSE", "FDCE", "FDPE", "SRL16E", "SRLC32E")
                    and isinstance(c["connections"]["CE"][0], int))
    assert loads, "no flip-flops with a clock enable found"
    assert max(loads.values()) <= 2 * ww, f"a clock-enable net drives {max(loads.values())} flip-flops"
