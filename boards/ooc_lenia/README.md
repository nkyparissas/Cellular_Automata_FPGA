# Out-of-context timing of the Lenia datapath

`ooc_lenia.tcl` synthesises, places and routes the Lenia datapath (the sliding window and `rtl/rules/ca_rule_lenia.sv`, wrapped with registered inputs and outputs in `ooc_lenia_top.sv`) out of context on the Artix-7 100T (`xc7a100tcsg324-1`), with the engine clock at 200 MHz and the growth-table write port at 100 MHz (`ooc_lenia.xdc`). It checks the 200 MHz target of the Lenia design (spec Section 9.7) before a full board build.

```
vivado -mode batch -source boards/ooc_lenia/ooc_lenia.tcl                 # N = 27, 16-bit cells
vivado -mode batch -source boards/ooc_lenia/ooc_lenia.tcl -tclargs 37 16  # Hydrogeminium window
```

The reports land in `build/ooc_lenia/` (`timing.rpt`, `utilization.rpt`). The script has not been run yet (no Vivado in the development environment), so expect to adjust it for your Vivado version. A negative slack points to the stage to deepen: the class pre-add trees, the multipliers, the adder tree over the products, or the shift; the rule's latency may grow freely, since the framework aligns the valid bit.

## Open-source flow (openXC7)

`run_openxc7.sh` takes the same datapath through Yosys (OSS CAD Suite with the yosys-slang plugin, `synth_xilinx`) and the nextpnr-xilinx of [openXC7](https://github.com/openXC7) on the same part, without Vivado:

```
boards/ooc_lenia/run_openxc7.sh            # N = 27, 16-bit cells, 200 MHz
boards/ooc_lenia/run_openxc7.sh 37 16 200  # Hydrogeminium window
```

nextpnr-xilinx is taken from `$OPENXC7/bin` (default `~/openxc7`, the unpacked release); do not source the release's environment script in a shell that also runs Verilator, since it points `VERILATOR_ROOT` at a Verilator the release does not contain. The harness `lenia_pnr_top.sv` needs only three pins (`lenia_pnr_nexys4ddr.xdc`): an LFSR and a rule-90 scrambler feed the window (a plain shift register would let synthesis merge window registers), the outputs are folded into one LED, and the reset passes through `ca_reset_sync` as in the core, so that its fan-out is timed. The script uses the static placer, because the default heap placer cannot legalise one carry chain of the 27 x 27 build; `PNR_ARGS` replaces the placer options and `SKIP_SYNTH=1` places an existing netlist again.

The reports land in `build/openxc7_lenia_n<N>_c<CW>/` (`utilization.txt`, `nextpnr.log`, `report.json` with the detailed critical path), together with three pictures drawn by `plot_pnr.py`: the floorplan coloured by function, the critical path on the die, and the routing use per tile. The flow contains no Xilinx IP and nextpnr's timing model is an estimate, so Vivado remains the reference for sign-off.

Results on 2026-11-01 (16-bit cells, 6-bit weights, 12-bit table index, 200 MHz target):

| Window | Routed Fmax | LUT slots | Flip-flops | CARRY4 | DSP48E1 | RAMB36 |
|---|---|---|---|---|---|---|
| 27 x 27 (C = 69) | 264.9 MHz | 23,519 (19 %) | 21,000 (17 %) | 2,805 (18 %) | 69 (29 %) | 4 |
| 37 x 37 (C = 121) | 228.5 MHz | 43,956 (35 %) | 39,396 (31 %) | 5,322 (34 %) | 121 (50 %) | 4 |

In both builds the worst path runs from a register of a class pre-add tree to the carry chain of its next level, with 2 to 2.5 ns of routing between them. Before the weight chain's shift enable was made local to each class, that enable limited the builds to 223.6 MHz (27 x 27) and 163.5 MHz (37 x 37). The 37 x 37 result uses `PNR_ARGS="--placer static --seed 2"`: with the default seed the router had not converged after an hour, whereas seed 2 routed in under five minutes. The harness excludes the line buffer, which takes 2 RAMB36 per line-buffer row (N + 1 rows) with the 128-bit write port.
