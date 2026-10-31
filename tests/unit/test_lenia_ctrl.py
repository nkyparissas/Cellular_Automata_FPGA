"""Lenia configuration controller (rtl/ctrl/ca_lenia_ctrl.sv): kernel FIFO and
pending flag, inactive-bank table writes, commit and swap, reset behaviour
(design spec 2026-10-31, Sections 6.2 and 6.3; plan decisions 4 to 7)."""
import cocotb
import pytest
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from rtl_runner import run_cocotb

PARAMS = {"C": 7, "WEIGHT_W": 6, "LUT_IDX_W": 4, "CELL_W": 8, "SH_DEFAULT": 3}
STROBES = ("kern_wr_i", "gt_wr_i", "sh_wr_i", "commit_i")


async def start(dut):
    for s in STROBES + ("run_i", "busy_i", "active_i"):
        getattr(dut, s).value = 0
    dut.gt_idx_i.value = 0
    dut.wdata_i.value = 0
    dut.gen_count_i.value = 0
    dut.arst_ni.value = 0
    dut.erst_ni.value = 0
    await Timer(1, unit="ns")       # inputs settle before the first clock edge
    Clock(dut.aclk_i, 10, unit="ns").start()
    Clock(dut.eclk_i, 7, unit="ns").start()
    for _ in range(3):
        await RisingEdge(dut.aclk_i)
    dut.arst_ni.value = 1
    dut.erst_ni.value = 1
    await RisingEdge(dut.aclk_i)
    shifted = []

    async def collect():
        while True:
            await RisingEdge(dut.eclk_i)
            await Timer(1, unit="ns")
            if int(dut.kern_valid_o.value):
                shifted.append(int(dut.kern_data_o.value))

    cocotb.start_soon(collect())
    return shifted


async def pulse(dut, strobe, wdata=0, idx=0):
    """One-cycle register strobe with its data, as ca_regs drives it."""
    dut.wdata_i.value = wdata
    dut.gt_idx_i.value = idx
    getattr(dut, strobe).value = 1
    await RisingEdge(dut.aclk_i)
    getattr(dut, strobe).value = 0


async def cycles(dut, n):
    for _ in range(n):
        await RisingEdge(dut.aclk_i)


def sel(dut):
    v = int(dut.sel_o.value)
    return v >> 6, v & 0x3F


@cocotb.test()
async def cocotb_kernel_accept_and_pending(dut):
    shifted = await start(dut)
    words = [5, 63, 0, 17, 42, 1, 33]
    for w in words:
        await pulse(dut, "kern_wr_i", w)
    await Timer(1, unit="ns")
    assert int(dut.kern_pending_o.value) == 1 and int(dut.hold_o.value) == 1
    for _ in range(200):
        await RisingEdge(dut.aclk_i)
        await Timer(1, unit="ns")
        if not int(dut.kern_pending_o.value):
            break
        assert int(dut.hold_o.value) == 1
    assert not int(dut.kern_pending_o.value), "KERNEL_PENDING never cleared"
    assert shifted == words, f"pending cleared after {shifted}"
    assert int(dut.hold_o.value) == 0
    for flag in ("run_i", "busy_i"):
        getattr(dut, flag).value = 1
        await pulse(dut, "kern_wr_i", 9)
        await cycles(dut, 40)
        assert shifted == words and int(dut.kern_pending_o.value) == 0, f"word accepted with {flag} set"
        getattr(dut, flag).value = 0


