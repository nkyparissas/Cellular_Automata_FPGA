# Generic PCIe/XDMA template

A starting point for any Xilinx board with a PCIe edge connector and on-board DDR. The host reads and writes the board DDR through the XDMA DMA channels (memory-mapped mode) and controls the core through the XDMA AXI-Lite BAR; the core's consumer handshake is the `FRAME_REQ` register.

**Status: unverified template.** It was written without Vivado and without a target board. `ca_core_xdma.sv` lints against the project RTL (`make lint-boards`); `bd_ca_xdma.tcl` has not been run.

## Files

* `ca_core_xdma.sv` - block-design module reference: `ca_core_flat` with the configuration from `ca_cfg.svh`, the frame stream always accepted, `pass_done` exported for an XDMA user interrupt.
* `bd_ca_xdma.tcl` - creates the project and block design: XDMA (AXI-MM, 1 H2C + 1 C2H channel, 64 KB AXI-Lite BAR), a DDR4 controller (via board automation), two SmartConnects, a clocking wizard for the engine clock, and the core.

## Adapting

1. Edit the variables at the top of `bd_ca_xdma.tcl`: `part`, `board_part` (with board files, PCIe and DDR pins come from board automation), `pcie_lanes`, `pcie_gen`, `ddr_interface`, `eclk_mhz`, `config`, `data_w`, `buf1_addr`.
2. Boards with DDR3 or an MIG instead of the DDR4 IP: replace the `ddr4_0` cell and the `c0_ddr4_ui_clk` connection.
3. Without board files: add the PCIe reference-clock buffer (`util_ds_buf`), `sys_rst_n`, and the board XDC.
4. Run `vivado -mode batch -source boards/xdma_template/bd_ca_xdma.tcl`, then synthesise the generated `ca_xdma_bd_wrapper`.

## Host side

Install Xilinx `dma_ip_drivers` (XDMA Linux driver). The driver exposes `/dev/xdma0_user` (AXI-Lite BAR, registers), `/dev/xdma0_h2c_0` and `/dev/xdma0_c2h_0` (DMA; the file offset is the DDR address). `python3 -m ca_host.cli --transport xdma --config <json>` uses these with the default buffer addresses 0x0 and 0x1000_0000 (see `host/`).
