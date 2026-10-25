# Large-Neighbourhood Cellular Automata on FPGAs (SystemVerilog)

A portable SystemVerilog framework for simulating cellular automata with large neighbourhoods (for example 29 x 29) on Xilinx FPGAs, one new cell per clock cycle regardless of the neighbourhood size. It is a re-implementation of the architecture published in the papers listed in `NOTICE`: a dual-clock grid-lines buffer streams one neighbourhood column per cycle into an N x N sliding window followed by a rule plug-in. The new design adds AXI4 memory access, an AXI4-Lite register file, an AXI4-Stream frame output with a generic "ready for a new buffer" consumer handshake, rule plug-ins, a bit-exact golden model, a Verilator-based verification flow, board templates and a Python host library.

## Status

| Part | State |
|---|---|
| Core RTL (`rtl/`) | complete; lint clean (Verilator `-Wall`); bit-exact against the golden model in unit, subsystem and integration tests, and at full 1920x1080 size for the six legacy experiments (see `docs/verification.md`) |
| Rules | Hodgepodge machine, Greenberg-Hastings, interval rule (Artificial Physics); masks: square, von Neumann, legacy circle, legacy Artificial Physics |
| Display variant (`boards/nexys4ddr/`) | system simulated; board top lints against IP stubs; Vivado flow unverified |
| PCIe variant (`boards/xdma_template/`) | generic template; the Verilog module reference lints and elaborates under slang; block-design script unverified |
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

## Instructions

These steps take a cellular automaton from its description and an initial grid to a running FPGA, upload the grid, run it and read frames back. The first part is common to every target; the two parts after it cover the board with a display (Digilent Nexys 4 DDR) and a PCIe card (XDMA). Commands run from the repository root. Note that the Vivado flows have not been run yet (see Status), so the build steps may need adjustments for your Vivado version.

### Common steps

**1. Describe the automaton.** A JSON file in `configs/` defines it; the six configurations of the legacy experiments serve as templates, and `docs/adding_a_rule.md` explains how to add a new rule.

| Key | Meaning | Values |
|---|---|---|
| `name` | label of the output folders | any string |
| `grid` | `[GRID_X, GRID_Y]` in cells | `[1920, 1080]` on the display board; `GRID_X * cell_w` must be a multiple of the memory data width (128 bits on the Nexys 4 DDR, 512 bits in the XDMA template) |
| `cell_w` | bits per cell | 4 or 8 for the legacy display palettes; 1, 2, 4, 8, 16 or 32 in the core |
| `nbh` | neighbourhood size N (an N x N window) | odd, at least 3 |
| `boundary` | treatment of the grid edges | `toroidal`, `zero`, or the legacy `cylindrical` and `rectangular` modes |
| `rule` | rule plug-in | `hodgepodge`, `ghm` (Greenberg-Hastings), `interval` (Artificial Physics) |
| `mask` | neighbours that take part in the rule | `moore`, `von_neumann`, `circle29`, `ap21` |
| `params` | rule parameters | `hodgepodge`: `G`, `K`; `ghm`: `T`, `STATES`, `E`; `interval`: `LO1`, `HI1`, `LO2`, `HI2`, `ALIVE` (see `docs/register_map.md`) |
| `seed`, `seed_mode`, `seed_value` | initial grid image and the conversion of its pixels into cell states | see step 2 |
| `palette` | colours of the PNG files written on the host | `gray`, `legacy4_windows`, `legacy4_gradient`, `legacy8` |

**2. Prepare the initial grid.** The initial state is an image of exactly GRID_X x GRID_Y pixels, drawn in any image editor and stored as BMP or PNG. The host software converts it directly, so the MATLAB script and text file of the original flow are no longer needed. `seed_mode` selects the conversion:

| `seed_mode` | Image | Cell state |
|---|---|---|
| `index` | indexed (palette) image | the palette index of each pixel, so a 16-colour bitmap (for example from Microsoft Paint) maps directly onto 4-bit cells |
| `binary` | indexed image | `seed_value` for every non-zero pixel (for example 251 for Hodgepodge, 1 for Artificial Physics), 0 otherwise |
| `raw` | greyscale or indexed image | the pixel value itself (8-bit cells) |
| `gray8` | indexed image | the grey-level mapping of the legacy `bmp2ascii.m` script |

**3. Preview the evolution with the golden model.** The model is bit-exact with the hardware, so its snapshots show what the FPGA will produce:

```
PYTHONPATH=model python3 -m ca_model.run --config configs/my_ca.json --gens 1000 --png-every 100
```

The PNG and NumPy snapshots (`gen_00000.png`, `gen_00100.png`, ...) land in `build/exp/<name>/`.

**4. Optionally, simulate the RTL.** `python3 tools/run_rtl_experiment.py --config configs/my_ca.json --gens 3 --dump-every 1` runs the core at full size in Verilator and compares every dumped generation with the model. A full-HD generation takes 7 to 20 s of simulation, so the tool refuses more than 200 generations unless `--allow-long` is given.

**5. Know what the bitstream fixes.** The grid size, cell width, neighbourhood, mask, boundary mode and rule are compiled into the bitstream, so changing any of them requires a new build. The initial grid, the rule parameters, the speed and PAUSE are run-time settings, which the host changes through the register file (`docs/register_map.md`).

