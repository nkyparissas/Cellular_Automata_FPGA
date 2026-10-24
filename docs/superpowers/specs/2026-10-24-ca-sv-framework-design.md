# Large-Neighbourhood CA Framework in SystemVerilog: Design

Date: 2026-10-24. Branch: `sv_refactor` (orphan). Reference only: `../Cellular_Automata_FPGA` (legacy VHDL, read-only).

## 1. Goal and scope

This work re-implements the legacy VHDL cellular automaton (CA) framework as a modular, board-independent SystemVerilog design. The legacy parallelisation scheme is preserved: a grid-lines buffer streams one neighbourhood column per engine clock cycle into an N x N sliding window, and the rule logic computes one new cell per cycle from the complete window. Everything around that core changes. All external interfaces become AXI4 (memory), AXI4-Lite (control) and AXI4-Stream (frame output). A generic consumer handshake ("ready for a new buffer") drives the double-buffer swap, which allows either a display or a PCIe/XDMA host to pace the simulation. Rules become plug-ins, which prepares the framework for a fixed-point Lenia rule.

Out of scope for now: a specific PCIe board, running Vivado, Lenia itself, more than one cell per clock cycle (interfaces leave room for it).

## 2. Decisions taken with the user

| Topic | Decision |
|---|---|
| Repository | Completely new content on orphan branch `sv_refactor`; nothing copied from the legacy tree except input seed images, mask data and board pin assignments. |
| XDMA mode | Memory-mapped. The host reads and writes the FPGA board DDR through the XDMA C2H/H2C channels at the DDR addresses of the frame buffers; the doorbell is an AXI4-Lite register. |
| Orientation | Window element `win[i][j]` is grid row `y-r+i`, column `x-r+j` (post-2023 convention), for every rule including Artificial Physics. |
| Experiment check | Start from the seed image of each `sw` experiment, run 1000 generations, write a PNG; the user judges visually. No exact match to the legacy `result.txt`. |
| Boards | Generic XDMA template plus a Nexys 4 DDR display variant; board folders contain only board-specific content. |
| AXI library | pulp-platform/axi v0.39.11 with common_cells v1.39.0, vendored under `third_party/`. |
| Python | User-managed venv with numpy, pillow, pyserial, cocotb 2.1-dev, pytest. No other packages. |
| Git | Every commit needs explicit user approval. |

## 3. Architecture

```
            aclk domain (AXI clock)                                   eclk domain (engine clock)
 AXI4-Lite ──► ca_regs ──► ca_controller ──┬──────────────────────────────────────────┐
                                           │ start/commit/front                       │ rule params (CDC at pass start)
                     ┌─────────────────────┴───────┐                                  ▼
 AXI4 (one master)◄──┤ axi_rw_join (pulp)          │      ┌────────────────────┐   ┌──────────┐   ┌──────────┐
   to MIG / NoC      │  ▲ AR/R          ▲ AW/W/B   │      │  ca_line_buffer    │   │ca_window │   │ ca_rule_*│
                     │ ca_frame_reader  ca_frame_  │      │  N+1 row slots     │──►│ N x N    │──►│ (plug-in)│
                     │   │   │          writer     │      │  (dual-clock RAM)  │   │ shift reg│   └────┬─────┘
                     └───┼───┼────────────▲────────┘      │  drain sequencer   │   └──────────┘        │ cell, vld
                         │   └── rows ───►│ line buffer ─►└────────────────────┘                       ▼
 AXI4-Stream ◄───────────┘ (frame rows,   │ write port                                      ca_cell_packer
   consumer                 requested     │                                                        │ words
 frame_req ─► ca_controller passes only)  └──────────── ca_async_fifo (eclk → aclk) ◄──────────────┘
```

One "pass" reads the front buffer once. While doing so it (a) optionally forwards the frame rows to the consumer stream, (b) fills the line buffer, from which the engine computes the next generation, and (c) optionally writes that generation to the back buffer ("commit"). After a committing pass the controller swaps front and back. Passes are strictly sequential: a pass starts only after the previous pass has received all write responses.

## 4. Memory layout

