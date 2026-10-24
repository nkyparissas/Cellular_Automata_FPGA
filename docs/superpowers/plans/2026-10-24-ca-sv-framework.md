# CA SystemVerilog Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-implement the legacy VHDL large-neighbourhood CA framework as a portable, AXI-based SystemVerilog design with a golden model, a Verilator verification flow, board templates and a Python host library.

**Architecture:** One pass reads the front frame buffer over AXI4, fills an (N+1)-slot dual-clock line buffer and optionally streams the frame to a consumer; a sliding N x N window feeds a plug-in rule at one cell per engine cycle; results are packed and written to the back buffer; a single controller decides commits and swaps. Details: the spec below.

**Tech Stack:** SystemVerilog (Vivado- and Verilator-compatible), pulp-platform/axi v0.39.11 + common_cells v1.39.0, Verilator 5.045, cocotb 2.1-dev, GHDL 6 (legacy only), Python 3.11 with numpy, pillow, pyserial, pytest.

**Spec:** `docs/superpowers/specs/2026-10-24-ca-sv-framework-design.md`

## Global Constraints

- Never modify `/home/nkyparissas/ca_workspace/Cellular_Automata_FPGA` (read-only reference).
- Work in `/home/nkyparissas/ca_workspace/Cellular_Automata_FPGA_new` on branch `sv_refactor`. Every `git commit` needs explicit user approval; ask at each commit step (batching per phase is fine if the user agrees).
- Never install packages; if a new Python package becomes necessary, give the user one `python3 -m pip install ...` command and wait.
- `rtl/` contains no vendor primitives or IP; Xilinx IP appears only under `boards/`.
- Own RTL lints clean with `verilator --lint-only -Wall` (waivers only in `rtl/lint.vlt`, each with a reason). Third-party code builds with `-Wno-fatal`.
- Naming: modules and files `ca_<name>`, ports `*_i`/`*_o`, clocks `clk_i`/`aclk_i`/`eclk_i`, active-low resets `rst_ni`/`arst_ni`/`erst_ni`.
- Window orientation `win[i][j]` = row `y-r+i`, column `x-r+j`; `MASK` bit index `i*NBH+j`.
- Memory layout and bursts exactly as spec Section 4; register map exactly as spec Section 10; rule semantics exactly as spec Section 11.
- Generated outputs go to `build/` (gitignored); nothing generated is committed.
- Python modules are importable via `pyproject.toml` `[tool.pytest.ini_options] pythonpath = ["model", "host", "tools", "tests"]`.

## Review Focus

1. Consumer backpressure for long periods (random `tready` low up to 90%, including mid-row) must not lose data or overwrite line-buffer slots; frames stay bit-exact. Test: Task 15 `test_core_consumer_backpressure`.
2. Heavy memory latency and backpressure (random AR/AW/W ready, gaps between R beats, late B) must not change results. Tests: Task 12 `tb_reader` stall mode, Task 13 `tb_writer` stall mode, Task 15 `test_core_memory_stalls`.
3. Frame requests while busy, bursts of requests, AUTO mode, RUN cleared mid-pass: exactly one swap per committing pass, nothing lost or duplicated. Test: Task 14 `tb_ctrl` cases `req_merge` and `run_clear_midpass`.
4. Register writes during a pass (FRAME_REPEAT, PAUSE, rule params, buffer addresses) apply at the next pass boundary only; front and back never alias. Tests: Task 14 `midpass_changes`, Task 15 `test_core_param_change_between_passes`.
5. Rows straddling 4 KB pages (row bytes not dividing 4096, base not 4 KB aligned) must split bursts and keep contents exact. Tests: Task 12 `tb_reader` 4k mode, Task 13 `tb_writer` 4k mode.

---

## Phase 1: Repository and golden model

### Task 1: Repository skeleton, vendored AXI library, lint harness, legacy findings document

**Files:**
- Create: `README.md` (short placeholder, finalised in Task 24), `.gitignore` (`build/`, `__pycache__/`, `*.vcd`, `*.fst`, `sim_build/`), `pyproject.toml`, `Makefile`
- Create: `third_party/axi/` (pulp-platform/axi tag v0.39.11: `include/`, `src/`, `LICENSE`, `Bender.yml`), `third_party/common_cells/` (tag v1.39.0: `include/`, `src/`, `LICENSE`, `Bender.yml`), `third_party/README.md` (upstream URLs, tags, commit hashes, licences)
- Create: `rtl/files.f`, `rtl/lint.vlt`, `sim/tb/tb_axi_smoke.sv`
- Create: `docs/legacy_vhdl_findings.md`
- Test: `tests/test_lint.py`

**Interfaces:**
- Produces: `rtl/files.f` (include dirs and ordered sources: third-party packages first, then `rtl/pkg`, `rtl/common`, ...); later tasks append their files. `make lint` and `tests/test_lint.py::test_rtl_lint_clean`.

- [ ] **Step 1:** Clone both upstream repos at the pinned tags into the scratchpad, copy only the listed folders into `third_party/`, record commit hashes in `third_party/README.md`.
- [ ] **Step 2:** Write `sim/tb/tb_axi_smoke.sv`: declares `AXI_TYPEDEF_ALL(axi, logic[31:0], logic[0:0], logic[127:0], logic[15:0], logic[0:0])` and `AXI_LITE_TYPEDEF_ALL(axil, logic[31:0], logic[31:0], logic[3:0])`, instantiates `axi_rw_join`, `axi_mux` (2 slave ports) and `axi_lite_mux` (2 slave ports) with tied-off inputs.
- [ ] **Step 3:** Write the failing test:

```python
def test_rtl_lint_clean():
    r = run(["make", "lint"])            # verilator --lint-only -Wall -f rtl/files.f --top-module tb_axi_smoke
    assert r.returncode == 0, r.stdout + r.stderr
```

- [ ] **Step 4:** Run `python3 -m pytest tests/test_lint.py -q`; expected FAIL (no Makefile target).
- [ ] **Step 5:** Write `Makefile` target `lint` (third-party sources with `-Wno-fatal`; any vendor lint noise waived in `rtl/lint.vlt` by file), `rtl/files.f`, `pyproject.toml`. If pulp modules fail under Verilator 5.045, stop and report to the user (fallback agreed: alexforencich/verilog-axi).
- [ ] **Step 6:** Run the test; expected PASS.
- [ ] **Step 7:** Write `docs/legacy_vhdl_findings.md` with the 12 findings from the review (file, line, description, impact, status "unconfirmed"); Task 23 updates the status column.
- [ ] **Step 8:** Commit checkpoint (ask the user): `chore: repository skeleton, vendored pulp axi, lint harness`.

### Task 2: Model grid I/O, palettes, frame packing

**Files:**
- Create: `model/ca_model/__init__.py`, `model/ca_model/grids.py`
- Create: `data/seeds/hodgepodge29_seed.bmp`, `data/seeds/hodgepodge19_seed.bmp`, `data/seeds/ghm_spirals.bmp`, `data/seeds/ap_random.bmp` (copied from the legacy `sw` folders: `8-bit (Hodgepodge 29x29)/seed.bmp`, `8-bit (Hodgepodge 19x19)/seed.bmp`, `4-bit (Greenberg-Hastings)/spirals.bmp`, `4-bit (Artificial Physics)/random.bmp`)
- Test: `tests/model/test_grids.py`

**Interfaces:**
- Produces: `load_seed(path: str, mode: str) -> np.ndarray` (uint8, shape (Y, X)); `mode` in `{"gray8", "index"}`; `pack_frame(grid: np.ndarray, cell_w: int) -> bytes`; `unpack_frame(data: bytes, grid_x: int, grid_y: int, cell_w: int) -> np.ndarray`; `to_rgb(grid, cell_w: int, palette: str) -> np.ndarray` (uint8 (Y, X, 3)); `save_png(grid, cell_w, palette, path)`; palettes `"gray"`, `"legacy4_windows"`, `"legacy4_gradient"`, `"legacy8"` (values transcribed from legacy `FHD_COLOR_CTRL.vhd`, 4-bit DAC values scaled by 17).

