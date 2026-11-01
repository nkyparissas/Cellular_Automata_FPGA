# ALINX AXAU25 (PCIe card)

The ALINX AXAU25 is a PCIe Gen3 x4 card that carries an AMD Artix UltraScale+ XCAU25P-2FFVB676I on the ACAU25 core board, with 1 GB of DDR4 and a 12 V supply. This folder builds the CA core as a PCIe accelerator for it, after `boards/xdma_template`: the host moves frames by DMA through the board's DDR4 and controls the core through the XDMA AXI-Lite BAR (`docs/figures/system_pcie.png` shows the system).

**Status: unverified.** Everything here was written from the ALINX user manuals (ACAU25 core board V1.0 and AXAU25 V1.0, both of November 2025) without the board and without Vivado. `tests/test_boards_static.py` checks that the constraints place every exported pin exactly once on the pin the manuals give, and that `build.tcl` runs through a Tcl interpreter with stub Vivado commands for both clocking options; the Vivado flow and the hardware have not been tried.

## Files

* `build.tcl` - creates the Vivado project and block design (XDMA, DDR4 controller, two SmartConnects, clocking wizard, the core through `boards/xdma_template/ca_core_xdma.v`), then synthesises, implements and writes the bitstream and the QSPI flash image.
* `axau25.xdc` - pins, I/O standards and configuration settings; `build.tcl` adds the clock groups (`build/alinx_axau25/clocks.xdc`), which depend on the clocking option.

## Board facts used

