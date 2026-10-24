# Register map

The CA core exposes 32-bit registers on an AXI4-Lite slave (`rtl/ctrl/ca_regs.sv`). Only the low 8 address bits are decoded, so the map repeats every 256 bytes; unmapped reads return 0 and every access responds OKAY. `rtl/ctrl/ca_regs_pkg.sv` is the source of truth, `host/ca_host/regs.py` mirrors it, and `tests/test_docs.py` checks this page against the package.

| Offset | Register | Access | Content |
|---|---|---|---|
| 0x00 | ID | RO | `0xCA5E0001` |
| 0x04 | CTRL | RW | bit 0 RUN, bit 1 PAUSE, bit 2 AUTO, bit 3 RESET_STATE (write 1; self-clearing, honoured only when no pass runs) |
| 0x08 | STATUS | RO | bit 0 BUSY (a pass runs or fast-forward passes remain), bit 1 FRONT (buffer holding the latest generation), bit 2 PENDING (a frame request is waiting) |
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

## Semantics

All settings are sampled when a pass starts, so writes during a pass take effect at the next one. A pass reads the front buffer, streams it to the consumer (requested passes only), computes the next generation and, when committing, writes it to the other buffer and swaps FRONT once every write response has returned. The controller (`rtl/ctrl/ca_controller.sv`) is the single owner of that decision.

| Rule | RULE_PARAM0 | RULE_PARAM1 | RULE_PARAM2 | RULE_PARAM3 | RULE_PARAM4 |
|---|---|---|---|---|---|
| hodgepodge (0) | G | K | | | |
| ghm (1) | T | STATES | E | | |
| interval (2) | LO1 | HI1 | LO2 | HI2 | ALIVE |

## Typical host sequence (XDMA)

1. Write the seed to `BUF0` (and `BUF1` in the legacy cylindrical and rectangular modes) through the H2C channel.
2. Write `CTRL = RUN`.
3. Write `FRAME_REQ`, poll `STATUS` until BUSY and PENDING are clear, read `STATUS.FRONT`, read the frame from that buffer through the C2H channel. Repeat.

`host/ca_host/controller.py` implements this sequence for every transport.