- [ ] **Step 1:** Compute reference CRCs once from the legacy text files (`zlib.crc32` of the uint8 array): `8-bit (Hodgepodge 29x29)/grid.txt`, `4-bit (Greenberg-Hastings)/grid_spirals.txt`, `4-bit (Artificial Physics)/random.txt`; check `8-bit (Hodgepodge 19x19)/bmp2ascii.m` to find which text file its `seed.bmp` produced and include it if one exists. Paste the constants into the test.
- [ ] **Step 2:** Write failing tests:

```python
@pytest.mark.parametrize("seed,mode,crc", LEGACY_SEED_CRCS)   # constants from Step 1
def test_seed_conversion_matches_legacy(seed, mode, crc):
    g = load_seed(seed, mode)
    assert g.shape == (1080, 1920) and zlib.crc32(g.tobytes()) == crc

@pytest.mark.parametrize("cell_w", [4, 8])
def test_pack_roundtrip(cell_w):
    g = rng.integers(0, 2**cell_w, (6, 64), dtype=np.uint8)
    assert np.array_equal(unpack_frame(pack_frame(g, cell_w), 64, 6, cell_w), g)

def test_pack_nibble_order():
    assert pack_frame(np.array([[1, 2]], np.uint8), 4) == bytes([0x21])
```

- [ ] **Step 3:** Run `python3 -m pytest tests/model/test_grids.py -q`; expected FAIL (import error).
- [ ] **Step 4:** Implement `grids.py` (Pillow for BMP and PNG; `gray8` reproduces `bmp2ascii.m`: `newmap = sort(gray(palette))`, value `round(newmap[index]*255)` with MATLAB `rgb2gray` weights 0.2989/0.5870/0.1140).
- [ ] **Step 5:** Run the tests; expected PASS. If a legacy pair differs, record why in the test as a documented exception rather than loosening the assertion.
- [ ] **Step 6:** Commit checkpoint: `feat(model): seed conversion, palettes, frame packing`.

### Task 3: Model masks and neighbourhood sums

**Files:**
- Create: `model/ca_model/masks.py`, `model/ca_model/neigh.py`
- Test: `tests/model/test_neigh.py`

**Interfaces:**
- Produces: `masks.moore(n) / von_neumann(n) / circle29() / ap21() -> np.ndarray` (bool, (n, n)); `masks.by_name(name: str, n: int) -> np.ndarray`; `masks.to_sv_literal(mask) -> str` (`NBH*NBH`-bit literal, bit `i*n+j`); `neigh.Boundary` (`TOROIDAL`, `CYLINDRICAL`, `RECTANGULAR`, `ZERO`); `neigh.window_sum(values: np.ndarray, mask, boundary) -> np.ndarray` (int64, shape of the *computed* region: (Y, X) for TOROIDAL/ZERO, (Y-2r, X) for CYLINDRICAL/RECTANGULAR); `neigh.naive_window_sum(...)` same signature, per-cell loops.

- [ ] **Step 1:** Transcribe `circle29` from the commented-out `INFECTED_CELL(i, j) <= 0` list (lines 119-262 of legacy `GHM/CA_ENGINE.vhd`: listed cells are outside the mask) and `ap21` from the `NEIGHBORHOOD_WEIGHT(i, j)` assignments of legacy `Artificial Physics/CA_ENGINE.vhd` (row i, column j as written).
- [ ] **Step 2:** Write failing tests:

```python
@pytest.mark.parametrize("bnd", list(Boundary))
@pytest.mark.parametrize("n,maskname", [(3,"moore"),(5,"von_neumann"),(7,"random"),(5,"moore")])
def test_window_sum_matches_naive(bnd, n, maskname):
    g = rng.integers(0, 256, (17, 23)); m = mask_for(maskname, n)
    assert np.array_equal(window_sum(g, m, bnd), naive_window_sum(g, m, bnd))

def test_legacy_masks_shape():
    assert circle29().sum() == CIRCLE29_COUNT and ap21().sum() == AP21_COUNT   # counts from Step 1
    assert von_neumann(29).sum() == 421 and circle29()[14, 14] and ap21()[10, 10]
```

- [ ] **Step 3:** Run `python3 -m pytest tests/model/test_neigh.py -q`; expected FAIL.
- [ ] **Step 4:** Implement `window_sum` by decomposing each mask row into contiguous runs and summing runs from row-wise prefix sums of the padded array (wrap padding horizontally for TOROIDAL/CYLINDRICAL, zero for RECTANGULAR/ZERO; vertically wrap for TOROIDAL, zero rows for ZERO, none for CYLINDRICAL/RECTANGULAR).
- [ ] **Step 5:** Run the tests; expected PASS.
- [ ] **Step 6:** Commit checkpoint: `feat(model): masks and boundary-aware window sums`.

### Task 4: Model rules and generation step

**Files:**
- Create: `model/ca_model/rules.py`, `model/ca_model/step.py`
- Test: `tests/model/test_rules.py`

**Interfaces:**
- Consumes: `neigh.window_sum`, `masks`.
- Produces: `rules.PARAM_INDEX = {"hodgepodge": {"G": 0, "K": 1}, "ghm": {"T": 0, "STATES": 1, "E": 2}, "interval": {"LO1": 0, "HI1": 1, "LO2": 2, "HI2": 3, "ALIVE": 4}}`; `rules.params_vector(rule: str, params: dict) -> list[int]` (length 8); elementwise array functions `rules.hodgepodge_cells(c, S, A, cell_w, G, K)`, `rules.ghm_cells(c, X, T, STATES)` and `rules.interval_cells(S, LO1, HI1, LO2, HI2, ALIVE)`; window-level reference `rules.cell_from_window(rule, win: np.ndarray, mask, params: list[int], cell_w) -> int` (used by the RTL unit tests); `step.step(grid, cfg: dict) -> np.ndarray` (frozen rows unchanged for CYLINDRICAL/RECTANGULAR); `step.run(grid, cfg, gens: int, callback=None) -> np.ndarray`.

- [ ] **Step 1:** Write failing tests with hand-computed values (N=3, CELL_W=8, MAX=255); `pv(rule, **kw)` is a test helper returning `params_vector(rule, kw)`:

```python
def test_hodgepodge_cases():
    hp = pv("hodgepodge", G=10, K=2)
    w = np.array([[0,5,0],[0,100,7],[255,0,0]])
    assert cell_from_window("hodgepodge", w, moore(3), hp, 8) == 101   # 367//4 + 10
    w[1,1] = 0;   assert cell_from_window("hodgepodge", w, moore(3), hp, 8) == 1   # A=3, 3//2
    w[1,1] = 255; assert cell_from_window("hodgepodge", w, moore(3), hp, 8) == 0
    w = np.full((3,3), 250); w[1,1] = 200
    assert cell_from_window("hodgepodge", w, moore(3), pv("hodgepodge", G=20, K=2), 8) == 255   # 2200//9+20 saturates
    assert cell_from_window("hodgepodge", np.ones((3,3),int), moore(3), pv("hodgepodge", G=0, K=0), 8) == 255  # K=0 -> MAX

def test_ghm_cases():
    gp = pv("ghm", T=2, STATES=15, E=1)
    w = np.zeros((3,3),int); w[0,0] = w[2,2] = 1
    assert cell_from_window("ghm", w, moore(3), gp, 4) == 1
    w[2,2] = 2;   assert cell_from_window("ghm", w, moore(3), gp, 4) == 0
    w[1,1] = 14;  assert cell_from_window("ghm", w, moore(3), gp, 4) == 0
    w[1,1] = 3;   assert cell_from_window("ghm", w, moore(3), gp, 4) == 4

@pytest.mark.parametrize("S,out", [(19,0),(20,1),(23,1),(24,0),(58,0),(59,1),(100,1),(101,0)])
def test_interval_edges(S, out):
    assert interval_cells(np.array([S]), 20, 23, 59, 100, 1)[0] == out

@pytest.mark.parametrize("rule", ["hodgepodge", "ghm", "interval"])
@pytest.mark.parametrize("bnd", list(Boundary))
def test_step_equals_window_reference(rule, bnd):
    cfg, g = small_random_case(rule, bnd, grid=(12, 10), nbh=3, seed=7)
    assert np.array_equal(step(g, cfg), reference_step(g, cfg))
    # reference_step: per-cell cell_from_window on the padded grid; frozen rows copied unchanged
```

