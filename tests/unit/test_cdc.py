"""Package functions, delay line and clock-domain-crossing primitives."""
import random

import cocotb
import pytest
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

from rtl_runner import run_cocotb


# ---------------------------------------------------------------- cocotb ---
async def reset2(dut, clks_rsts, cycles=5):
    for _, rst in clks_rsts:
        rst.value = 0
    await Timer(50, unit="ns")
    for clk, rst in clks_rsts:
        await RisingEdge(clk)
        rst.value = 1
    await Timer(20, unit="ns")


@cocotb.test()
async def cocotb_gray_xfer_monotonic(dut):
    sp, dp = int(cocotb.plusargs.get("src_ns", "3")), int(cocotb.plusargs.get("dst_ns", "7"))
    Clock(dut.src_clk_i, sp, unit="ns").start()
    Clock(dut.dst_clk_i, dp, unit="ns").start()
    dut.src_bin_i.value = 0
    await reset2(dut, [(dut.src_clk_i, dut.src_rst_ni), (dut.dst_clk_i, dut.dst_rst_ni)])
    w = len(dut.src_bin_i)
    mod = 1 << w
    seen = [0]

    async def watch():
        prev = 0
        while True:
            await RisingEdge(dut.dst_clk_i)
            v = int(dut.dst_bin_o.value)
            assert (v - prev) % mod < mod // 2, f"destination went backwards {prev} -> {v}"
            prev = v
            seen[0] = v

    cocotb.start_soon(watch())
    val = 0
    for _ in range(600):
        await RisingEdge(dut.src_clk_i)
        if random.random() < 0.6:
            val = (val + 1) % mod
            dut.src_bin_i.value = val
    await ClockCycles(dut.dst_clk_i, 10)
    assert seen[0] == val


@cocotb.test()
async def cocotb_async_fifo_random(dut):
    wp, rp = int(cocotb.plusargs.get("w_ns", "3")), int(cocotb.plusargs.get("r_ns", "7"))
    Clock(dut.wclk_i, wp, unit="ns").start()
    Clock(dut.rclk_i, rp, unit="ns").start()
    dut.w_valid_i.value = 0
    dut.r_ready_i.value = 0
    dut.w_data_i.value = 0
    await reset2(dut, [(dut.wclk_i, dut.wrst_ni), (dut.rclk_i, dut.rrst_ni)])
    width = len(dut.w_data_i)
    n = 2000
    data = [random.getrandbits(width) for _ in range(n)]
    got = []

    async def writer():
        i = 0
        while i < n:
            want = random.random() < 0.7
            dut.w_valid_i.value = int(want)
            dut.w_data_i.value = data[i]
            await RisingEdge(dut.wclk_i)
            if want and int(dut.w_ready_o.value):
                i += 1
        dut.w_valid_i.value = 0

    async def reader():
        while len(got) < n:
            rdy = random.random() < 0.6
            dut.r_ready_i.value = int(rdy)
            await RisingEdge(dut.rclk_i)
            if rdy and int(dut.r_valid_o.value):
                got.append(int(dut.r_data_o.value))

    cocotb.start_soon(writer())
    await reader()
    assert got == data


@cocotb.test()
async def cocotb_delay(dut):
    Clock(dut.clk_i, 10, unit="ns").start()
    d = int(dut.D.value)
    hist = []
    for k in range(50):
        v = random.getrandbits(len(dut.d_i))
        dut.d_i.value = v
        hist.append(v)
        await RisingEdge(dut.clk_i)
        await Timer(1, unit="ns")
        if d == 0:
            assert int(dut.q_o.value) == v
        elif k >= d - 1:
            assert int(dut.q_o.value) == hist[k - d + 1]


@cocotb.test()
async def cocotb_pkg_functions(dut):
    await Timer(1, unit="ns")
    exp = {  # (grid_y=20, nbh=5): virt_rows, out_rows, out_row_first, hzero per boundary
        0: (24, 20, 0, 0), 1: (20, 16, 2, 0), 2: (20, 16, 2, 1), 3: (24, 20, 0, 1)}
    got = [(int(dut.virt_o.value) >> (16 * b)) & 0xFFFF for b in range(4)]
    assert got == [exp[b][0] for b in range(4)]
    got = [(int(dut.outr_o.value) >> (16 * b)) & 0xFFFF for b in range(4)]
    assert got == [exp[b][1] for b in range(4)]
    got = [(int(dut.first_o.value) >> (16 * b)) & 0xFFFF for b in range(4)]
    assert got == [exp[b][2] for b in range(4)]
    assert [(int(dut.hzero_o.value) >> b) & 1 for b in range(4)] == [exp[b][3] for b in range(4)]
    assert [(int(dut.tlat_o.value) >> (8 * k)) & 0xFF for k in range(5)] == [0, 1, 4, 9, 10]  # n=1,2,9,441,841


# ---------------------------------------------------------------- pytest ---
@pytest.mark.parametrize("src_ns,dst_ns", [(3, 7), (7, 3), (5, 5)])
def test_gray_xfer_monotonic(src_ns, dst_ns):
    run_cocotb("ca_gray_xfer", "test_cdc", {"W": 5}, testcase="cocotb_gray_xfer_monotonic",
               plusargs=[f"+src_ns={src_ns}", f"+dst_ns={dst_ns}"])


@pytest.mark.parametrize("w_ns,r_ns", [(5, 5), (3, 7), (7, 3)])
def test_async_fifo_random(w_ns, r_ns):
    run_cocotb("ca_async_fifo", "test_cdc", {"W": 37, "DEPTH": 16}, testcase="cocotb_async_fifo_random",
               plusargs=[f"+w_ns={w_ns}", f"+r_ns={r_ns}"])


@pytest.mark.parametrize("d", [0, 1, 5])
def test_delay(d):
    run_cocotb("ca_delay", "test_cdc", {"W": 9, "D": d}, testcase="cocotb_delay")


def test_pkg_functions():
    run_cocotb("tb_pkg_funcs", "test_cdc", testcase="cocotb_pkg_functions")