A frame buffer holds `GRID_Y` rows of `ROW_BYTES = GRID_X*CELL_W/8` bytes, row-major, starting at `BUFb_ADDR` (b = 0, 1). Cell `x` of a row occupies bits `[x*CELL_W +: CELL_W]` of the row viewed as a little-endian bit vector; for 8-bit cells byte `x` is cell `x`, for 4-bit cells cell `2k` is the low nibble of byte `k`. Constraints checked at elaboration: `GRID_X*CELL_W % DATA_W == 0`, `DATA_W/CELL_W` is a power of two, `NBH` odd and `>= 3`, `GRID_X >= NBH`, `GRID_Y >= NBH`. Buffer addresses must be `DATA_W/8` aligned. Bursts are INCR, full width, at most `MAX_BURST` beats and never cross a 4 KB boundary.

## 5. Row sequence per pass and boundary modes

`r = (NBH-1)/2`. The reader produces a sequence of "virtual rows"; the line buffer is a FIFO over that sequence, and output row `o` is computed from virtual rows `o .. o+NBH-1`.

| Mode | Virtual rows (V) | Source of virtual row v | Forwarded to consumer | Output rows written | Horizontal edge |
|---|---|---|---|---|---|
| `BND_TOROIDAL` | `GRID_Y+2r` | DDR row `(v-r) mod GRID_Y` | `r <= v < GRID_Y+r` | all, row `o` → row `o` | wrap |
| `BND_CYLINDRICAL` (legacy) | `GRID_Y` | DDR row `v` | all | `GRID_Y-2r`, row `o` → row `o+r` | wrap |
| `BND_RECTANGULAR` (legacy) | `GRID_Y` | DDR row `v` | all | `GRID_Y-2r`, row `o` → row `o+r` | zeros |
| `BND_ZERO` (new) | `GRID_Y+2r` | zero row if `v<r` or `v>=GRID_Y+r`, else DDR row `v-r` | non-zero rows | all, row `o` → row `o` | zeros |

The legacy cylindrical and rectangular modes keep the first and last `r` rows frozen at their initial values; the loader must therefore write the initial grid into both buffers in those modes (the host library does this automatically).

Per output row the drain issues `GRID_X+2r` column reads at addresses `(k-r) mod GRID_X`, `k = 0 .. GRID_X+2r-1`. In zero-edge modes the column data is replaced by zeros for `k < r` and `k >= GRID_X+r`. The column entering at index `k` is tagged valid for `k >= 2r`, which marks exactly the windows centred on columns `0 .. GRID_X-1`.

**Deviation from the accepted default (needs confirmation).** The accepted default kept the legacy 2N-line structure (N+1 circular lines plus r top-halo and r bottom-halo lines). This design instead uses N+1 slots only and re-reads the r top rows at the end of a toroidal pass. The cost is r extra row reads per pass (1.3% of the read traffic at N=29, on top of the r bottom-halo rows already agreed). The gains are half the line-buffer BRAM, no special halo bookkeeping, and one uniform mechanism for all four boundary modes.

## 6. Line buffer and drain

`ca_line_buffer` contains N+1 simple-dual-port RAMs (write width `DATA_W` on `aclk`, read width `CELL_W` on `eclk`, read latency 1), one per slot. Virtual row v lives in slot `v mod (NBH+1)`. Window row `i` of output row `o` reads slot `(o+i) mod (NBH+1)` through a registered rotation multiplexer. Three free-running gray-coded counters cross the clock boundary: rows written (aclk → eclk), rows released (eclk → aclk) and rows popped by the writer (aclk → eclk). Counter width is `PW = $clog2(NBH+1)+2`.

* The reader may allocate a slot when `written_ptr - released_sync < NBH+1`.
* The drain may start output row `o` when `written_sync - released_ptr >= NBH` and `started_rows - popped_sync < FIFO_ROWS`.
* After the last column read of row `o` the drain increments `released_ptr`. After the last output row of a pass (`out_rows` rows) it releases the remaining `NBH-1` rows with single increments on consecutive cycles, which keeps every gray transition single-bit.