- [ ] **Step 2:** Run `python3 -m pytest tests/model/test_rules.py -q`; expected FAIL.
- [ ] **Step 3:** Implement `rules.py` and `step.py` (int64 arithmetic; `A` and `X` exclude the centre explicitly; division by zero yields MAX).
- [ ] **Step 4:** Run the tests; expected PASS.
- [ ] **Step 5:** Commit checkpoint: `feat(model): hodgepodge, GHM and interval rules`.

### Task 5: Experiment configs, model CLI, 1000-generation images (user checkpoint)

**Files:**
- Create: `configs/hodgepodge29.json`, `configs/hodgepodge19.json`, `configs/ghm_circle_toroidal.json`, `configs/ghm_vn_toroidal.json`, `configs/ghm_moore_cylindrical.json`, `configs/ap_toroidal.json`
- Create: `model/ca_model/config.py`, `model/ca_model/run.py`, `docs/verification.md`
- Test: `tests/model/test_config_run.py`

**Interfaces:**
- Produces: `config.load(path) -> dict` (validates keys of spec Section 17, resolves paths relative to the repo root); CLI `python3 -m ca_model.run --config <json> --gens <n> [--png-every <k>] [--out build/exp/<name>]` writing `gen_<nnnnn>.png` and `gen_<nnnnn>.npy`.
- Config values: hodgepodge29 `nbh 29, G 105, K 5, cell_w 8, toroidal, moore, gray8, legacy8`; hodgepodge19 `nbh 19, G 48, K 3, cell_w 8, toroidal, moore, gray8, legacy8`; GHM `nbh 29, cell_w 4, T 5, STATES 15, E 1, index, legacy4_windows`, masks `circle29` / `von_neumann` (toroidal) / `moore` (cylindrical); AP `nbh 21, cell_w 4, ap21, LO1 20, HI1 23, LO2 59, HI2 100, ALIVE 1, toroidal, index, legacy4_windows`.

- [ ] **Step 1:** Write failing tests: `test_all_configs_load` (every file in `configs/` loads and its seed exists), `test_cli_small_run` (a temporary 32x24 config runs 3 generations and writes `gen_00003.png`).
- [ ] **Step 2:** Run `python3 -m pytest tests/model/test_config_run.py -q`; expected FAIL.
- [ ] **Step 3:** Implement `config.py` and `run.py`.
- [ ] **Step 4:** Run the tests; expected PASS.
- [ ] **Step 5:** Run all six experiments: `for c in configs/*.json; do python3 -m ca_model.run --config $c --gens 1000 --png-every 250; done`. Expected: `build/exp/<name>/gen_01000.png` for each, plus timing per generation in the log.
- [ ] **Step 6:** Show the six `gen_01000.png` paths (and `gen_00000.png`) to the user and wait for their verdict; record the verdict in `docs/verification.md`.
- [ ] **Step 7:** Commit checkpoint: `feat(model): experiment configs and CLI`.

## Phase 2: RTL building blocks

Unit-test harness used by Tasks 6 to 9: `tests/unit/rtl_runner.py` provides `run_cocotb(toplevel: str, sources: list[str], parameters: dict, test_module: str)` built on `cocotb_tools.runner.get_runner("verilator")`, using `rtl/files.f` include paths and `build/unit/<toplevel>_<hash>` as build dir. Created in Task 6.

### Task 6: Package and CDC primitives

**Files:**
- Create: `rtl/pkg/ca_pkg.sv`, `rtl/common/ca_delay.sv`, `rtl/common/ca_sync.sv`, `rtl/common/ca_reset_sync.sv`, `rtl/common/ca_gray_xfer.sv`, `rtl/common/ca_async_fifo.sv`
- Create: `tests/unit/rtl_runner.py`
- Test: `tests/unit/test_cdc.py`

**Interfaces:**
- Produces (`ca_pkg`): `boundary_e {BND_TOROIDAL, BND_CYLINDRICAL, BND_RECTANGULAR, BND_ZERO}` (2 bits), `rule_e {RULE_HODGEPODGE, RULE_GHM, RULE_INTERVAL}` (4 bits), `NUM_RULE_PARAMS = 8`, `rule_params_t = logic [7:0][31:0]`, param index localparams `HP_G=0, HP_K=1, GHM_T=0, GHM_STATES=1, GHM_E=2, IV_LO1=0, IV_HI1=1, IV_LO2=2, IV_HI2=3, IV_ALIVE=4`, functions `virt_rows(grid_y, nbh, bnd)`, `out_rows(grid_y, nbh, bnd)`, `out_row_first(nbh, bnd)`, `hzero(bnd)`, `tree_lat(n)` (= `$clog2(n)`, 0 for n=1), all per spec Section 5.
- `ca_delay #(W, D) (clk_i, d_i[W], q_o[W])`, D=0 is a wire.
- `ca_sync #(W=1, STAGES=2) (clk_i, d_i, q_o)`; `ca_reset_sync (clk_i, arst_ni, rst_no)`.
- `ca_gray_xfer #(W) (src_clk_i, src_rst_ni, src_bin_i[W], dst_clk_i, dst_rst_ni, dst_bin_o[W])`.
- `ca_async_fifo #(W, DEPTH) (wclk_i, wrst_ni, w_valid_i, w_ready_o, w_data_i, rclk_i, rrst_ni, r_valid_o, r_ready_i, r_data_o)`, first-word fall-through, DEPTH a power of two.

- [ ] **Step 1:** Write failing cocotb tests: `test_gray_xfer_monotonic` (source increments at random times with a 3:7 clock ratio; destination never decreases mod 2^W and ends equal to source), `test_async_fifo_random` (both clock ratios 1:1, 3:7 and 7:3; random valid/ready; 2000 words received in order, none lost), `test_delay` (D in {0, 1, 5}).
- [ ] **Step 2:** Run `python3 -m pytest tests/unit/test_cdc.py -q`; expected FAIL.
- [ ] **Step 3:** Implement the modules (gray pointers with `ca_sync` stages in the FIFO); add files to `rtl/files.f`.
- [ ] **Step 4:** Run the tests and `make lint`; expected PASS and lint clean.
- [ ] **Step 5:** Commit checkpoint: `feat(rtl): package and CDC primitives`.

### Task 7: Asymmetric RAM and cell packer

**Files:**
- Create: `rtl/common/ca_ram_sdp_asym.sv`, `rtl/engine/ca_cell_packer.sv`
- Test: `tests/unit/test_ram_packer.py`

**Interfaces:**
- `ca_ram_sdp_asym #(WR_W, RD_W, RD_DEPTH) (wclk_i, we_i, waddr_i[$clog2(RD_DEPTH*RD_W/WR_W)], wdata_i[WR_W], rclk_i, raddr_i[$clog2(RD_DEPTH)], rdata_o[RD_W])`; registered read (latency 1); narrow index k reads bits `[(k % (WR_W/RD_W))*RD_W +: RD_W]` of wide word `k / (WR_W/RD_W)`. Coded after the Vivado UG901 asymmetric-RAM template so Vivado infers block RAM.
- `ca_cell_packer #(CELL_W, DATA_W) (clk_i, rst_ni, cell_i, vld_i, word_o[DATA_W], word_vld_o)`; first cell in bits `[CELL_W-1:0]`.

