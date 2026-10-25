# Digilent Nexys 4 DDR (display variant)

This folder contains only what is specific to the board: the top level (`top_nexys4ddr.sv`: two clocking wizards as in the legacy design, one for the 200/325 MHz MIG clocks and one for the 148.5 MHz pixel clock, DDR2 MIG with an AXI4 slave, 4-bit VGA, UART, buttons, LEDs), pin constraints, the MIG project and a Vivado build script. The design itself is `rtl/top/ca_display_system.sv`.

**Status: unverified on hardware and in Vivado.** The RTL around the board top is simulated (`tests/sim/test_uart_board.py`) and the top level lints against stub IP modules (`make lint-boards`), but `build.tcl` and `ip/mig_ddr2_axi.prj` (the legacy DDR2 settings with the AXI4 interface enabled: 128-bit data, 4-bit ID, 27-bit address) were written without Vivado.

## Build

```
vivado -mode batch -source boards/nexys4ddr/build.tcl -tclargs configs/hodgepodge29.json
```

The configuration file chooses the rule, neighbourhood, boundary mode and grid; the grid must be 1920x1080 because the display shows it at 1080p60 (148.5 MHz pixel clock). The bitstream lands in `build/nexys4ddr/`.

## Use

* LEDs: 0 DDR2 calibrated, 1 MIG clock locked, 2 toggles on every pass, 3 display underflow.
* Seed upload and control over the USB-UART at 2 Mbaud: `python3 -m ca_host.cli --transport uart --port /dev/ttyUSB1 --config configs/hodgepodge29.json` loads the seed and starts the run, then takes commands on stdin: `+`/`-` faster/slower, `p` pause/resume, `s` snapshot (read under PAUSE, so the image is one consistent generation; a 1920x1080 8-bit frame takes about 10 s at 2 Mbaud), `q` quit and leave the board running, `x` stop and quit. The display requests the passes, so the host never waits for the core to go idle (`docs/register_map.md`, consumer-paced cores).
* Buttons: up = one generation per displayed frame (60 per second), down = one generation per second (the reset default), left = pause/resume. Pausing keeps the display running on the current generation; the host can then read it back over the UART.

Memory map: buffer 0 at 0x0000_0000, buffer 1 at 0x0100_0000. In the legacy cylindrical and rectangular modes the host writes the seed into both buffers.