The eclk side is pass-agnostic: pass lengths are compile-time constants, so no per-pass information crosses to eclk except the rule parameters.

## 7. Clock domains and resets

`aclk` drives regs, controller, reader, writer, line-buffer write ports and the consumer stream. `eclk` drives the line-buffer read side, window, rule, packer and the FIFO write side. The two may be the same clock. Resets are active-low (`rst_ni`, pulp convention), asserted asynchronously and released synchronously per domain by `ca_reset_sync`. Rule parameters are captured in `aclk` at pass start and transferred with a toggle handshake; they are stable for the whole pass because passes do not overlap.

## 8. Flow control

The reader issues a row's AR bursts only after allocating a slot, so line-buffer writes never block. R beats of forwarded rows are accepted only when the consumer stream accepts them (`rready = tready` for forwarded rows), so consumer backpressure stalls the memory read without data loss. The drain starts a row only when the output FIFO can absorb a whole row, so the engine pipeline never needs to stall. The output FIFO depth is the next power of two at or above `FIFO_ROWS * GRID_X*CELL_W/DATA_W`. The legacy design relied on display pacing for all of this; an XDMA host provides no such pacing.

## 9. Controller semantics

* Request sources: a write to `FRAME_REQ`, a pulse on `frame_req_i` from the consumer, or `CTRL.AUTO` (always pending while `RUN`). Pending requests merge into one flag.
* When `RUN`, a request is pending and no pass is active, a *requested pass* starts with `fwd_en=1`. It commits when `!PAUSE && repeat_cnt >= FRAME_REPEAT`; `repeat_cnt` then resets, otherwise it increments (saturating) unless paused. This reproduces the legacy `SPEED_SETTING` behaviour: one generation every `FRAME_REPEAT+1` consumed frames.
* After a committing requested pass, `GENS_PER_FRAME-1` further passes run with `fwd_en=0` and `commit=1` (fast-forward); they stop early if `PAUSE` is set or `RUN` cleared.
* A pass ends when the reader is done and the writer has drained `out_rows` rows (and received all B responses when committing). On commit `FRONT` toggles and `GEN_COUNT` increments; `PASS_COUNT` increments for every pass; `pass_done_o` pulses.
* All registers are sampled at pass start; writes during a pass take effect at the next pass. A single controller owns the swap decision, which removes legacy finding 1.
* `CTRL.RESET_STATE` (self-clearing, honoured only when idle) clears `FRONT`, `GEN_COUNT`, `PASS_COUNT`, `repeat_cnt` and the pending flag.

## 10. Register map (AXI4-Lite, 32-bit, byte offsets)

| Offset | Name | Access | Content |
|---|---|---|---|
| 0x00 | ID | RO | `0xCA5E0001` |
| 0x04 | CTRL | RW | bit0 RUN, bit1 PAUSE, bit2 AUTO, bit3 RESET_STATE (write 1, self-clearing) |
| 0x08 | STATUS | RO | bit0 BUSY, bit1 FRONT, bit2 PENDING |
| 0x0C | FRAME_REQ | WO | any write requests one pass |
| 0x10 | FRAME_REPEAT | RW | [15:0], reset value parameter `FRAME_REPEAT_DEFAULT` |
| 0x14 | GENS_PER_FRAME | RW | [15:0], 0 is treated as 1, reset 1 |
| 0x18 | GEN_COUNT | RO | committed generations |
| 0x1C | PASS_COUNT | RO | passes |
| 0x20 / 0x24 | BUF0_ADDR lo / hi | RW | reset `BUF0_DEFAULT` |
| 0x28 / 0x2C | BUF1_ADDR lo / hi | RW | reset `BUF1_DEFAULT` |
| 0x30 | GRID_DIM | RO | [15:0] GRID_X, [31:16] GRID_Y |
| 0x34 | CORE_CFG | RO | [7:0] CELL_W, [15:8] NBH, [17:16] BOUNDARY, [23:20] RULE, [31:24] DATA_W/8 |
| 0x40 + 4k | RULE_PARAM[k], k = 0..7 | RW | reset `PARAM_DEFAULTS[k]` |