- [ ] **Step 1:** Write failing tests: `test_ram_mapping` (WR_W 128, RD_W in {4, 8}, RD_DEPTH 64: write random words, read every narrow index, compare with the mapping), `test_packer_order` (CELL_W 4 and 8, DATA_W 64 and 128, with random gaps in `vld_i`).
- [ ] **Step 2:** Run `python3 -m pytest tests/unit/test_ram_packer.py -q`; expected FAIL.
- [ ] **Step 3:** Implement; add to `rtl/files.f`.
- [ ] **Step 4:** Run tests and `make lint`; expected PASS.
- [ ] **Step 5:** Commit checkpoint: `feat(rtl): asymmetric RAM and cell packer`.

### Task 8: Adder tree and pipelined divider

**Files:**
- Create: `rtl/arith/ca_adder_tree.sv`, `rtl/arith/ca_div_pipe.sv`
- Test: `tests/unit/test_arith.py`

**Interfaces:**
- `ca_adder_tree #(N_IN, IN_W, OUT_W) (clk_i, in_i[N_IN-1:0][IN_W-1:0], sum_o[OUT_W-1:0])`, latency `ca_pkg::tree_lat(N_IN)`, one register per level, unsigned.
- `ca_div_pipe #(NUM_W, DEN_W) (clk_i, num_i, den_i, quo_o[NUM_W-1:0])`, restoring division, one quotient bit per stage, latency `NUM_W`; `den_i == 0` gives all ones.

- [ ] **Step 1:** Write failing tests: `test_adder_tree` (N_IN in {1, 2, 9, 441, 841}, random inputs every cycle, output equals the sum `tree_lat(N_IN)` cycles later), `test_div_pipe` (NUM_W 18, DEN_W 10: random pairs every cycle plus edge cases `num=0`, `den=1`, `den=0`, `num=2**18-1`).
- [ ] **Step 2:** Run `python3 -m pytest tests/unit/test_arith.py -q`; expected FAIL.
- [ ] **Step 3:** Implement; add to `rtl/files.f`.
- [ ] **Step 4:** Run tests and `make lint`; expected PASS.
- [ ] **Step 5:** Commit checkpoint: `feat(rtl): adder tree and pipelined divider`.

### Task 9: Window, rules and engine

**Files:**
- Create: `rtl/engine/ca_window.sv`, `rtl/rules/ca_rule_hodgepodge.sv`, `rtl/rules/ca_rule_ghm.sv`, `rtl/rules/ca_rule_interval.sv`, `rtl/engine/ca_engine.sv`
- Test: `tests/unit/test_engine.py`

**Interfaces:**
- Consumes: `ca_adder_tree`, `ca_div_pipe`, `ca_delay`, `ca_pkg`; Python `rules.cell_from_window`.
- `ca_window #(N, CELL_W) (clk_i, col_i[N-1:0][CELL_W-1:0], vld_i, win_o[N-1:0][N-1:0][CELL_W-1:0], vld_o)`: each cycle `win[i][j-1] <= win[i][j]`, `win[i][N-1] <= col_i[i]`, `vld_o <= vld_i`.
- Rules: `ca_rule_<name> #(N, CELL_W, logic [N*N-1:0] MASK) (clk_i, win_i, vld_i, params_i (ca_pkg::rule_params_t), cell_o[CELL_W-1:0], vld_o)`; each rule delays `vld` and the centre cell internally to match its own latency.
- `ca_engine #(N, CELL_W, ca_pkg::rule_e RULE, logic [N*N-1:0] MASK) (clk_i, col_i, vld_i, params_i, cell_o, vld_o)`: window plus a `generate case (RULE)`.

- [ ] **Step 1:** Write failing tests: for each rule, `test_<rule>_random_windows` streams random columns (N in {3, 5, 9}, CELL_W 4 and 8, random masks containing the centre, random params, `vld_i` random), reconstructs each window in Python from the column stream, and asserts every valid output equals `rules.cell_from_window`; `test_engine_output_count` checks that the number of `vld_o` pulses equals the number of `vld_i` pulses.
- [ ] **Step 2:** Run `python3 -m pytest tests/unit/test_engine.py -q`; expected FAIL.
- [ ] **Step 3:** Implement window, rules and engine; add to `rtl/files.f`.
- [ ] **Step 4:** Run tests and `make lint`; expected PASS. Also lint the engine once at N=29, CELL_W=8 (hodgepodge) and N=21, CELL_W=4 (interval) to catch width problems at full size.
- [ ] **Step 5:** Commit checkpoint: `feat(rtl): sliding window, rule plug-ins, engine`.

## Phase 3: Line buffer, memory masters, control

### Task 10: Line buffer with drain sequencer

**Files:**
- Create: `rtl/engine/ca_line_buffer.sv`
- Test: `sim/tb/tb_line_buffer.sv`, `tests/sim/test_line_buffer.py`, shared runner `tools/rtlsim.py`

**Interfaces:**
- Consumes: `ca_ram_sdp_asym`, `ca_gray_xfer`, `ca_pkg`.
- `ca_line_buffer #(GRID_X, GRID_Y, CELL_W, NBH, DATA_W, ca_pkg::boundary_e BND, FIFO_ROWS, PW)`:
  aclk side `aclk_i, arst_ni, alloc_valid_i, alloc_ready_o, alloc_slot_o[$clog2(NBH+1)-1:0], wr_en_i, wr_slot_i, wr_addr_i[$clog2(GRID_X*CELL_W/DATA_W)-1:0], wr_data_i[DATA_W-1:0], row_done_i, popped_i[PW-1:0]`;
  eclk side `eclk_i, erst_ni, col_o[NBH-1:0][CELL_W-1:0], vld_o`.
  Behaviour per spec Sections 5, 6 and 8 (`row_done_i` pulses once after the last beat of an allocated row is written).
- Produces `tools/rtlsim.py`: `build(tb_top: str, defines: dict, params: dict, out_dir) -> Path` (Verilator `--binary --timing -Wno-fatal` on `rtl/files.f` plus `sim/`), `run(binary, plusargs: dict, timeout_s) -> str` (raises unless the log contains `TB_PASS`).

- [ ] **Step 1:** Write `tb_line_buffer.sv`: a behavioural writer feeds the virtual-row sequence of a small random grid (from `+grid_hex`), with random gaps, honouring `alloc_ready_o`; a behavioural popper advances `popped_i` with random delay; a checker reconstructs windows from `col_o`/`vld_o` and compares every valid window centre with the expected padded grid (passed as `+expect_hex`). It prints `TB_PASS` or `$fatal`s.
- [ ] **Step 2:** Write failing pytest `test_line_buffer[bnd-nbh-cell_w-ratio]` over `BND` x `NBH in {3,5,7}` x `CELL_W in {4,8}` x clock ratio `{1:1, 2:3, 3:2}` on a 32x12 grid with two passes; the expected window stream comes from the model's padding functions.
- [ ] **Step 3:** Run `python3 -m pytest tests/sim/test_line_buffer.py -q`; expected FAIL.
- [ ] **Step 4:** Implement `ca_line_buffer.sv`; add to `rtl/files.f`.
- [ ] **Step 5:** Run the tests and `make lint`; expected PASS.
- [ ] **Step 6:** Commit checkpoint: `feat(rtl): dual-clock line buffer with drain sequencer`.

### Task 11: Verification models

