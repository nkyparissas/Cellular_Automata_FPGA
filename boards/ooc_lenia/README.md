# Out-of-context timing of the Lenia datapath

`ooc_lenia.tcl` synthesises, places and routes the Lenia datapath (the sliding window and `rtl/rules/ca_rule_lenia.sv`, wrapped with registered inputs and outputs in `ooc_lenia_top.sv`) out of context on the Artix-7 100T (`xc7a100tcsg324-1`), with the engine clock at 200 MHz and the growth-table write port at 100 MHz (`ooc_lenia.xdc`). It checks the 200 MHz target of the Lenia design (spec Section 9.7) before a full board build.

```
vivado -mode batch -source boards/ooc_lenia/ooc_lenia.tcl                 # N = 27, 16-bit cells
vivado -mode batch -source boards/ooc_lenia/ooc_lenia.tcl -tclargs 37 16  # Hydrogeminium window
```

The reports land in `build/ooc_lenia/` (`timing.rpt`, `utilization.rpt`). The script has not been run yet (no Vivado in the development environment), so expect to adjust it for your Vivado version. A negative slack points to the stage to deepen: the class pre-add trees, the multipliers, the adder tree over the products, or the shift; the rule's latency may grow freely, since the framework aligns the valid bit.
