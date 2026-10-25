# Adding a rule

A rule is one SystemVerilog module behind a fixed interface, one entry in two enumerations, one `case` arm, and one Python function in the golden model. The framework handles the window, the boundaries, the memory traffic and the valid alignment. This guide adds a "majority" rule as a worked example: a cell becomes `ALIVE` when at least `T` cells of its masked neighbourhood are non-zero, and 0 otherwise.

## 1. Golden model first

Add the parameters to `PARAM_INDEX` and the semantics to `_apply` in `model/ca_model/rules.py`:

```python
PARAM_INDEX["majority"] = {"T": 0, "ALIVE": 1}

def majority_cells(N, T, ALIVE):
    return np.where(np.asarray(N) >= T, ALIVE, 0)

# in _apply():
if rule == "majority":
    N = stats((values > 0).astype(np.int64), mask)
    return majority_cells(N, params[0], params[1])
```

Then add hand-computed cases to `tests/model/test_rules.py` (and a `CASES` entry so that `test_step_equals_window_reference` covers the new rule in every boundary mode). Run `python3 -m pytest tests/model -q`.

## 2. RTL module

Copy `rtl/rules/ca_rule_interval.sv` to a new file and keep its port list unchanged:

```systemverilog
module ca_rule_majority #(
  parameter int unsigned    N      = 29,
  parameter int unsigned    CELL_W = 8,
  parameter logic [N*N-1:0] MASK   = '1
) (
  input  logic                            clk_i,
  input  logic                            rst_ni,
  input  logic [N-1:0][N-1:0][CELL_W-1:0] win_i,     // win_i[i][j]: row y-r+i, column x-r+j
  input  logic                            vld_i,
  input  ca_pkg::rule_params_t            params_i,
  output logic [CELL_W-1:0]               cell_o,
  output logic                            vld_o
);
```

Build the per-cell terms with a `generate` loop over `MASK` (masked-off cells become constant zeros and disappear in synthesis), sum them with `rtl/arith/ca_adder_tree.sv` (latency `ca_pkg::tree_lat(N*N)`), register the decision, and delay `vld_i` by the total latency with `rtl/common/ca_valid_delay.sv`. Any latency is allowed: the rule owns its valid pipeline, and the window, line buffer and packer do not care. If the rule needs the centre cell, take `win_i[(N-1)/2][(N-1)/2]` and delay it with `rtl/common/ca_delay.sv` to the cycle where it is used (see `rtl/rules/ca_rule_ghm.sv`). Divisions can use `rtl/arith/ca_div_pipe.sv` (one quotient bit per stage).

## 3. Register the rule

* `rtl/pkg/ca_pkg.sv`: add `RULE_MAJORITY = 4'd3` to `rule_e` and parameter index constants if useful.
* `rtl/engine/ca_engine.sv`: add a `case` arm instantiating the new module.
* `tools/gen_cfg.py` (`RULE_ID`), `host/ca_host/simdev.py` (`RULE_ID`) and `host/ca_host/controller.py` (`RULES`): add the name with the same number.
* `rtl/ctrl/ca_regs.sv` needs no change: `CORE_CFG` reports the rule number.

## 4. Tests

* `tests/unit/test_engine.py`: add the rule to `RULES`, `random_params` and `random_cell`; the existing test then compares the RTL with the model on random windows for several neighbourhood sizes and cell widths.
* `tests/core/test_core.py`: add the rule to `RULE_CELL` so that the integration matrix runs it in all four boundary modes.
* `make lint`: lint the engine at full size by adding a small wrapper to `LINT_TOPS` (see `sim/tb/lint_engine_ghm.sv`).

## 5. Configuration

Create a configuration file next to the existing ones in `configs/`, for example:

```json
{"name": "majority9", "grid": [1920, 1080], "cell_w": 4, "nbh": 9, "boundary": "toroidal",
 "rule": "majority", "mask": "moore", "params": {"T": 41, "ALIVE": 1},
 "seed": "data/seeds/ap_random.bmp", "seed_mode": "binary", "seed_value": 1, "palette": "legacy4_windows"}
```

`python3 -m ca_model.run --config <file> --gens 100` shows the model's behaviour; `python3 tools/run_rtl_experiment.py --config <file> --gens 3 --dump-every 1` runs the RTL at full size and compares it with the model.

## Notes towards Lenia

A fixed-point Lenia rule fits the same interface: the kernel becomes a weighted sum (constant multipliers, or radius-grouped pre-adds to share DSPs), the growth function a lookup table indexed by the quantised potential, and the update `clip(c + dt * G(u))` a final pipeline stage. Wider cells (for example 16-bit fixed point) need no framework change: `CELL_W` is a parameter throughout the RTL, and the golden model, frame packing (`model/ca_model/grids.py`), configuration tools and host handle 1-, 2-, 4-, 8-, 16- and 32-bit cells (`tests/core/test_core.py::test_core_16bit_cells` runs 16-bit cells end to end). Seeds are 8-bit images and the legacy display palettes exist for 4- and 8-bit cells only; the `gray` palette works for any width. Kernels that should change at run time can take their weights from additional RULE_PARAM registers or from a small RAM loaded through AXI4-Lite.