**Files:**
- Create: `sim/models/axi_mem_model.sv`, `sim/models/axis_sink_model.sv`, `sim/models/axil_bfm.sv`
- Test: `sim/tb/tb_models.sv`, `tests/sim/test_models.py`

**Interfaces:**
- `axi_mem_model #(DATA_W, ADDR_W, ID_W, MEM_BYTES, type axi_req_t, type axi_resp_t) (clk_i, rst_ni, req_i, resp_o)`; plusargs `+mem_stall=<0..95>` (percent of cycles each ready/valid is withheld), `+mem_lat=<max cycles before first R beat or B>`, `+mem_seed=<n>`; tasks `load_hex(string file, longint addr)`, `dump_hex(string file, longint addr, longint bytes)`; assertions: INCR only, full-width size, no 4 KB crossing, `wlast` on the last beat, AW/W/AR payload stable while valid and not ready, address in range.
- `axis_sink_model #(DATA_W, BEATS_PER_ROW, ROWS) (clk_i, rst_ni, tdata_i, tvalid_i, tready_o, tlast_i, tuser_i, frame_req_o)`; plusargs `+sink_stall=<0..95>`, `+sink_req=<0|1>` (1: pulse `frame_req_o` a random 0..200 cycles after each complete frame, and once after reset); checks `tuser` on beat 0 and `tlast` every `BEATS_PER_ROW`; keeps the last complete frame in `frame[]` and a count `frames_seen`.
- `axil_bfm #(type axil_req_t, type axil_resp_t) (clk_i, req_o, resp_i)` with tasks `write(addr, data)` and `read(addr, output data)`.

- [ ] **Step 1:** Write `tb_models.sv`: a scripted AXI master writes bursts (including one that ends exactly at a 4 KB boundary) and reads them back under `+mem_stall=50`; a scripted stream source drives two frames into the sink.
- [ ] **Step 2:** Write failing pytest `test_models_selfcheck` (runs `tb_models` with stall 0 and 50; expects `TB_PASS`) and `test_mem_model_flags_4k_crossing` (a deliberately crossing burst under `+bad_burst=1` must end with a fatal assertion).
- [ ] **Step 3:** Run `python3 -m pytest tests/sim/test_models.py -q`; expected FAIL.
- [ ] **Step 4:** Implement the three models.
- [ ] **Step 5:** Run the tests; expected PASS.
- [ ] **Step 6:** Commit checkpoint: `test(sim): AXI memory, stream sink and AXI-Lite models`.

### Task 12: Frame reader

**Files:**
- Create: `rtl/mem/ca_frame_reader.sv`
- Test: `sim/tb/tb_reader.sv`, `tests/sim/test_reader.py`

**Interfaces:**
- Consumes: `ca_pkg` row-sequence functions, `axi_mem_model`, `axis_sink_model`.
- `ca_frame_reader #(GRID_X, GRID_Y, CELL_W, NBH, DATA_W, ADDR_W, ca_pkg::boundary_e BND, MAX_BURST, type axi_req_t, type axi_resp_t) (clk_i, rst_ni, start_i, base_addr_i[ADDR_W-1:0], fwd_en_i, done_o, axi_req_o, axi_resp_i, m_axis_tdata_o, m_axis_tvalid_o, m_axis_tready_i, m_axis_tlast_o, m_axis_tuser_o, lb_alloc_valid_o, lb_alloc_ready_i, lb_alloc_slot_i, lb_wr_en_o, lb_wr_slot_o, lb_wr_addr_o, lb_wr_data_o, lb_row_done_o)`. Only AR and R fields of `axi_req_o` are driven; write fields are tied to zero. Single ID; AR issue runs ahead of R reception through a small row-descriptor FIFO (slot, zero flag, forward flag). `done_o` pulses after the last row's `lb_row_done_o`.

- [ ] **Step 1:** Write `tb_reader.sv`: memory preloaded with a frame; a line-buffer stub grants slots with random delays and records every write; the sink checks the forwarded frame equals memory; the TB checks the recorded slot writes equal the virtual-row sequence of spec Section 5.
- [ ] **Step 2:** Write failing pytest `test_reader[bnd-mode]` with modes `basic`, `stall` (`+mem_stall=60 +sink_stall=60`), `4k` (GRID_X 1000, CELL_W 8, DATA_W 64, base 0x0FC8), `nofwd` (`fwd_en_i=0`, sink must see no beats).
- [ ] **Step 3:** Run `python3 -m pytest tests/sim/test_reader.py -q`; expected FAIL.
- [ ] **Step 4:** Implement; add to `rtl/files.f`.
- [ ] **Step 5:** Run the tests and `make lint`; expected PASS.
- [ ] **Step 6:** Commit checkpoint: `feat(rtl): AXI4 frame reader`.

### Task 13: Frame writer

**Files:**
- Create: `rtl/mem/ca_frame_writer.sv`
- Test: `sim/tb/tb_writer.sv`, `tests/sim/test_writer.py`

**Interfaces:**
- `ca_frame_writer #(GRID_X, GRID_Y, CELL_W, NBH, DATA_W, ADDR_W, ca_pkg::boundary_e BND, MAX_BURST, PW, type axi_req_t, type axi_resp_t) (clk_i, rst_ni, start_i, commit_i, base_addr_i, done_o, s_tdata_i[DATA_W-1:0], s_tvalid_i, s_tready_o, popped_o[PW-1:0], axi_req_o, axi_resp_i)`. Processes `out_rows` rows per pass starting at row `out_row_first`; when `commit_i=0` it pops and discards without AXI traffic; `popped_o` increments once per fully popped row; `done_o` pulses after the last row and, when committing, the last B response. Only AW, W and B fields are driven.

- [ ] **Step 1:** Write `tb_writer.sv`: a source pushes `out_rows` random rows with random gaps; the TB compares memory with the expected image (rows outside the written range must keep their preload pattern).
- [ ] **Step 2:** Write failing pytest `test_writer[bnd-mode]`, modes `basic`, `stall`, `4k` (same geometry as Task 12), `discard` (memory unchanged, `done_o` still pulses, `popped_o` reaches `out_rows`).
- [ ] **Step 3:** Run `python3 -m pytest tests/sim/test_writer.py -q`; expected FAIL.
- [ ] **Step 4:** Implement; add to `rtl/files.f`.
- [ ] **Step 5:** Run the tests and `make lint`; expected PASS.
- [ ] **Step 6:** Commit checkpoint: `feat(rtl): AXI4 frame writer`.

### Task 14: Registers and controller

**Files:**
- Create: `rtl/ctrl/ca_regs_pkg.sv`, `rtl/ctrl/ca_regs.sv`, `rtl/ctrl/ca_controller.sv`
- Test: `sim/tb/tb_ctrl.sv`, `tests/sim/test_ctrl.py`