Unmapped reads return 0; all accesses respond OKAY. `rtl/ctrl/ca_regs_pkg.sv` is the single source of truth; `host/ca_host/regs.py` mirrors it and a test checks parity.

## 11. Rules (bit-exact semantics)

`MAX = 2^CELL_W - 1`, `c = win[r][r]`, `M[i][j]` the binary mask (`MASK` bit `i*NBH+j`). Divisions are unsigned floor divisions; a zero divisor yields `MAX`.

* **Hodgepodge** (`RULE_HODGEPODGE`, params `G`=0, `K`=1). `S = Σ M·win` (centre included when `M[r][r]=1`); `A = Σ_{(i,j)≠(r,r)} M·[win>0]`. `c=0`: `min(MAX, A/K)`; `c=MAX`: `0`; otherwise `min(MAX, S/(A+1) + G)`. Matches the legacy engine (where `MAX=255` and the mask is all ones).
* **Greenberg-Hastings** (`RULE_GHM`, params `T`=0, `STATES`=1, `E`=2). `X = Σ_{(i,j)≠(r,r)} M·[1 <= win <= E]`. `c>0`: `(c+1 >= STATES) ? 0 : c+1`; `c=0`: `X >= T ? 1 : 0`. The legacy engine wraps at `c+1 >= N-1` with `N=16`, so `STATES=15, E=1` reproduces it (legacy finding 6).
* **Interval** (`RULE_INTERVAL`, params `LO1`=0, `HI1`=1, `LO2`=2, `HI2`=3, `ALIVE`=4). `S = Σ M·win`; output `ALIVE` when `S ∈ [LO1,HI1] ∪ [LO2,HI2]`, else 0. Artificial Physics is `LO1=20, HI1=23, LO2=59, HI2=100, ALIVE=1` with the legacy 21x21 weight mask.

Each rule module pipelines its own valid bit and exposes no latency parameter to the framework, so rules may have any latency. Adding a rule means one SV module, one `rule_e` value, one `generate` case arm in `ca_engine`, and one Python function in `model/ca_model/rules.py`.

## 12. Masks

`model/ca_model/masks.py` provides `moore(n)`, `von_neumann(n)` (`|i-r|+|j-r| <= r`), `circle29()` and `ap21()`; the last two are literal copies of the legacy data (the commented-out list in the GHM engine and the weight matrix of the Artificial Physics engine, as written, in row-column order). `tools/gen_cfg.py` emits the mask as a `NBH*NBH`-bit SystemVerilog literal.

## 13. Consumers

* **Stream contract.** `m_axis` carries rows `0 .. GRID_Y-1` of the front buffer during requested passes only: `GRID_X*CELL_W/DATA_W` beats per row, `tlast` on the last beat of every row, `tuser` on the first beat of row 0. Consumers that do not need the data tie `tready` high.
* **Display** (`ca_video_out`). Async FIFO into the pixel clock, generic video timing, palette lookup (legacy 4-bit "windows" and "gradient", legacy 8-bit black-red-white, grey). It pulses `frame_req_o` once per video frame at a configurable line in vertical blanking; on underflow it outputs black and resynchronises on the next `tuser`.
* **XDMA (memory-mapped)**. The stream is unused. The host writes the seed via H2C, writes `FRAME_REQ`, polls `STATUS.BUSY` and `GEN_COUNT`, reads `STATUS.FRONT` and fetches the frame via C2H from `BUF[FRONT]`.

## 14. Board variants

* `boards/nexys4ddr`: MIG (DDR2, AXI4 slave) ← `axi_mux` ← {`ca_core`, `ca_uart_bridge`}; `axi_lite_mux` ← {`ca_uart_bridge`, `ca_buttons_axil`} → core registers; `ca_video_out` at 1920x1080@60 (148.5 MHz) to the 4-bit VGA DAC. Buttons: up sets `FRAME_REPEAT=0`, down sets `FRAME_REPEAT=59`, left toggles `PAUSE`. Seeds and frame dumps travel through the UART bridge (2 Mbaud, 8N1).
* `boards/xdma_template`: Vivado block-design Tcl with XDMA (AXI-MM, AXI4-Lite master BAR), SmartConnect, DDR controller from board automation, clock wizard for `eclk`, and `ca_core_flat` as an RTL module reference. Unverified until a board and a Vivado version are chosen.

