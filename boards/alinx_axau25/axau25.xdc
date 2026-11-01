## ALINX AXAU25 (XCAU25P-2FFVB676I) pins used by build.tcl, from the ALINX user manuals
## ACAU25 core board V1.0 (2.3 clocks, 2.4 DDR4) and AXAU25 V1.0 (3.3 PCIe, 3.11 LEDs).
## UNVERIFIED against the hardware: compare with ALINX's own demo constraints (README.md).

## Configuration: 1.8 V bank 0, Micron MT25QU256 QSPI flash (x4), compressed bitstream so that
## the FPGA is configured soon enough after power-up for the host to enumerate the PCIe card.
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
## A faster configuration clock shortens the boot further; take the rate from ALINX's demo XDC.
# set_property BITSTREAM.CONFIG.CONFIGRATE <MHz> [current_design]

## PCIe (Gen3 x4 on GTY quad 224): 100 MHz reference clock from the slot (MGTREFCLK0_224) and
## PERST# (bank 65, 1.8 V). The lanes are placed by the XDMA IP from its GT quad setting.
set_property PACKAGE_PIN AB7 [get_ports pcie_refclk_clk_p]
set_property PACKAGE_PIN AB6 [get_ports pcie_refclk_clk_n]
create_clock -period 10.000 -name pcie_refclk [get_ports pcie_refclk_clk_p]
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS18 PULLUP true} [get_ports pcie_perstn]
set_false_path -from [get_ports pcie_perstn]

## 200 MHz system clock (SiT9121 LVDS oscillator on the core board, bank 65 at 1.8 V), the DDR4
## controller's reference. The internal 100 ohm termination assumes no resistor on the board.
set_property -dict {PACKAGE_PIN T24 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports sys_clk_200_clk_p]
set_property -dict {PACKAGE_PIN U24 IOSTANDARD LVDS DIFF_TERM_ADV TERM_100} [get_ports sys_clk_200_clk_n]

## User LEDs (active high): LED1 = DDR4 calibrated, LED2 = PCIe link up.
set_property -dict {PACKAGE_PIN W21  IOSTANDARD LVCMOS18} [get_ports led_ddr_calib]
set_property -dict {PACKAGE_PIN AC16 IOSTANDARD LVCMOS18} [get_ports led_pcie_link]
set_false_path -to [get_ports {led_ddr_calib led_pcie_link}]