**Interfaces:**
- `ca_regs_pkg`: offsets `REG_ID=8'h00, REG_CTRL=8'h04, REG_STATUS=8'h08, REG_FRAME_REQ=8'h0C, REG_FRAME_REPEAT=8'h10, REG_GENS_PER_FRAME=8'h14, REG_GEN_COUNT=8'h18, REG_PASS_COUNT=8'h1C, REG_BUF0_LO=8'h20, REG_BUF0_HI=8'h24, REG_BUF1_LO=8'h28, REG_BUF1_HI=8'h2C, REG_GRID_DIM=8'h30, REG_CORE_CFG=8'h34, REG_RULE_PARAM0=8'h40`; `CA_ID=32'hCA5E_0001`; bits `CTRL_RUN=0, CTRL_PAUSE=1, CTRL_AUTO=2, CTRL_RESET_STATE=3, ST_BUSY=0, ST_FRONT=1, ST_PENDING=2`.
- `ca_regs #(GRID_X, GRID_Y, CELL_W, NBH, ca_pkg::boundary_e BND, ca_pkg::rule_e RULE, DATA_W, ADDR_W, logic [63:0] BUF0_DEFAULT, BUF1_DEFAULT, int FRAME_REPEAT_DEFAULT, ca_pkg::rule_params_t PARAM_DEFAULTS, type axil_req_t, type axil_resp_t) (clk_i, rst_ni, axil_req_i, axil_resp_o, run_o, pause_o, auto_o, reset_state_o, frame_req_o, frame_repeat_o[15:0], gens_per_frame_o[15:0], buf0_addr_o[ADDR_W-1:0], buf1_addr_o[ADDR_W-1:0], rule_params_o, busy_i, front_i, pending_i, gen_count_i[31:0], pass_count_i[31:0])`.
- `ca_controller (clk_i, rst_ni, run_i, pause_i, auto_i, reset_state_i, req_i, frame_repeat_i[15:0], gens_per_frame_i[15:0], pass_start_o, rd_fwd_en_o, wr_commit_o, rd_done_i, wr_done_i, front_o, busy_o, pending_o, gen_count_o[31:0], pass_count_o[31:0], pass_done_o)`; `pass_start_o` starts reader and writer together and samples addresses and parameters; semantics per spec Section 9.

