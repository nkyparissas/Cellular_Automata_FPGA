"""Asymmetric simple-dual-port RAM and cell packer."""
import random

import cocotb
import pytest
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from rtl_runner import run_cocotb


@cocotb.test()
async def cocotb_ram_mapping(dut):
    Clock(dut.wclk_i, 4, unit="ns").start()
    Clock(dut.rclk_i, 6, unit="ns").start()
    wr_w, rd_w, depth = int(dut.WR_W.value), int(dut.RD_W.value), int(dut.RD_DEPTH.value)
    ratio = wr_w // rd_w
    words = [random.getrandbits(wr_w) for _ in range(depth // ratio)]
    dut.we_i.value = 0
    for a, w in enumerate(words):
        await RisingEdge(dut.wclk_i)
        dut.we_i.value = 1
        dut.waddr_i.value = a
        dut.wdata_i.value = w
    await RisingEdge(dut.wclk_i)
    dut.we_i.value = 0
    for k in range(depth):
        await RisingEdge(dut.rclk_i)
        dut.raddr_i.value = k
        await RisingEdge(dut.rclk_i)          # registered read: data one cycle later
        await Timer(1, unit="ns")
        exp = (words[k // ratio] >> ((k % ratio) * rd_w)) & ((1 << rd_w) - 1)
        assert int(dut.rdata_o.value) == exp, f"narrow index {k}"


@cocotb.test()
async def cocotb_packer_order(dut):
    Clock(dut.clk_i, 10, unit="ns").start()
    cw, dw = int(dut.CELL_W.value), int(dut.DATA_W.value)
    per = dw // cw
    dut.vld_i.value = 0
    dut.cell_i.value = 0
    dut.rst_ni.value = 0
    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    cells = [random.getrandbits(cw) for _ in range(per * 7)]
    got = []

    async def collect():
        while True:
            await RisingEdge(dut.clk_i)
            await Timer(1, unit="ns")
            if int(dut.word_vld_o.value):
                got.append(int(dut.word_o.value))

    cocotb.start_soon(collect())
    i = 0
    while i < len(cells):
        await RisingEdge(dut.clk_i)
        if random.random() < 0.7:
            dut.vld_i.value = 1
            dut.cell_i.value = cells[i]
            i += 1
        else:
            dut.vld_i.value = 0
    await RisingEdge(dut.clk_i)
    dut.vld_i.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_i)
    exp = [sum(c << (k * cw) for k, c in enumerate(cells[w * per:(w + 1) * per])) for w in range(7)]
    assert got == exp


@pytest.mark.parametrize("rd_w", [4, 8])
def test_ram_mapping(rd_w):
    run_cocotb("ca_ram_sdp_asym", "test_ram_packer", {"WR_W": 128, "RD_W": rd_w, "RD_DEPTH": 64},
               testcase="cocotb_ram_mapping")


@pytest.mark.parametrize("cell_w,data_w", [(4, 64), (8, 64), (4, 128), (8, 128)])
def test_packer_order(cell_w, data_w):
    run_cocotb("ca_cell_packer", "test_ram_packer", {"CELL_W": cell_w, "DATA_W": data_w},
               testcase="cocotb_packer_order")