## DDR4: one Micron MT40A512M16LY (x16) on bank 66. adr[14], adr[15] and adr[16] are WE_n,
## CAS_n and RAS_n. The manual's PL_DDR4_PAR (L24) is not used (parity off).
set_property PACKAGE_PIN G25 [get_ports {c0_ddr4_adr[0]}]
set_property PACKAGE_PIN M26 [get_ports {c0_ddr4_adr[1]}]
set_property PACKAGE_PIN L25 [get_ports {c0_ddr4_adr[2]}]
set_property PACKAGE_PIN E26 [get_ports {c0_ddr4_adr[3]}]
set_property PACKAGE_PIN M25 [get_ports {c0_ddr4_adr[4]}]
set_property PACKAGE_PIN F22 [get_ports {c0_ddr4_adr[5]}]
set_property PACKAGE_PIN H26 [get_ports {c0_ddr4_adr[6]}]
set_property PACKAGE_PIN F24 [get_ports {c0_ddr4_adr[7]}]
set_property PACKAGE_PIN G26 [get_ports {c0_ddr4_adr[8]}]
set_property PACKAGE_PIN J23 [get_ports {c0_ddr4_adr[9]}]
set_property PACKAGE_PIN J25 [get_ports {c0_ddr4_adr[10]}]
set_property PACKAGE_PIN J24 [get_ports {c0_ddr4_adr[11]}]
set_property PACKAGE_PIN F25 [get_ports {c0_ddr4_adr[12]}]
set_property PACKAGE_PIN H24 [get_ports {c0_ddr4_adr[13]}]
set_property PACKAGE_PIN K26 [get_ports {c0_ddr4_adr[14]}]
set_property PACKAGE_PIN H22 [get_ports {c0_ddr4_adr[15]}]
set_property PACKAGE_PIN H21 [get_ports {c0_ddr4_adr[16]}]
set_property PACKAGE_PIN K25 [get_ports c0_ddr4_act_n]
set_property PACKAGE_PIN J26 [get_ports {c0_ddr4_ba[0]}]
set_property PACKAGE_PIN G22 [get_ports {c0_ddr4_ba[1]}]
set_property PACKAGE_PIN L22 [get_ports {c0_ddr4_bg[0]}]
set_property PACKAGE_PIN L23 [get_ports {c0_ddr4_cke[0]}]
set_property PACKAGE_PIN H23 [get_ports {c0_ddr4_cs_n[0]}]
set_property PACKAGE_PIN M24 [get_ports {c0_ddr4_odt[0]}]
set_property PACKAGE_PIN K22 [get_ports {c0_ddr4_ck_t[0]}]
set_property PACKAGE_PIN K23 [get_ports {c0_ddr4_ck_c[0]}]
set_property PACKAGE_PIN G24 [get_ports c0_ddr4_reset_n]
set_property PACKAGE_PIN E25 [get_ports {c0_ddr4_dm_n[0]}]
set_property PACKAGE_PIN L18 [get_ports {c0_ddr4_dm_n[1]}]
set_property PACKAGE_PIN F23 [get_ports {c0_ddr4_dq[0]}]
set_property PACKAGE_PIN D25 [get_ports {c0_ddr4_dq[1]}]
set_property PACKAGE_PIN E23 [get_ports {c0_ddr4_dq[2]}]
set_property PACKAGE_PIN B26 [get_ports {c0_ddr4_dq[3]}]
set_property PACKAGE_PIN D24 [get_ports {c0_ddr4_dq[4]}]
set_property PACKAGE_PIN D26 [get_ports {c0_ddr4_dq[5]}]
set_property PACKAGE_PIN B25 [get_ports {c0_ddr4_dq[6]}]
set_property PACKAGE_PIN C26 [get_ports {c0_ddr4_dq[7]}]
set_property PACKAGE_PIN M20 [get_ports {c0_ddr4_dq[8]}]
set_property PACKAGE_PIN J20 [get_ports {c0_ddr4_dq[9]}]
set_property PACKAGE_PIN J19 [get_ports {c0_ddr4_dq[10]}]
set_property PACKAGE_PIN M21 [get_ports {c0_ddr4_dq[11]}]
set_property PACKAGE_PIN L20 [get_ports {c0_ddr4_dq[12]}]
set_property PACKAGE_PIN J21 [get_ports {c0_ddr4_dq[13]}]
set_property PACKAGE_PIN K20 [get_ports {c0_ddr4_dq[14]}]
set_property PACKAGE_PIN K21 [get_ports {c0_ddr4_dq[15]}]
set_property PACKAGE_PIN D23 [get_ports {c0_ddr4_dqs_t[0]}]
set_property PACKAGE_PIN C24 [get_ports {c0_ddr4_dqs_c[0]}]
set_property PACKAGE_PIN M19 [get_ports {c0_ddr4_dqs_t[1]}]
set_property PACKAGE_PIN L19 [get_ports {c0_ddr4_dqs_c[1]}]

## DDR4 I/O standards (the DDR4 IP's defaults, repeated so that this file is complete).
set_property IOSTANDARD SSTL12_DCI [get_ports {c0_ddr4_adr[*] c0_ddr4_act_n c0_ddr4_ba[*] c0_ddr4_bg[*] c0_ddr4_cke[*] c0_ddr4_cs_n[*] c0_ddr4_odt[*]}]
set_property IOSTANDARD DIFF_SSTL12_DCI [get_ports {c0_ddr4_ck_t[*] c0_ddr4_ck_c[*]}]
set_property IOSTANDARD LVCMOS12 [get_ports c0_ddr4_reset_n]
set_property IOSTANDARD POD12_DCI [get_ports {c0_ddr4_dq[*] c0_ddr4_dm_n[*]}]
set_property IOSTANDARD DIFF_POD12_DCI [get_ports {c0_ddr4_dqs_t[*] c0_ddr4_dqs_c[*]}]
