# Architecture

This document summarises how the design is organised; the full rationale is in `docs/superpowers/specs/2026-10-24-ca-sv-framework-design.md`.

## Principle

The framework keeps the parallelisation of the original design: a grid-lines buffer delivers one neighbourhood column per engine clock cycle to an N x N sliding window, and the rule computes one new cell per cycle from the complete window, regardless of the neighbourhood size. Large neighbourhoods therefore cost logic, not throughput. Everything around this core is built from AXI interfaces so that the same core serves a display board and a PCIe host.

## Data path of one pass

```
 DDR (front buffer) --AXI4 AR/R--> ca_frame_reader --+--> AXI4-Stream to the consumer (requested passes)
                                                     |
                                                     +--> ca_line_buffer (NBH+1 row slots, aclk write / eclk read)
                                                              | one column per eclk cycle
                                                         ca_window (N x N) --> ca_rule_* --> ca_cell_packer
                                                                                                   |
 DDR (back buffer) <--AXI4 AW/W/B-- ca_frame_writer <-- ca_async_fifo (eclk -> aclk) <------------+
```

* `rtl/mem/ca_frame_reader.sv` turns the boundary mode into a sequence of virtual rows (wrapped, zero or memory rows), issues the read bursts (at most `MAX_BURST` beats, never across 4 KB) and writes each row into a line-buffer slot it has allocated first, so the line buffer is never overrun. Forwarded rows wait for the consumer's `tready`.
* `rtl/engine/ca_line_buffer.sv` holds NBH+1 rows in dual-clock RAMs (`rtl/common/ca_ram_sdp_asym.sv`). Its drain streams `GRID_X+2r` columns per output row, wrapping or zeroing the edges, and starts a row only when NBH rows are present and the output FIFO can absorb the whole row. Gray-coded counters carry rows written, released and popped across the clock boundary.
* `rtl/engine/ca_engine.sv` is the window plus the selected rule; each rule pipelines its own valid bit, so rules may have any latency.
* `rtl/mem/ca_frame_writer.sv` writes the output rows to the back buffer when the pass commits, or discards them otherwise.
* `rtl/top/ca_core.sv` joins the reader and writer onto one AXI4 master with pulp-platform `axi_rw_join`, and holds the register file, the controller and the parameter clock crossing. `rtl/top/ca_core_flat.sv` offers the same core with Xilinx-style flat ports.

## Boundary modes

| Mode | Rows read per pass | Rows written | Edges |
|---|---|---|---|
| toroidal | GRID_Y + 2r (the last r and first r rows are read again) | all | wrap |
| zero | GRID_Y + 2r (2r zero rows, no memory traffic) | all | zero |
| cylindrical (legacy) | GRID_Y | GRID_Y - 2r, the first and last r rows stay as loaded | wrap |
| rectangular (legacy) | GRID_Y | GRID_Y - 2r, the first and last r rows stay as loaded | zero |

## Control and consumers

The controller starts a pass when RUN is set and a frame request is pending, from the `FRAME_REQ` register (host doorbell) or the consumer's `frame_req` input. It commits one generation every `FRAME_REPEAT+1` requested passes and can run `GENS_PER_FRAME-1` extra passes without streaming (fast-forward). See `docs/register_map.md`.

* Display boards: `rtl/top/ca_display_system.sv` combines the core with `rtl/consumers/ca_video_out.sv` (async FIFO, video timing, palette, frame request in vertical blanking), the UART bridge (`rtl/io/ca_uart_bridge.sv`) and the buttons (`rtl/io/ca_buttons_axil.sv`) behind pulp `axi_mux` and `axi_lite_mux`. `boards/nexys4ddr/` adds only clocks, the DDR2 MIG and pins.
* PCIe hosts: `boards/xdma_template/` instantiates the core next to XDMA in memory-mapped mode; the host moves frames by DMA and requests passes through the register file.

## Clocks and resets

`aclk` runs the AXI side (registers, controller, reader, writer, line-buffer write port, consumer stream); `eclk` runs the engine. Resets are active low and synchronous; each domain synchronises the external reset with `rtl/common/ca_reset_sync.sv`, and only control and valid state is reset (data-path registers and delay lines are not). Rule parameters cross with a toggle handshake at pass start (`rtl/top/ca_params_cdc.sv`).

## Verification

* `model/ca_model/` is the bit-exact golden model (numpy), checked against a per-cell reference.
* `tests/unit/` (cocotb + Verilator) checks the building blocks and every rule against the model on random windows.
* `tests/sim/` and `tests/core/` (SystemVerilog testbenches in `sim/tb/`, models in `sim/models/`) check the reader, writer, line buffer, controller and the whole core, generation by generation, under random memory and consumer stalls.
* `tools/run_rtl_experiment.py` runs the full-size experiments of `configs/` on the RTL.
* `tests/legacy/` runs the original VHDL in GHDL to tie the model to the legacy semantics and to reproduce the findings in `docs/legacy_vhdl_findings.md`.

Results are recorded in `docs/verification.md`.
