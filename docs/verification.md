# Verification record

## Golden-model experiments (Task 5)

Command: `PYTHONPATH=model python3 -m ca_model.run --config configs/<name>.json --gens 1000 --png-every 250`; outputs in `build/exp/<name>/` (not committed). Timings were measured with all six runs in parallel.

| Experiment | Seed | Setting | ms/gen | User verdict (2026-10-24) |
|---|---|---|---|---|
| hodgepodge29 | hodgepodge29_seed.bmp, white = 251 | N=29 Moore, G=105, K=5, toroidal | 1436 | looks right |
| hodgepodge19 | see below | N=19 Moore, G=60, K=3, toroidal | 426 (single run) | first version rejected; grid_custom re-run looks right (2026-10-25) |
| ghm_circle_toroidal | ghm_spirals.bmp (indices) | N=29 circle, T=5, STATES=15, E=1 | 957 | looks right |
| ghm_vn_toroidal | ghm_spirals.bmp (indices) | N=29 von Neumann, T=5, STATES=15, E=1 | 956 | looks right |
| ghm_moore_cylindrical | ghm_spirals.bmp (indices) | N=29 Moore, legacy cylindrical | 930 | looks right |
| ap_toroidal | ap_random.bmp, white = 1 | N=21 legacy AP mask (row, column), interval 20..23 / 59..100 | 1573 | looks right |

Hodgepodge 19x19: the first run started from `seed.bmp` (G=48) and did not self-organise, which the legacy `READ ME.txt` also records ("We are yet to find an initial seed that leads to auto-organization. grid_custom works for G = 47 ... 60, G = 60 converges"). The legacy 19x19 result was produced from `grid_custom.txt`, so the configuration now starts from `data/seeds/hodgepodge19_grid_custom.png` (a lossless copy of that text grid) with G=60, K=3; it forms spirals like the legacy result and was run to 2000 generations; the user confirmed this run on 2026-10-25.

## RTL experiments at full size (Task 16)

Command: `python3 tools/run_rtl_experiment.py --config configs/<name>.json --gens <n> --dump-every <k>`; the core testbench (`sim/tb/tb_core.sv`) runs the 1920x1080 grid with a behavioural AXI memory and compares every dumped generation with the golden model. Outputs in `build/rtl_exp/<name>/`.

| Experiment | Build | s/gen (Verilator, 1 thread, machine shared) | Generations 1-3 |
|---|---|---|---|
| hodgepodge29 | 29 s | 20.1 | MATCH |
| hodgepodge19 | 19 s | 12.5 | MATCH |
| ghm_circle_toroidal | 57 s | 20.1 | MATCH |
| ghm_vn_toroidal | 33 s | 11.5 | MATCH |
| ghm_moore_cylindrical | 36 s | 11.1 | MATCH |
| ap_toroidal | 18 s | 7.5 | MATCH |