| Item | Value | Manual |
|---|---|---|
| FPGA | XCAU25P-2FFVB676I (Vivado part `xcau25p-ffvb676-2-i`): 141k LUTs, 282k flip-flops, 300 RAMB36, 1,200 DSP slices, 12 GTY | ACAU25 2.2 |
| PCIe | Gen3 x4 edge connector on GTY quad 224 (lane 0 on the quad's channel 3); 100 MHz reference clock from the slot on MGTREFCLK0_224 (AB7/AB6); PERST# on T19 | AXAU25 3.3 |
| DDR4 | one Micron MT40A512M16LY-062EIT (8 Gb, x16) on bank 66, up to 2400 MT/s | ACAU25 2.4 |
| Clocks | 200 MHz LVDS oscillator on T24/U24 (bank 65), system and DDR4 reference; 156.25 MHz GTY reference on MGTREFCLK1_225 (T7/T6), not used here | ACAU25 2.3 |
| Flash | Micron MT25QU256 (256 Mb, 1.8 V) on the configuration pins | ACAU25 2.5 |
| I/O banks | 64 and 65 at 1.8 V (connectors, FMC, LEDs, keys, PERST#), 66 for the DDR4, 84 to 86 at 3.3 V | ACAU25 2.7, 2.8 |
| LEDs | LED1 on W21, LED2 on AC16, active high, 1.8 V | AXAU25 3.11 |
| Keys | KEY1 on N26, KEY2 on AA23, active low, 1.8 V (not used) | AXAU25 3.10 |
| UART | CP2102 USB-UART on a mini-USB port: FPGA receive A12, transmit A13, 3.3 V (not used) | AXAU25 3.5 |
| JTAG | 10-pin 2.54 mm header | AXAU25 3.8 |
| Power | 12 V adapter | AXAU25 3.12 |

## Design

* **PCIe**: XDMA in memory-mapped mode, Gen3 x4, 128-bit AXI at 250 MHz, one H2C and one C2H channel, a 64 KB AXI-Lite BAR for the registers, and `pass_done` as user interrupt 0.
* **DDR4**: the DDR4 controller IP for the MT40A512M16LY-062E at 2400 MT/s, referenced to the 200 MHz oscillator, with a 128-bit AXI4 slave on its 300 MHz user clock.
* **Data width**: the core's memory port is 128 bits wide, the width of both the XDMA and the DDR4 AXI ports, so the SmartConnects need no width converters, and the line buffer takes 2 RAMB36 per row (76 of the 300 for the 37 x 37 window).
* **Clocks**: the core's AXI side runs on the XDMA user clock (250 MHz) and the engine at 200 MHz from a clocking wizard on the same clock. If the AXI side misses 250 MHz, the second build argument gives it a clock of its own (for example 125 MHz).
* **Memory map**: frame buffers at 0x0000_0000 and 0x1000_0000 of the DDR4 (the host CLI's defaults); registers at 0x0 of BAR 0.
* **LEDs**: LED1 lights when the DDR4 is calibrated, LED2 when the PCIe link is up.

## Build

The free Vivado ML Standard edition supports the XCAU25P: AMD's "What's New in Vivado 2023.2" lists the XCAU20P and XCAU25P in both editions, and AMD support article 000036659 states that Vivado 2024.1 Standard supports all XC and XA Artix UltraScale+ devices. Use Vivado 2023.2 or later.

```
vivado -mode batch -source boards/alinx_axau25/build.tcl -tclargs configs/lenia_orbium.json        # core AXI side at 250 MHz
vivado -mode batch -source boards/alinx_axau25/build.tcl -tclargs configs/lenia_orbium.json 125    # own 125 MHz AXI clock
```

The outputs land in `build/alinx_axau25/`: the Vivado project, `timing.rpt`, `utilization.rpt` and the flash image `ca_axau25.mcs`; the bitstream is `vivado/ca_axau25.runs/impl_1/ca_axau25_bd_wrapper.bit`. The yosys syntheses of the full core for the Artix-7 (about 14k to 16k LUTs, and 121 DSP slices for the 37 x 37 Lenia window) suggest that every configuration in `configs/` fits the XCAU25P comfortably; the host must use the configuration the bitstream was built with.

## Programming and first boot

* **Power**: the manual names the 12 V adapter as the board's supply and does not say that the card draws power from the slot, so connect the adapter also when the card sits in the PC.
* **JTAG**: the 10-pin header needs a Xilinx-compatible cable (AMD Platform Cable USB II, Digilent JTAG-HS2 or HS3, or the ALINX downloader).
* **Boot from flash**: the host enumerates PCIe devices shortly after power-up, so the FPGA must be configured by then. In the Vivado Hardware Manager, add the configuration memory `mt25qu256-spi-x1_x2_x4`, program `ca_axau25.mcs`, and power-cycle the PC with the board's adapter connected. The bitstream is compressed and loads over SPI x4 to keep configuration short; a faster configuration clock (`BITSTREAM.CONFIG.CONFIGRATE` in `axau25.xdc`) shortens it further. After a JTAG download alone, a warm reboot of the PC (the board keeps its power from the adapter) lets the host enumerate it.

## Host

Build and load the XDMA driver from Xilinx `dma_ip_drivers`. `lspci -d 10ee:` should show the card (device ID 9034, the XDMA default for Gen3 x4), and the driver creates `/dev/xdma0_user` (registers), `/dev/xdma0_h2c_0` and `/dev/xdma0_c2h_0` (DMA to and from the DDR4). Then run the configuration the bitstream was built with:

```
PYTHONPATH=host:model python3 -m ca_host.cli --transport xdma --device /dev/xdma0 --config configs/lenia_orbium.json
PYTHONPATH=host:model python3 -m ca_host.cli --transport xdma --device /dev/xdma0 --config configs/lenia_orbium.json --frames 10 --headless --out frames
```

## When the board arrives

1. **Compare with ALINX's demo projects** (PCIe/XDMA and DDR4) and update `build.tcl` and `axau25.xdc` where they differ:
   * the 200 MHz clock's I/O standard and whether the board terminates it (`DIFF_TERM_ADV`);
   * the DDR4 IP settings (memory part, CAS latency, reference clock);
   * the XDMA PCIe block location and GT quad;
   * the configuration rate;
   * PERST#'s I/O standard and pull-up;
   * the bank voltages: 1.8 V on banks 64 and 65, 1.2 V on bank 66 for the DDR4.
2. **Build.** IP property names can change between Vivado versions; a failing `set_property` names the property to fix.
3. **Standalone test** (12 V, no PC): program over JTAG; LED1 should light (DDR4 calibrated).
4. **In the PC**: program the flash, install the card in a x4 or wider slot with the adapter connected, and boot. LED2 should light, and `sudo lspci -vv -d 10ee:` should report `LnkSta: Speed 8GT/s, Width x4`.
5. **Run** the host CLI and look at the first frames.
6. **Timing**: if `timing.rpt` shows negative slack on the XDMA user clock, rebuild with `core_aclk_mhz` 125.
