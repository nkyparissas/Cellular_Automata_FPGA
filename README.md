# Large-Neighbourhood Cellular Automata on FPGAs (SystemVerilog)

A portable SystemVerilog framework for simulating cellular automata with large neighbourhoods (for example 29 x 29) on Xilinx FPGAs, one new cell per clock cycle regardless of the neighbourhood size. It is a re-implementation of the architecture published in the papers listed in `NOTICE`: a dual-clock grid-lines buffer streams one neighbourhood column per cycle into an N x N sliding window followed by a rule plug-in. The new design adds AXI4 memory access, an AXI4-Lite register file, an AXI4-Stream frame output with a generic "ready for a new buffer" consumer handshake, rule plug-ins, a bit-exact golden model, a Verilator-based verification flow, board templates and a Python host library.

## Status

| Part | State |
|---|---|
| Core RTL (`rtl/`) | complete; lint clean (Verilator `-Wall`); bit-exact against the golden model in unit, subsystem and integration tests, and at full 1920x1080 size for the six legacy experiments (see `docs/verification.md`) |
| Rules | Hodgepodge machine, Greenberg-Hastings, interval rule (Artificial Physics); masks: square, von Neumann, legacy circle, legacy Artificial Physics |
| Display variant (`boards/nexys4ddr/`) | system simulated; board top lints against IP stubs; Vivado flow unverified |
| PCIe variant (`boards/xdma_template/`) | generic template; module reference lints; block-design script unverified |
| Host software (`host/ca_host/`) | XDMA, UART and simulated transports, controller, viewer and CLI; tested against the simulated device and fake device nodes |
| Legacy VHDL | reviewed and co-simulated in GHDL; findings in `docs/legacy_vhdl_findings.md` |

## Quick start

Requirements: Verilator 5, Python 3.11 with numpy, pillow, pyserial, cocotb 2 and pytest; GHDL for the legacy tests (they are skipped without the legacy repository).

```
make lint                                     # Verilator -Wall on every RTL top
python3 -m pytest -q                          # all tests (about 25 minutes)
PYTHONPATH=model python3 -m ca_model.run --config configs/hodgepodge29.json --gens 1000 --png-every 250
python3 tools/run_rtl_experiment.py --config configs/hodgepodge29.json --gens 3 --dump-every 1
PYTHONPATH=host:model python3 -m ca_host.cli --transport sim --config configs/ghm_circle_toroidal.json --frames 5 --headless
```

## Repository layout

| Path | Content |
|---|---|
| `rtl/` | portable RTL: `pkg`, `common` (CDC, RAM, FIFO), `arith`, `engine`, `rules`, `mem`, `ctrl`, `top`, `consumers`, `io`; `rtl/files.f` lists packages and search paths |
| `third_party/` | pulp-platform `axi` and `common_cells`, vendored at pinned versions |
| `model/ca_model/` | golden model: seeds and palettes, masks, boundary-aware window sums, rules, experiment runner |
| `sim/` | SystemVerilog testbenches (`sim/tb/`) and verification models (`sim/models/`: AXI memory, stream sink, AXI4-Lite driver) |
| `tests/` | `model`, `unit` (cocotb), `sim`, `core`, `host`, `legacy` and static checks |
| `tools/` | configuration header generator, file-list generator, Verilator runner, full-size RTL experiment runner |
| `configs/`, `data/seeds/` | experiment configurations and their seed images |
| `boards/` | `nexys4ddr` (display, UART, buttons) and `xdma_template` (PCIe) |
| `host/ca_host/` | host library and command-line viewer |
| `docs/` | `docs/architecture.md`, `docs/register_map.md`, `docs/adding_a_rule.md`, `docs/verification.md`, `docs/legacy_vhdl_findings.md`, the design spec and the implementation plan |

## Licence and attribution

Apache License 2.0 (`LICENSE`). Redistributions and derivative works must keep `NOTICE`, which credits Nikolaos Kyparissas and lists the publications to cite; `CITATION.cff` provides the preferred citation. Vendored code keeps its own licence (Solderpad Hardware License 0.51).