@cocotb.test()
async def cocotb_growth_bank_and_commit(dut):
    await start(dut)
    holds = []

    async def watch_hold():
        while True:
            await RisingEdge(dut.aclk_i)
            holds.append(int(dut.hold_o.value))

    cocotb.start_soon(watch_hold())
    assert sel(dut) == (0, 3) and int(dut.sh_inactive_o.value) == 3
    # Table writes target the inactive bank; indices beyond the table are ignored.
    dut.wdata_i.value, dut.gt_idx_i.value, dut.gt_wr_i.value = 0x3AB, 5, 1
    await Timer(1, unit="ns")
    assert int(dut.gt_we_o.value) == 1 and int(dut.gt_addr_o.value) == (1 << 4) | 5
    assert int(dut.gt_data_o.value) == 0x1AB
    dut.gt_idx_i.value = 16
    await Timer(1, unit="ns")
    assert int(dut.gt_we_o.value) == 0
    await RisingEdge(dut.aclk_i)
    dut.gt_wr_i.value = 0
    await pulse(dut, "sh_wr_i", 9)
    await Timer(1, unit="ns")
    assert int(dut.sh_inactive_o.value) == 9 and sel(dut) == (0, 3)
    # Commit while idle: swap at once, GROWTH_GEN latched.
    dut.gen_count_i.value = 41
    await pulse(dut, "commit_i")
    await cycles(dut, 3)
    await Timer(1, unit="ns")
    assert sel(dut) == (1, 9) and int(dut.growth_gen_o.value) == 41 and int(dut.growth_pending_o.value) == 0
    assert int(dut.sh_inactive_o.value) == 3
    # Commit during a pass: wait; writes and a second commit are ignored while pending.
    dut.active_i.value, dut.gen_count_i.value = 1, 50
    await pulse(dut, "commit_i")
    await cycles(dut, 10)
    await Timer(1, unit="ns")
    assert int(dut.growth_pending_o.value) == 1 and sel(dut) == (1, 9)
    dut.wdata_i.value, dut.gt_idx_i.value, dut.gt_wr_i.value = 7, 2, 1
    await Timer(1, unit="ns")
    assert int(dut.gt_we_o.value) == 0
    await RisingEdge(dut.aclk_i)
    dut.gt_wr_i.value = 0
    await pulse(dut, "sh_wr_i", 21)
    await pulse(dut, "commit_i")
    await Timer(1, unit="ns")
    assert int(dut.sh_inactive_o.value) == 3
    dut.active_i.value = 0
    await cycles(dut, 3)
    await Timer(1, unit="ns")
    assert sel(dut) == (0, 3) and int(dut.growth_gen_o.value) == 50 and int(dut.growth_pending_o.value) == 0
    await cycles(dut, 10)
    assert sel(dut) == (0, 3), "a second commit while pending caused a second swap"
    # Fast-forward passes queued (BUSY high) but no pass running: the swap still happens.
    dut.busy_i.value, dut.gen_count_i.value = 1, 60
    await pulse(dut, "commit_i")
    await cycles(dut, 3)
    await Timer(1, unit="ns")
    assert sel(dut)[0] == 1 and int(dut.growth_gen_o.value) == 60 and int(dut.growth_pending_o.value) == 0
    assert not any(holds), "a growth commit raised hold_o"


@cocotb.test()
async def cocotb_reset_keeps_configuration(dut):
    await start(dut)
    await pulse(dut, "sh_wr_i", 12)
    dut.gen_count_i.value = 7
    await pulse(dut, "commit_i")
    await cycles(dut, 3)
    await pulse(dut, "sh_wr_i", 30)
    dut.active_i.value = 1
    await pulse(dut, "commit_i")
    await cycles(dut, 2)
    assert int(dut.growth_pending_o.value) == 1
    before = (sel(dut), int(dut.sh_inactive_o.value))
    assert before == ((1, 12), 30)
    dut.arst_ni.value = 0
    dut.erst_ni.value = 0
    await cycles(dut, 1)
    dut.active_i.value = 0              # the pass ends while the reset is held: no swap
    await cycles(dut, 3)
    dut.arst_ni.value = 1
    dut.erst_ni.value = 1
    await cycles(dut, 3)
    await Timer(1, unit="ns")
    assert int(dut.growth_pending_o.value) == 0 and int(dut.kern_pending_o.value) == 0
    assert int(dut.growth_gen_o.value) == 0
    assert (sel(dut), int(dut.sh_inactive_o.value)) == before


@pytest.mark.parametrize("case", ["cocotb_kernel_accept_and_pending", "cocotb_growth_bank_and_commit",
                                  "cocotb_reset_keeps_configuration"])
def test_lenia_ctrl(case):
    run_cocotb("ca_lenia_ctrl", "test_lenia_ctrl", PARAMS, testcase=case)
