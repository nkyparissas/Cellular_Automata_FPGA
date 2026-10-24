"""Pipelined adder tree and restoring divider."""
import math
import random

import cocotb
import pytest
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from rtl_runner import run_cocotb


def tree_lat(n):
    return 0 if n <= 1 else math.ceil(math.log2(n))


@cocotb.test()
async def cocotb_adder_tree(dut):
    Clock(dut.clk_i, 10, unit="ns").start()
    n, w = int(dut.N_IN.value), int(dut.IN_W.value)
    lat = tree_lat(n)
    sums = []
    for k in range(40):
        vals = [random.getrandbits(w) for _ in range(n)]
        if k == 3:
            vals = [(1 << w) - 1] * n          # all-ones corner case
        dut.in_i.value = sum(v << (i * w) for i, v in enumerate(vals))
        sums.append(sum(vals))
        await RisingEdge(dut.clk_i)
        await Timer(1, unit="ns")
        if lat == 0:
            assert int(dut.sum_o.value) == sums[k]
        elif k >= lat - 1:
            assert int(dut.sum_o.value) == sums[k - lat + 1], f"cycle {k}"


@cocotb.test()
async def cocotb_div_pipe(dut):
    Clock(dut.clk_i, 10, unit="ns").start()
    nw, dw = int(dut.NUM_W.value), int(dut.DEN_W.value)
    edges = [(0, 5), (123, 1), (777, 0), ((1 << nw) - 1, 1), ((1 << nw) - 1, (1 << dw) - 1), (214455, 842)]
    pairs = edges + [(random.getrandbits(nw), random.getrandbits(dw)) for _ in range(200)]
    exp = [((n // d) if d else (1 << nw) - 1) & ((1 << nw) - 1) for n, d in pairs]
    for k, (n, d) in enumerate(pairs + [(0, 1)] * nw):
        dut.num_i.value = n
        dut.den_i.value = d
        await RisingEdge(dut.clk_i)
        await Timer(1, unit="ns")
        j = k - nw + 1
        if 0 <= j < len(pairs):
            assert int(dut.quo_o.value) == exp[j], f"{pairs[j]}"


@pytest.mark.parametrize("n_in", [1, 2, 9, 441, 841])
def test_adder_tree(n_in):
    run_cocotb("ca_adder_tree", "test_arith",
               {"N_IN": n_in, "IN_W": 8, "OUT_W": 8 + max(1, tree_lat(n_in))},
               testcase="cocotb_adder_tree")


def test_div_pipe():
    run_cocotb("ca_div_pipe", "test_arith", {"NUM_W": 18, "DEN_W": 10}, testcase="cocotb_div_pipe")
