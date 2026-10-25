"""Sliding window + rule plug-ins against the golden model's window function."""
import os
import random

import cocotb
import numpy as np
import pytest
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from ca_model.rules import cell_from_window
from rtl_runner import run_cocotb

RULES = {0: "hodgepodge", 1: "ghm", 2: "interval"}


def random_params(rule, cell_w, nbh, rng):
    maxv = (1 << cell_w) - 1
    if rule == "hodgepodge":
        return [rng.randint(0, 120), rng.choice([0, 1, 2, 3, 5, 7, 200]), 0, 0, 0, 0, 0, 0]
    if rule == "ghm":
        return [rng.randint(0, 6), rng.randint(2, maxv + 1), rng.randint(1, 3), 0, 0, 0, 0, 0]
    lo1 = rng.randint(0, nbh * nbh // 3)
    lo2 = rng.randint(lo1, nbh * nbh)
    return [lo1, lo1 + rng.randint(0, 4), lo2, lo2 + rng.randint(0, 20), rng.randint(1, maxv), 0, 0, 0]


def random_cell(rule, cell_w, rng):
    maxv = (1 << cell_w) - 1
    if rule == "hodgepodge":
        return rng.choice([0, 0, 1, maxv, maxv - 1, rng.randint(0, maxv)])
    if rule == "ghm":
        return rng.choice([0, 0, 0, 1, 1, 2, rng.randint(0, maxv)])
    return rng.choice([0, 1, 1, rng.randint(0, maxv)])


def edge_params(rule, nbh):
    """Degenerate and boundary parameter sets: zero divisors, empty or
    unreachable thresholds, values wider than a cell."""
    nn = nbh * nbh
    if rule == "hodgepodge":   # [G, K]: K = 0 saturates, K = 1, K > A, G = 0, G > MAX
        return [[60, 0, 0, 0, 0, 0, 0, 0], [60, 1, 0, 0, 0, 0, 0, 0], [5, nn + 7, 0, 0, 0, 0, 0, 0],
                [0, 3, 0, 0, 0, 0, 0, 0], [70000, 3, 0, 0, 0, 0, 0, 0]]
    if rule == "ghm":          # [T, STATES, E]: T = 0, STATES = 0 and 1, E = 0, T unreachable
        return [[0, 15, 1, 0, 0, 0, 0, 0], [3, 0, 1, 0, 0, 0, 0, 0], [3, 1, 1, 0, 0, 0, 0, 0],
                [1, 15, 0, 0, 0, 0, 0, 0], [nn + 1, 15, 1, 0, 0, 0, 0, 0]]
    # [LO1, HI1, LO2, HI2, ALIVE]: empty intervals, S = 0 only, ALIVE wider than a cell
    return [[5, 2, 9, 7, 1, 0, 0, 0], [0, 0, 0, 0, 3, 0, 0, 0], [0, 100000, 0, 0, 70000, 0, 0, 0]]


async def start_engine(dut):
    """Reset the engine and start collecting its outputs into the returned list."""
    dut.vld_i.value = 0
    dut.rst_ni.value = 0
    Clock(dut.clk_i, 10, unit="ns").start()
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    got = []

    async def collect():
        while True:
            await RisingEdge(dut.clk_i)
            await Timer(1, unit="ns")
            if int(dut.vld_o.value):
                got.append(int(dut.cell_o.value))

    cocotb.start_soon(collect())
    return got


async def check_windows(dut, rng, rule, mask, params, cycles, got):
    """Stream random columns with ``params`` and compare every output with the model."""
    n, cw = int(dut.N.value), int(dut.CELL_W.value)
    dut.params_i.value = sum(p << (32 * k) for k, p in enumerate(params))
    first = len(got)
    hist, expected = [], []
    for t in range(cycles + n):
        col = [random_cell(rule, cw, rng) for _ in range(n)]
        hist.append(col)
        dut.col_i.value = sum(c << (i * cw) for i, c in enumerate(col))
        vld = t >= n - 1 and t < cycles and rng.random() < 0.8
        dut.vld_i.value = int(vld)
        if vld:
            win = np.array([[hist[t - (n - 1 - j)][i] for j in range(n)] for i in range(n)])
            expected.append(cell_from_window(rule, win, mask, params, cw))
        await RisingEdge(dut.clk_i)
    dut.vld_i.value = 0
    for _ in range(200):
        await RisingEdge(dut.clk_i)
    out = got[first:]
    assert len(out) == len(expected), f"{len(out)} outputs for {len(expected)} valid inputs"
    bad = [k for k, (a, b) in enumerate(zip(out, expected)) if a != b]
    assert not bad, f"first mismatch at output {bad[0]}: rtl {out[bad[0]]} model {expected[bad[0]]} params {params}"


def dut_rule_and_mask(dut):
    n = int(dut.N.value)
    mask_int = int(dut.MASK.value)
    mask = np.array([[(mask_int >> (i * n + j)) & 1 for j in range(n)] for i in range(n)], dtype=bool)
    return RULES[int(dut.RULE_ID.value)], mask


@cocotb.test()
async def cocotb_rule_random_windows(dut):
    rng = random.Random(int(cocotb.plusargs.get("seed", "1")))
    rule, mask = dut_rule_and_mask(dut)
    params = random_params(rule, int(dut.CELL_W.value), int(dut.N.value), rng)
    got = await start_engine(dut)
    await check_windows(dut, rng, rule, mask, params, int(cocotb.plusargs.get("cycles", "300")), got)


@cocotb.test()
async def cocotb_rule_edge_params(dut):
    rng = random.Random(int(cocotb.plusargs.get("seed", "1")))
    rule, mask = dut_rule_and_mask(dut)
    got = await start_engine(dut)
    for params in edge_params(rule, int(dut.N.value)):
        await check_windows(dut, rng, rule, mask, params, 120, got)


def mask_literal(n, seed):
    rng = random.Random(seed)
    bits = [rng.random() < 0.6 for _ in range(n * n)]
    bits[(n // 2) * n + n // 2] = True
    v = sum(1 << k for k, b in enumerate(bits) if b)
    return f"{n * n}'h{v:x}"


CASES = [(rule_id, n, cw) for rule_id in (0, 1, 2) for n in (3, 5, 9) for cw in (4, 8)]


@pytest.mark.parametrize("rule_id,n,cw", CASES, ids=[f"{RULES[r]}-n{n}-c{c}" for r, n, c in CASES])
def test_rule_random_windows(rule_id, n, cw):
    run_cocotb("tb_engine", "test_engine",
               {"N": n, "CELL_W": cw, "RULE_ID": rule_id, "MASK": mask_literal(n, 100 * n + cw + rule_id)},
               testcase="cocotb_rule_random_windows", plusargs=[f"+seed={n * 10 + cw}"])


# Hodgepodge with a small A count (N <= 11 at 8 bits, every practical N at 16 bits)
# exercises the K = 0 saturation; the other rules get their degenerate thresholds.
EDGE_CASES = [(0, 3, 8), (0, 5, 8), (0, 9, 8), (0, 5, 16), (1, 5, 4), (2, 5, 8)]


@pytest.mark.parametrize("rule_id,n,cw", EDGE_CASES, ids=[f"{RULES[r]}-n{n}-c{c}" for r, n, c in EDGE_CASES])
def test_rule_edge_params(rule_id, n, cw):
    run_cocotb("tb_engine", "test_engine",
               {"N": n, "CELL_W": cw, "RULE_ID": rule_id, "MASK": mask_literal(n, 100 * n + cw + rule_id)},
               testcase="cocotb_rule_edge_params", plusargs=[f"+seed={n * 10 + cw + 7}"])


def test_engine_full_size_hodgepodge29():
    full = f"{29 * 29}'h{(1 << 29 * 29) - 1:x}"
    run_cocotb("tb_engine", "test_engine", {"N": 29, "CELL_W": 8, "RULE_ID": 0, "MASK": full},
               testcase="cocotb_rule_random_windows", plusargs=["+cycles=120", "+seed=29"])