Long RTL runs (snapshots every 250 generations compared with the model's snapshots at the same generations). They were stopped after about four hours at the user's request; RTL runs are now limited to 200 generations (`tools/run_rtl_experiment.py` refuses more without `--allow-long`), and longer horizons use the golden model.

| Experiment | Gen 250 | Gen 500 | Gen 750 |
|---|---|---|---|
| hodgepodge29 | MATCH | not reached | not reached |
| hodgepodge19 | MATCH | MATCH | not reached |
| ghm_circle_toroidal | MATCH | MATCH | not reached |
| ghm_vn_toroidal | MATCH | MATCH | not reached |
| ghm_moore_cylindrical | MATCH | MATCH | not reached |
| ap_toroidal | MATCH | MATCH | MATCH |

## Legacy VHDL (Tasks 22 and 23)

The legacy toroidal buffer with the Hodgepodge n29, GHM and Artificial Physics engines reproduces the golden model exactly on random 64x64 toroidal grids (GHDL; two simulation artefacts of the legacy code patched in a build copy, see `docs/legacy_vhdl_findings.md` #13 and #14). Findings 1, 2 and 3 were reproduced with directed testbenches.

## Lenia (2026-10-31)

Design spec `docs/superpowers/specs/2026-10-31-lenia-rule-design.md`, implementation plan `docs/superpowers/plans/2026-10-31-lenia-rule.md`.

* **Golden model** (`tests/model/test_lenia.py`): the FFT sum equals the per-cell reference in all four boundary modes for N = 5, 7, 9, 8- and 16-bit cells and 4- and 8-bit weights; a generation equals the per-window reference for SH = 0, 3 and 40, including saturation; the distance-class counts (69, 78 and 121 classes for N = 27, 29, 37) and the creatures' quantised kernels (Orbium 64 non-zero classes over 496 cells, Hydrogeminium 106 over 904) are pinned. A 1920x1080 generation takes about 0.2 s.
* **Precision** (`tests/model/test_lenia_precision.py`, 500 steps against the floating-point update of the Lenia tutorial, 16-bit cells, 6-bit weights, 12-bit table index): Orbium (128 x 128) mean mass error 0.23 %, speed ratio 1.0014, size ratio 1.0004; Hydrogeminium (192 x 192) mean mass error 0.53 %, speed ratio 0.990, size ratio 0.998. The thresholds are 3 % for mass, 2 % (Orbium) and 3 % (Hydrogeminium) for speed and size.
* **RTL unit tests** (`tests/unit/test_rule_lenia.py`, `tests/unit/test_lenia_ctrl.py`): the datapath equals the model on random windows for N = 5, 7, 9 and 27, with random kernels and tables in both banks, power-up defaults, SH and saturation edges and the chain order; each word's shift reaches class 0 exactly C cycles after the word, for words in consecutive cycles and with gaps, and a reset with shifts in flight produces no stray done pulses while the words presented from the first cycle after it are counted; after synthesis for the 7-series (yosys `synth_xilinx`), no net drives the clock enables of more than one class. The configuration controller accepts kernel words only when idle, holds passes until the last word's shift has reached class 0 (also with a full FIFO and C words in the chain behind a slower engine clock), writes only the inactive bank, ignores indices beyond the table and writes while a commit is pending, swaps when no pass runs (also with fast-forward passes queued) and keeps its configuration over a reset.
* **Core** (`tests/core/test_core_lenia.py`): every generation bit-exact with uploaded random kernels and tables (toroidal and zero edges), with the power-up kernel and table (Orbium on 128 x 128), with 8-bit cells, with memory stalls, with a growth commit while passes run (host-paced, consumer-paced and with fast-forward passes; the table schedule follows GROWTH_GEN), with the commit moved cycle by cycle across a pass start, with a kernel write during a pass (ignored) and with no pass starting while a kernel load is pending; an unsupported weight width fails at elaboration.
* **Registers** (`tests/sim/test_ctrl.py`): 16-bit decoding (0x0104 is unmapped, 0x10004 aliases CTRL) and, in a core built for another rule, the Lenia registers read 0, ignore writes and raise no strobe.
* **Static**: `make lint` (including the Lenia tops), `make lint-boards` for `hodgepodge29` and `lenia_orbium`, and slang elaboration of both board tops with both configurations are clean.
* **200 MHz**: unverified here; `boards/ooc_lenia/ooc_lenia.tcl` is the out-of-context Vivado run to do first.

Full-size regression after the Lenia work (`tools/run_rtl_experiment.py --gens 2 --dump-every 1 --threads 4`, 1920x1080):

| Configuration | s/gen (Verilator, 4 threads) | Generations 1-2 |
|---|---|---|
| hodgepodge29 | 9.6 | MATCH |
| hodgepodge19 | 7.7 | MATCH |
| ghm_circle_toroidal | 8.8 | MATCH |
| ghm_vn_toroidal | 10.5 | MATCH |
| ghm_moore_cylindrical | 9.1 | MATCH |
| ap_toroidal | 8.2 | MATCH |
| lenia_orbium | 9.3 | MATCH |
| lenia_hydrogeminium | 11.0 | MATCH |