UART bridge protocol (little-endian; addresses and lengths multiples of `DATA_W/8`): `0x10 addr[4] data[4]` register write → `0x10`; `0x11 addr[4]` register read → `0x11 data[4]`; `0x20 addr[4] len[4] bytes[len]` memory write → `0x20` after the last write response; `0x21 addr[4] len[4]` memory read → `0x21 bytes[len]`.

## 15. Host software (`host/ca_host`)

`Device` abstraction (`read_reg`, `write_reg`, `read_mem`, `write_mem`) with three transports: `XdmaDevice` (Linux dma_ip_drivers: `/dev/xdma0_user` mapped for registers, `pread`/`pwrite` on `/dev/xdma0_c2h_0` and `/dev/xdma0_h2c_0` with the DDR address as file offset), `UartDevice` (bridge protocol over pyserial) and `SimDevice` (in-process emulation on the golden model). `CAController` implements seed loading, start, frame request, wait, frame read, speed and parameter control. The viewer uses OpenCV when available and falls back to PNG snapshots.

## 16. Verification strategy

1. Golden model (`model/ca_model`, numpy, integer arithmetic) checked against a naive per-cell reference on random small grids for every mask and boundary mode.
2. RTL unit tests with cocotb + Verilator; rules are compared with the model's rule functions on random windows.
3. Subsystem SystemVerilog testbenches (Verilator `--timing`) with behavioural AXI memory, stream sink and AXI4-Lite BFM, randomised latency/backpressure and protocol assertions.
4. Core integration matrix (rules x boundary modes x NBH x CELL_W x DATA_W x clock ratios), bit-exact against the model over several generations.
5. Full-HD experiments: model 1000-generation PNGs for user review, RTL bit-exact for the first generations, long RTL runs in the background after measuring their cost.
6. Legacy VHDL in GHDL on small grids (behavioural models of the Xilinx IP) to tie the model to the legacy semantics, plus directed tests for the documented legacy findings.
7. Host library tests against `SimDevice` and file-backed fake XDMA device nodes.

## 17. Configuration files

`configs/<name>.json` drives the model, the RTL testbench generator and the board builds:

```json
{"name": "hodgepodge29", "grid": [1920, 1080], "cell_w": 8, "nbh": 29,
 "boundary": "toroidal", "rule": "hodgepodge", "mask": "moore",
 "params": {"G": 105, "K": 5}, "seed": "data/seeds/hodgepodge29_seed.bmp",
 "seed_mode": "binary", "seed_value": 251, "palette": "legacy8"}
```

`seed_mode` is `index` (raw palette index), `binary` (non-zero pixels become `seed_value`; reproduces the legacy text grids: 251 for Hodgepodge, 1 for Artificial Physics) or `gray8` (legacy `bmp2ascii.m` for 8-bit: sorted grey palette lookup times 255, rounded).

## 18. Repository layout

```
rtl/{pkg,common,arith,engine,rules,mem,ctrl,top,consumers,io}/   portable RTL, rtl/files.f, rtl/lint.vlt
third_party/{axi,common_cells}/                                  vendored, licences kept
sim/{models,tb}/                                                 SV models and testbenches
model/ca_model/                                                  golden model + CLI
host/ca_host/                                                    host library, transports, viewer
tools/                                                           gen_cfg.py, rtlsim.py, run_rtl_experiment.py
configs/  data/seeds/  tests/{model,unit,sim,core,host,legacy}/  docs/  boards/{nexys4ddr,xdma_template}/
```

## 19. Open items for the user

1. Accept the N+1-slot line buffer (Section 5) instead of the 2N-line structure.
2. GHM `STATES` semantics as defined in Section 11 (legacy look obtained with `STATES=15`).
3. Licence of the new repository (legacy: CC BY 4.0; vendored pulp code: Solderpad 0.51).