**6. Drive the core from the host.** Every target is driven by `host/ca_host` (`PYTHONPATH=host:model`; on Windows `set PYTHONPATH=host;model`). `python3 -m ca_host.cli --help` lists the options of the command-line tool, and `--transport sim` runs the same host flow on the golden model, which allows trying the host side without hardware. Scripts use the same library; the setup is identical on every target, and only the device and the way frames are read back differ (see the two sections below):

```python
from ca_model import config
from ca_model.grids import load_seed
from ca_host.controller import CAController

cfg = config.load("configs/hodgepodge29.json")
ctl = CAController(dev, cfg)        # dev: UartDevice or XdmaDevice, see below
ctl.load_grid(load_seed(cfg["seed"], cfg["seed_mode"], cfg.get("seed_value")))  # stops, resets, uploads
ctl.set_params(cfg["params"])       # may also change while running; applies from the next pass
ctl.set_frame_repeat(0)             # one generation per pass; n: one generation every n+1 passes
ctl.start()
```

### Board with a display (Digilent Nexys 4 DDR)

On this board the display requests a new pass for every frame it shows (1080p at 60 Hz), so the automaton advances in real time on its own; the host uploads the grid, steers the run and reads frames back.

1. **Build** the bitstream for a configuration (the grid must be 1920x1080):
   ```
   vivado -mode batch -source boards/nexys4ddr/build.tcl -tclargs configs/hodgepodge29.json
   ```
   The bitstream, `ca_nexys4ddr.bit`, is written to the `build` folder (subfolder `nexys4ddr`).
2. **Program** the FPGA with the Vivado Hardware Manager and connect a monitor to the VGA port. LED 0 lights once the DDR2 memory is calibrated; the screen stays black until a run starts.
3. **Upload the grid and run:**
   ```
   PYTHONPATH=host:model python3 -m ca_host.cli --transport uart --port /dev/ttyUSB1 --config configs/hodgepodge29.json
   ```
   The board's USB-UART appears as the second of its two serial ports on Linux (`/dev/ttyUSB1`) and as a COM port on Windows (`--port COM5`). At 2 Mbaud the upload of a 1920x1080 grid takes about 10 s for 8-bit cells and 5 s for 4-bit cells. The run then starts at 60 generations per second; `--frame-repeat 59` starts at one generation per second instead, and `--seed my_grid.bmp` replaces the configuration's seed.
4. **Control** the run from the terminal by typing a command and Enter: `+` faster, `-` slower, `p` pause or resume, `s` snapshot, `q` quit and leave the board running, `x` stop and quit. The push buttons act on the same settings at any time: up runs at 60 generations per second, down at one generation per second, left pauses or resumes.
5. **Read a frame back** with `s`: the host sets PAUSE (the display keeps showing the current generation), waits for the running pass to finish, reads the frame (about 10 s for 8-bit cells), saves it as `frame_00001.png`, `frame_00002.png`, ... in the folder `frames` (or shows it in a window when OpenCV is installed; `--headless --out <dir>` forces PNG files in `<dir>`) and resumes. In a script, `gen, frame = ctl.snapshot()` returns the generation count and the grid as a NumPy array of cell states, with `dev = UartDevice(port="/dev/ttyUSB1")` from `ca_host.uart`. Do not use `wait_frame()` on this board: the display keeps the core busy, so it would time out.
6. **LEDs:** 0 DDR2 calibrated, 1 memory clock locked, 2 toggles on every pass, 3 display underflow.

### PCIe card (XDMA)

On a PCIe card the host requests every pass through the `FRAME_REQ` register and reads each new generation from the card's DDR by DMA, so the host loop sets the pace; `GENS_PER_FRAME` computes several generations per request when the intermediate ones are not needed.

1. **Adapt and build** the template: edit the variables at the top of `boards/xdma_template/bd_ca_xdma.tcl` (device, board, PCIe lanes and speed, DDR interface, engine clock, configuration file, memory data width), run
   ```
   vivado -mode batch -source boards/xdma_template/bd_ca_xdma.tcl
   ```
   add the board constraints, then synthesise, implement and write the bitstream of `ca_xdma_bd_wrapper`. `boards/xdma_template/README.md` lists the details.
2. **Program** the card, reboot or rescan the PCIe bus, and load the XDMA Linux driver from Xilinx's `dma_ip_drivers` repository. The driver creates `/dev/xdma0_user` (registers) and `/dev/xdma0_h2c_0`, `/dev/xdma0_c2h_0` (DMA, where the file offset is the DDR address); the user running the host needs read and write access to them.
3. **Upload the grid and run:**
   ```
   PYTHONPATH=host:model python3 -m ca_host.cli --transport xdma --device /dev/xdma0 --config configs/hodgepodge29.json
   ```
   The tool uploads the grid by DMA and then, frame after frame, requests a pass, waits for it and reads the new generation back. In the window, `+` and `-` change the speed (FRAME_REPEAT), `f` cycles GENS_PER_FRAME through 1, 2, 4 and 8, space pauses or resumes, `s` saves the frame as a PNG and `q` quits (and stops the core).
4. **Read frames back** without a window: `--headless --out <dir> --frames N` saves N consecutive frames as `<dir>/frame_00001.png`, ... and stops. In a script, with `dev = XdmaDevice(prefix="/dev/xdma0")` from `ca_host.xdma`:
   ```python
   ctl.request_frame()          # one pass (one generation with FRAME_REPEAT = 0)
   gen = ctl.wait_frame()       # wait until it is done; returns the generation count
   frame = ctl.read_frame()     # NumPy array of cell states, read by DMA
   ```
