# Register map

The CA core exposes 32-bit registers on an AXI4-Lite slave (`rtl/ctrl/ca_regs.sv`). The low 16 address bits are decoded, so the map repeats every 64 KB (the size of the XDMA template's BAR); unmapped reads return 0 and every access responds OKAY. `rtl/ctrl/ca_regs_pkg.sv` is the source of truth, `host/ca_host/regs.py` mirrors it, and `tests/test_docs.py` checks this page against the package.

| Offset | Register | Access | Content |
|---|---|---|---|
| 0x00 | ID | RO | `0xCA5E0001` |
| 0x04 | CTRL | RW | bit 0 RUN, bit 1 PAUSE, bit 2 AUTO, bit 3 RESET_STATE (write 1; self-clearing, honoured only when no pass runs) |
| 0x08 | STATUS | RO | bit 0 BUSY (a pass runs or fast-forward passes remain), bit 1 FRONT (buffer holding the latest generation), bit 2 PENDING (a frame request is waiting); Lenia cores: bit 3 KERNEL_PENDING, bit 4 GROWTH_PENDING, bit 5 GROWTH_BANK (active table bank) |
| 0x0C | FRAME_REQ | WO | any write requests one pass ("ready for a new buffer") |
| 0x10 | FRAME_REPEAT | RW | [15:0] a generation is committed every FRAME_REPEAT+1 requested passes |
| 0x14 | GENS_PER_FRAME | RW | [15:0] generations committed per committing request (0 behaves as 1) |
| 0x18 | GEN_COUNT | RO | committed generations since reset or RESET_STATE |
| 0x1C | PASS_COUNT | RO | passes since reset or RESET_STATE |
| 0x20 | BUF0_LO | RW | frame buffer 0 address, bits 31:0 |
| 0x24 | BUF0_HI | RW | frame buffer 0 address, bits 63:32 |
| 0x28 | BUF1_LO | RW | frame buffer 1 address, bits 31:0 |
| 0x2C | BUF1_HI | RW | frame buffer 1 address, bits 63:32 |
| 0x30 | GRID_DIM | RO | [15:0] GRID_X, [31:16] GRID_Y |
| 0x34 | CORE_CFG | RO | [7:0] CELL_W, [15:8] NBH, [17:16] boundary mode, [23:20] rule, [31:24] DATA_W/8 |
| 0x40 | RULE_PARAM0 | RW | rule parameter 0; parameters 1 to 7 follow at 0x44 to 0x5C |
| 0x60 | LENIA_CFG | RO | Lenia cores: [7:0] distance classes C, [11:8] WEIGHT_W, [15:12] LUT_IDX_W, [20:16] table entry width (CELL_W + 1) |
| 0x64 | KERNEL_DATA | WO | Lenia cores: [WEIGHT_W-1:0] next class weight, class 0 first; accepted only while RUN is clear and no pass is busy |
| 0x68 | GROWTH_SHIFT | RW | Lenia cores: [5:0] shift SH of the inactive table bank |
| 0x6C | GROWTH_COMMIT | WO | Lenia cores: any write requests a bank swap |
| 0x70 | GROWTH_GEN | RO | Lenia cores: GEN_COUNT when the last swap took effect |
| 0x8000 | GROWTH_TABLE | WO | Lenia cores: entry idx of the inactive bank at 0x8000 + 4 idx, [CELL_W:0] two's complement; indices of 2^LUT_IDX_W and above are ignored |

In cores built for another rule, the offsets 0x60 to 0x70 and the table window read 0 and ignore writes, and STATUS bits 3 to 5 read 0.

## Semantics

All settings are sampled when a pass starts, so writes during a pass take effect at the next one. A pass reads the front buffer, streams it to the consumer (requested passes only), computes the next generation and, when committing, writes it to the other buffer and swaps FRONT once every write response has returned. The controller (`rtl/ctrl/ca_controller.sv`) is the single owner of that decision.

| Rule | RULE_PARAM0 | RULE_PARAM1 | RULE_PARAM2 | RULE_PARAM3 | RULE_PARAM4 |
|---|---|---|---|---|---|
| hodgepodge (0) | G | K | | | |
| ghm (1) | T | STATES | E | | |
| interval (2) | LO1 | HI1 | LO2 | HI2 | ALIVE |

Lenia cores (rule 3) do not use the RULE_PARAM registers; their kernel and growth function are configured as described below.

## Loading a seed

Clear RUN (and AUTO), poll `STATUS` until BUSY is clear (a pass in flight still reads and writes the buffers, and RESET_STATE is ignored while it runs), write `CTRL.RESET_STATE`, check that FRONT and GEN_COUNT read 0, then write the seed to `BUF0` (and `BUF1` in the legacy cylindrical and rectangular modes). `CAController.load_grid()` implements this.

## Host-paced cores (XDMA)

1. Load the seed as above, through the H2C channel.
2. Write `CTRL = RUN`.
3. Write `FRAME_REQ`, poll `STATUS` until BUSY and PENDING are clear, read `STATUS.FRONT`, read the frame from that buffer through the C2H channel. Repeat.

`CAController.request_frame()`, `wait_frame()` and `read_frame()` implement step 3.

## Consumer-paced cores (display boards)

The display requests a pass every frame, so with RUN set passes run back to back and `STATUS` never reads idle; `wait_frame()` must not be used. The host loads the seed, sets RUN and steers the run (FRAME_REPEAT, PAUSE, rule parameters). To read the current generation it sets PAUSE (passes keep running and streaming but no longer commit), waits until BUSY is clear or PASS_COUNT has advanced (the pass running when PAUSE was set has ended), reads `GEN_COUNT`, `STATUS.FRONT` and that buffer, and restores PAUSE. `CAController.snapshot()` implements this, and `python3 -m ca_host.cli --transport uart` uses it for its `s` command.

## Lenia: kernel and growth function

A Lenia core computes, for every cell, `S = sum over distance classes c of w[c] * (sum of the cells of class c)`, reads the active growth-table bank at `min(S >> SH, 2^LUT_IDX_W - 1)` and adds the entry to the cell with saturation (design spec `docs/superpowers/specs/2026-10-31-lenia-rule-design.md`, Section 5). `model/ca_model/lenia.py` computes the weights and tables, and `CAController.load_kernel()` and `set_growth()` implement the procedures below. RESET_STATE leaves the kernel and the tables unchanged; at power-up both hold the configuration's defaults, so the default creature runs after a seed upload alone.

**Kernel (once per simulation).** Clear RUN, wait until BUSY is clear, write the C class weights to `KERNEL_DATA` in class order (class 0 first) and poll `STATUS` until KERNEL_PENDING is clear. The weights shift into a chain of registers next to the class multipliers; words written while RUN is set or a pass is busy are ignored, and no pass starts while KERNEL_PENDING is set. Because the table folds in the kernel normalisation, write a new growth table after every kernel change.

**Growth function (live).** Wait until GROWTH_PENDING is clear, write `GROWTH_SHIFT` and the `2^LUT_IDX_W` entries of `GROWTH_TABLE` (they go to the inactive bank), then write `GROWTH_COMMIT`. The banks swap in the first cycle in which no pass is running, so a pass never mixes two tables and a commit never delays a pass; GROWTH_PENDING then clears and `GROWTH_GEN` holds the generation count at the swap. Generations up to GROWTH_GEN were computed with the previous table and every later one with the new table, which is the schedule a replay in the model uses. Table and shift writes are ignored while a commit is pending, and a second commit while one is pending is ignored.