- [ ] **Step 1:** Write `tb_ctrl.sv` with `axil_bfm` and behavioural reader/writer stand-ins (random pass durations) and named cases selected by `+case=`: `regs_rw` (every RW register reads back, RO registers ignore writes, unmapped reads 0, ID constant), `repeat_cadence` (FRAME_REPEAT=2: commits on requested passes 3, 6, 9), `gens_per_frame` (GENS_PER_FRAME=3: one request gives 3 commits, the first with `rd_fwd_en_o=1`, the others 0), `pause` (no commits, passes still run on request), `req_merge` (10 doorbells during a busy pass produce exactly one further pass), `auto` (back-to-back passes while AUTO), `run_clear_midpass` (current pass completes, no new pass starts), `midpass_changes` (FRAME_REPEAT, PAUSE and RULE_PARAM writes during a pass do not change that pass's commit decision or sampled params), `reset_state`.
- [ ] **Step 2:** Write failing pytest `test_ctrl[case]` for every case, plus `tests/host/test_regs_parity.py::test_regs_parity`, which parses `ca_regs_pkg.sv` and compares with `host/ca_host/regs.py` (create `regs.py` here with the same constants).
- [ ] **Step 3:** Run `python3 -m pytest tests/sim/test_ctrl.py tests/host/test_regs_parity.py -q`; expected FAIL.
- [ ] **Step 4:** Implement the three RTL files and `host/ca_host/__init__.py`, `host/ca_host/regs.py`; add RTL to `rtl/files.f`.
- [ ] **Step 5:** Run the tests and `make lint`; expected PASS.
- [ ] **Step 6:** Commit checkpoint: `feat(rtl): register file and pass controller`.

## Phase 4: Core integration and full-size runs

### Task 15: Core top, flat wrapper, integration matrix

**Files:**
- Create: `rtl/top/ca_params_cdc.sv`, `rtl/top/ca_core.sv`, `rtl/top/ca_core_flat.sv`, `tools/gen_cfg.py`
- Test: `sim/tb/tb_core.sv`, `tests/core/test_core.py`

**Interfaces:**
- Consumes: everything from Tasks 6 to 14, pulp `axi_rw_join`.
- `ca_params_cdc (aclk_i, arst_ni, capture_i, params_i, eclk_i, erst_ni, params_o)` (toggle handshake, spec Section 7).
- `ca_core #(GRID_X, GRID_Y, CELL_W, NBH, ca_pkg::boundary_e BOUNDARY, ca_pkg::rule_e RULE, logic [NBH*NBH-1:0] MASK, DATA_W=128, ADDR_W=32, ID_W=1, MAX_BURST=64, FIFO_ROWS=2, logic [63:0] BUF0_DEFAULT=0, BUF1_DEFAULT=64'h0100_0000, FRAME_REPEAT_DEFAULT=0, ca_pkg::rule_params_t PARAM_DEFAULTS='0, type axi_req_t, type axi_resp_t, type axil_req_t, type axil_resp_t) (aclk_i, arst_ni, eclk_i, erst_ni, s_axil_req_i, s_axil_resp_o, m_axi_req_o, m_axi_resp_i, m_axis_tdata_o, m_axis_tvalid_o, m_axis_tready_i, m_axis_tlast_o, m_axis_tuser_o, frame_req_i, pass_done_o)`; elaboration `$error` for every constraint in spec Section 4.
- `ca_core_flat`: same parameters minus the types; declares typedefs with `AXI_TYPEDEF_ALL`/`AXI_LITE_TYPEDEF_ALL`; Xilinx-style flat ports `m_axi_{aw,w,b,ar,r}*`, `s_axil_*`, `m_axis_*`.
- `tools/gen_cfg.py`: `gen_cfg_svh(cfg: dict, data_w: int, path)` writing `localparam`s `GRID_X, GRID_Y, CELL_W, NBH, BOUNDARY, RULE, MASK, PARAMS, DATA_W`; `frame_to_hex(grid, cell_w, data_w) -> list[str]`; `hex_to_frame(lines, grid_x, grid_y, cell_w, data_w) -> np.ndarray`.
- `tb_core.sv` plusargs: `+seed_hex`, `+gens=<n>`, `+dump_gens=<comma list>`, `+dump_dir`, `+mem_stall`, `+sink_stall`, `+sink_req`, `+aclk_ps`, `+eclk_ps`, `+midpass_param=<0|1>`.

- [ ] **Step 1:** Write `tb_core.sv`: load the seed into BUF0 (and BUF1 for legacy cylindrical/rectangular), program registers, `RUN`, then per generation either doorbell (`+sink_req=0`) or consumer requests (`+sink_req=1`), wait for `pass_done_o` with a commit, dump requested generations from `BUF[FRONT]`; at every requested pass check the sink frame equals the front buffer.
- [ ] **Step 2:** Write failing pytest cases in `tests/core/test_core.py`:
  `test_core_matrix[rule-bnd-nbh-cell_w-data_w]` (rules x 4 boundaries x NBH {3, 5, 7} x CELL_W {4, 8} x DATA_W {64, 128}, grid 64x24, 4 generations, every generation bit-exact against `step.run`);
  `test_core_memory_stalls` (`+mem_stall=70`, eclk:aclk 3:2 and 2:3);
  `test_core_consumer_backpressure` (`+sink_req=1 +sink_stall=90`);
  `test_core_param_change_between_passes` (`+midpass_param=1`: G changes during pass 2; generations 1 and 2 use the old G, 3 onwards the new G, all matching the model);
  `test_core_bad_params_fail_elab` (GRID_X=30 with CELL_W 8 and DATA_W 128 must fail to build with the `$error` message).
- [ ] **Step 3:** Run `python3 -m pytest tests/core -q`; expected FAIL.
- [ ] **Step 4:** Implement the RTL and `gen_cfg.py`; add to `rtl/files.f`.
- [ ] **Step 5:** Run `python3 -m pytest tests/core -q` and `make lint`; expected PASS.
- [ ] **Step 6:** Commit checkpoint: `feat(rtl): CA core, flat wrapper, integration tests`.

### Task 16: Full-HD RTL experiments (user checkpoint)

**Files:**
- Create: `tools/run_rtl_experiment.py`
- Modify: `docs/verification.md`

**Interfaces:**
- Consumes: `tb_core`, `tools/rtlsim.py`, `tools/gen_cfg.py`, configs from Task 5.
- CLI `python3 tools/run_rtl_experiment.py --config <json> --gens <n> [--dump-every <k>] [--threads <t>]` writes `build/rtl_exp/<name>/gen_<nnnnn>.png|.npy` and `timing.txt`.

- [ ] **Step 1:** Implement the CLI (reuses `gen_cfg.py`, compares every dumped generation with the model and prints `MATCH`/`MISMATCH` with the first differing cell).
- [ ] **Step 2:** For each of the six configs run 3 generations with dumps every generation; expected `MATCH` for generations 1 to 3; record wall-clock seconds per generation.
- [ ] **Step 3:** Report the per-generation cost and the projected time for 1000 generations to the user and ask whether to launch the long runs (in the background, `run_in_background`).
- [ ] **Step 4:** If approved: run them, then compare `gen_01000.npy` with the model's `gen_01000.npy`; expected identical; record results in `docs/verification.md`.
- [ ] **Step 5:** Commit checkpoint: `test: full-HD RTL experiment runner and results`.

## Phase 5: Consumers and boards

### Task 17: Display consumer

**Files:**
- Create: `rtl/consumers/ca_video_out.sv`, `rtl/consumers/ca_palette.sv`
- Test: `sim/tb/tb_video.sv`, `tests/sim/test_video.py`

**Interfaces:**
- `ca_palette #(CELL_W, string PALETTE) (clk_i, cell_i, rgb_o[23:0])`, palettes as in Task 2 (`"gray"`, `"legacy4_windows"`, `"legacy4_gradient"`, `"legacy8"`), latency 1; values must equal `grids.to_rgb`.
- `ca_video_out #(DATA_W, CELL_W, H_ACTIVE, H_FP, H_SYNC, H_BP, V_ACTIVE, V_FP, V_SYNC, V_BP, bit HS_POL, bit VS_POL, REQ_LINE, FIFO_DEPTH, string PALETTE) (aclk_i, arst_ni, s_axis_tdata_i, s_axis_tvalid_i, s_axis_tready_o, s_axis_tlast_i, s_axis_tuser_i, frame_req_o, pclk_i, prst_ni, hsync_o, vsync_o, de_o, rgb_o[23:0], underflow_o)`; `frame_req_o` (aclk) pulses once per video frame when the line counter reaches `REQ_LINE`.

- [ ] **Step 1:** Write `tb_video.sv` with a 16x8-active timing (small porches), a source streaming frames on request, and a capture of `rgb_o` during `de_o` compared with `to_rgb` of the source frame (expected values from a hex file); check sync pulse widths and one `frame_req_o` per frame; a starved case checks `underflow_o` and recovery at the next `tuser`.
- [ ] **Step 2:** Write failing pytest `test_video[palette]` and `test_video_underflow_recovers`.
- [ ] **Step 3:** Run `python3 -m pytest tests/sim/test_video.py -q`; expected FAIL.
- [ ] **Step 4:** Implement; add to `rtl/files.f`.
- [ ] **Step 5:** Run tests and `make lint`; expected PASS.
- [ ] **Step 6:** Commit checkpoint: `feat(rtl): display consumer`.

### Task 18: UART bridge, buttons, Nexys 4 DDR board

**Files:**
- Create: `rtl/io/ca_uart_rx.sv`, `rtl/io/ca_uart_tx.sv`, `rtl/io/ca_uart_bridge.sv`, `rtl/io/ca_buttons_axil.sv`
- Create: `boards/nexys4ddr/top_nexys4ddr.sv`, `boards/nexys4ddr/nexys4ddr.xdc` (pins transcribed from legacy `Nexys4DDR_Master.xdc`: clock E3, VGA, UART C4/D4, buttons, LEDs), `boards/nexys4ddr/ip/mig_ddr2_axi.prj` (DDR2 settings of the legacy `mig.prj` with the AXI4 interface enabled, 128-bit data), `boards/nexys4ddr/build.tcl`, `boards/nexys4ddr/README.md`
- Test: `sim/tb/tb_uart_bridge.sv`, `sim/tb/tb_nexys4ddr.sv`, `tests/sim/test_uart_board.py`

**Interfaces:**
- `ca_uart_bridge #(CLK_HZ, BAUD=2_000_000, DATA_W, ADDR_W, type axi_req_t, type axi_resp_t, type axil_req_t, type axil_resp_t) (clk_i, rst_ni, rxd_i, txd_o, m_axi_req_o, m_axi_resp_i, m_axil_req_o, m_axil_resp_i)`; protocol per spec Section 14; memory transfers as single-beat AXI4 transactions.
- `ca_buttons_axil #(CLK_HZ, DEBOUNCE_MS=20, SLOW_REPEAT=59, type axil_req_t, type axil_resp_t) (clk_i, rst_ni, btn_up_i, btn_down_i, btn_pause_i, m_axil_req_o, m_axil_resp_i)` (synchronises, debounces, writes `FRAME_REPEAT`, read-modify-writes `CTRL.PAUSE`).
- `top_nexys4ddr`: in simulation the MIG is replaced by `axi_mem_model` through ``ifdef CA_SIM``; 1920x1080@60 timing parameters (2200x1125 total, 148.5 MHz).

- [ ] **Step 1:** Write `tb_uart_bridge.sv` (UART BFM tasks at 2 Mbaud: register write/read, 64-byte memory write then read-back) and `tb_nexys4ddr.sv` (reduced grid 64x24 and reduced video timing via parameters: load seed over UART, set RUN, let video requests drive 3 generations, read the front buffer over UART and compare with the model; press "pause" and check no further commits).
- [ ] **Step 2:** Write failing pytests `test_uart_bridge_protocol`, `test_buttons_debounce` (bounce shorter than `DEBOUNCE_MS` is ignored), `test_nexys4ddr_system`.
- [ ] **Step 3:** Run `python3 -m pytest tests/sim/test_uart_board.py -q`; expected FAIL.
- [ ] **Step 4:** Implement RTL, board top, XDC, MIG project and `build.tcl` (non-project flow: read sources, generate MIG from the `.prj`, synth, impl, bitstream). Mark the Tcl and `.prj` as unverified in the README.
- [ ] **Step 5:** Run tests and `make lint`; expected PASS.
- [ ] **Step 6:** Commit checkpoint: `feat(boards): UART bridge, buttons, Nexys 4 DDR variant`.

### Task 19: Generic XDMA template

**Files:**
- Create: `boards/xdma_template/bd_ca_xdma.tcl`, `boards/xdma_template/top_xdma.sv`, `boards/xdma_template/README.md`
- Test: `tests/test_boards_static.py`

**Interfaces:**
- `bd_ca_xdma.tcl` variables at the top: `part`, `board_part`, `pcie_lanes`, `pcie_gen`, `ddr_interface` (name used by board automation), `eclk_mhz`, `grid_x`, `grid_y`, config JSON path. Creates XDMA (AXI-MM, 1 H2C + 1 C2H, PCIe-to-AXI-Lite master BAR 64 KB), SmartConnect (S00 XDMA `M_AXI`, S01 `ca_core_flat` `m_axi` → DDR), AXI-Lite path XDMA `M_AXI_LITE` → `ca_core_flat` `s_axil`, clocking wizard for `eclk`, address map DDR at 0x0 and core registers at 0x0 of the BAR, `m_axis_tready` tied high.
- README: adaptation steps, host driver setup (dma_ip_drivers), address conventions used by `XdmaDevice`.

- [ ] **Step 1:** Write failing `test_xdma_template_static`: the Tcl file defines every variable listed above and references `ca_core_flat`; `top_xdma.sv` lints with `verilator --lint-only` against stub modules for the BD wrapper.
- [ ] **Step 2:** Run `python3 -m pytest tests/test_boards_static.py -q`; expected FAIL.
- [ ] **Step 3:** Write the template files.
- [ ] **Step 4:** Run the test; expected PASS.
- [ ] **Step 5:** Commit checkpoint: `feat(boards): generic XDMA template`.

## Phase 6: Host software

### Task 20: Host library

**Files:**
- Create: `host/ca_host/device.py`, `host/ca_host/xdma.py`, `host/ca_host/uart.py`, `host/ca_host/simdev.py`, `host/ca_host/controller.py`
- Test: `tests/host/test_controller.py`, `tests/host/test_xdma_fake.py`, `tests/host/test_uart_protocol.py`

**Interfaces:**
- Consumes: `ca_host.regs`, `ca_model.step`, `ca_model.grids`.
- `device.Device` (abstract): `read_reg(off) -> int`, `write_reg(off, val)`, `read_mem(addr, n) -> bytes`, `write_mem(addr, data: bytes)`.
- `xdma.XdmaDevice(prefix="/dev/xdma0", user_size=0x10000)`: `mmap` of `<prefix>_user`, `os.pread`/`os.pwrite` on `<prefix>_c2h_0` / `<prefix>_h2c_0` with the DDR address as offset; constructor accepts explicit paths for testing.
- `uart.UartDevice(port, baud=2_000_000, timeout=5.0)` and pure functions `encode_reg_write(off, val) -> bytes` etc.
- `simdev.SimDevice(cfg: dict)`: register semantics of spec Sections 9 and 10, memory as a bytearray, passes executed synchronously on `FRAME_REQ` with `ca_model.step`.
- `controller.CAController(dev: Device, cfg: dict)`: `info() -> dict` (from GRID_DIM/CORE_CFG), `load_grid(grid)` (both buffers for legacy cylindrical/rectangular), `start()`, `stop()`, `set_frame_repeat(n)`, `set_gens_per_frame(n)`, `set_pause(b)`, `set_params(dict)`, `request_frame()`, `wait_frame(timeout) -> int` (GEN_COUNT), `read_frame() -> np.ndarray`.

- [ ] **Step 1:** Write failing tests: `test_controller_sim_matches_model` (SimDevice on a 32x24 config: 5 frames with FRAME_REPEAT 0 equal `step.run` generations 1 to 5; FRAME_REPEAT 2 yields one new generation every 3 requests), `test_xdma_fake_nodes` (temporary files stand in for `_user`, `_c2h_0`, `_h2c_0`; `write_mem`/`read_mem` hit the given offsets; registers go through the mmap), `test_uart_encoding` (byte-exact frames for each command of spec Section 14).
- [ ] **Step 2:** Run `python3 -m pytest tests/host -q`; expected FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the tests; expected PASS.
- [ ] **Step 5:** Commit checkpoint: `feat(host): device transports and controller`.

### Task 21: Viewer and CLI

**Files:**
- Create: `host/ca_host/viewer.py`, `host/ca_host/cli.py`
- Test: `tests/host/test_cli.py`

**Interfaces:**
- CLI `python3 -m ca_host.cli --transport {xdma,uart,sim} --config <json> [--seed <bmp>] [--device /dev/xdma0] [--port /dev/ttyUSB1] [--frames <n>] [--headless --out <dir>]`.
- Keys in the window: `+`/`-` decrease/increase FRAME_REPEAT, `f` cycles GENS_PER_FRAME 1/2/4/8, space toggles PAUSE, `s` saves a PNG, `q` quits. OpenCV when importable; otherwise headless PNG output.

- [ ] **Step 1:** Write failing test `test_cli_headless_sim` (sim transport, 32x24 config, `--frames 4 --headless --out tmp`: four PNGs whose pixels equal `to_rgb` of model generations 1 to 4).
- [ ] **Step 2:** Run `python3 -m pytest tests/host/test_cli.py -q`; expected FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the test; expected PASS.
- [ ] **Step 5:** Commit checkpoint: `feat(host): viewer and CLI`.

## Phase 7: Legacy VHDL in GHDL

### Task 22: Legacy core co-simulation on small grids

**Files:**
- Create: `tests/legacy/models/line_buffer_model.vhd` (entities `LINE_BUFFER_4b`, `LINE_BUFFER_8B`: generic depth, 128-bit write, narrow read, latency 1, little-endian mapping), `tests/legacy/models/divider_model.vhd` (entity `DIVIDER`, latency 34, output quotient & remainder as the IP), `tests/legacy/tb_legacy_core.vhd`, `tests/legacy/test_legacy_core.py`

**Interfaces:**
- Consumes: legacy sources read in place from `$LEGACY_DIR/src/vhdl` (default `../Cellular_Automata_FPGA`); tests skip when the directory is absent.
- `tb_legacy_core.vhd` feeds `GRID_LINES_TOROIDAL_BUFFER` (and `GRID_LINES_BUFFER`) with the rows of a small grid (GRID_X 128, GRID_Y 64) as the legacy memory read path would, drives the toroidal halo inputs as the legacy write-back would, collects `CA_ENGINE` outputs for one generation and writes them to a text file.

- [ ] **Step 1:** Write failing tests `test_legacy_hodgepodge29`, `test_legacy_ghm29_moore`, `test_legacy_ap21` comparing one legacy generation with `ca_model.step` (AP with the corrected orientation, which the current legacy code implements) on random seeds.
- [ ] **Step 2:** Run `python3 -m pytest tests/legacy -q`; expected FAIL.
- [ ] **Step 3:** Implement the models and the testbench (GHDL `--std=08`, `-frelaxed`).
- [ ] **Step 4:** Run the tests; expected PASS, or a documented mismatch added to `docs/legacy_vhdl_findings.md` with the first differing cell.
- [ ] **Step 5:** Commit checkpoint: `test(legacy): GHDL co-simulation of the legacy core`.

### Task 23: Directed tests for the legacy findings

**Files:**
- Create: `tests/legacy/tb_finding_init.vhd`, `tests/legacy/tb_finding_writeback.vhd`, `tests/legacy/tb_finding_speed.vhd`, `tests/legacy/test_findings.py`
- Modify: `docs/legacy_vhdl_findings.md`

**Interfaces:**
- Each testbench prints `CONFIRMED` or `NOT_REPRODUCED` with the cycle and signal values.

- [ ] **Step 1:** Write the tests: `test_finding2_initializer_third_beat` (drop `APP_WDF_RDY` during `WRITING_3`; count accepted beats), `test_finding3_writeback_grant` (deassert the grant while `APP_RDY`/`APP_WDF_RDY` are low; count lost commands or duplicated beats), `test_finding1_speed_desync` (change `SPEED_SETTING` between the graphics and write-back end-of-frame events; compare the two `SELECTED_FRAME` bits).
- [ ] **Step 2:** Run `python3 -m pytest tests/legacy/test_findings.py -q`.
- [ ] **Step 3:** Update the status column of `docs/legacy_vhdl_findings.md` with each outcome and the evidence.
- [ ] **Step 4:** Commit checkpoint: `test(legacy): directed checks of documented findings`.

## Phase 8: Documentation

### Task 24: README, architecture and extension guide

**Files:**
- Modify: `README.md`
- Create: `docs/architecture.md`, `docs/adding_a_rule.md`, `docs/register_map.md`
- Test: `tests/test_docs.py`

- [ ] **Step 1:** Write failing `test_docs_reference_existing_files` (every path in backticks in the four documents exists) and `test_register_map_doc_matches_pkg` (offsets in `docs/register_map.md` equal `ca_regs_pkg.sv`).
- [ ] **Step 2:** Run `python3 -m pytest tests/test_docs.py -q`; expected FAIL.
- [ ] **Step 3:** Write the documents. `adding_a_rule.md` walks through a worked example (a "majority" rule): SV module, `rule_e` entry, `ca_engine` case arm, Python function, unit test, config.
- [ ] **Step 4:** Run the full suite `python3 -m pytest -q` and `make lint`; expected PASS.
- [ ] **Step 5:** Commit checkpoint: `docs: README, architecture, register map, rule guide`.
