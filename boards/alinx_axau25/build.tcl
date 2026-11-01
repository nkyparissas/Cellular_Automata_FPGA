# ALINX AXAU25 PCIe card (Artix UltraScale+ XCAU25P-2FFVB676I, PCIe Gen3 x4, 1 GB DDR4 x16):
# the CA core as a PCIe accelerator, after boards/xdma_template (XDMA in memory-mapped mode).
# UNVERIFIED: written from the ALINX user manuals (ACAU25 and AXAU25, V1.0) without the board
# and without Vivado; README.md lists what to check when the board arrives.
#
# Usage (from the repository root; Vivado ML Standard, the free edition, supports the XCAU25P):
#   vivado -mode batch -source boards/alinx_axau25/build.tcl -tclargs [config [core_aclk_mhz]]
# config:        experiment configuration (default configs/lenia_orbium.json)
# core_aclk_mhz: 0 (default) runs the core's AXI side on the XDMA user clock (250 MHz); a value
#                such as 125 gives it a clock of its own from the clocking wizard, with the
#                SmartConnects crossing to it, in case 250 MHz does not meet timing.
# Outputs in build/alinx_axau25/: the Vivado project, timing.rpt, utilization.rpt and the QSPI
# flash image ca_axau25.mcs; the bitstream stays in the project's impl_1 run directory.
#
# Data paths:
#   host <-> XDMA M_AXI (H2C/C2H DMA)  -> smc_mem S00 -> DDR4 (seed upload, frame download)
#   CA core m_axi (reader + writer)    -> smc_mem S01 -> DDR4 (passes)
#   host <-> XDMA M_AXI_LITE (BAR 0)   -> smc_lite    -> CA core s_axil (registers, FRAME_REQ)
# Clocks: PCIe reference clock (100 MHz, slot) -> XDMA, whose user clock drives the AXI side and
# the clocking wizard for eclk; 200 MHz board oscillator -> DDR4 controller.
# LEDs: LED1 = DDR4 calibrated, LED2 = PCIe link up.

set board_dir [file normalize [file dirname [info script]]]
set root      [file normalize $board_dir/../..]
set config        [expr {$argc > 0 ? [lindex $argv 0] : "configs/lenia_orbium.json"}]
set core_aclk_mhz [expr {$argc > 1 ? [lindex $argv 1] : 0}]
set part          xcau25p-ffvb676-2-i
set eclk_mhz      200
set data_w        128                ;# = XDMA Gen3 x4 and DDR4 x16 AXI widths: no width converters
set buf1_addr     0x10000000         ;# second frame buffer (first at 0x0) inside the 1 GB DDR4
set ddr_part      MT40A512M16LY-062E ;# Micron 8 Gb x16 (ACAU25 manual 2.4: MT40A512M16LY-062EIT)
set gt_quad       GTY_Quad_224       ;# PCIe lanes and reference clock (AXAU25 manual, Table 3.3.1)
set out           $root/build/alinx_axau25
set own_aclk      [expr {$core_aclk_mhz > 0}]

# ------------------------------------------------------------- sources
file mkdir $out
exec python3 $root/tools/gen_cfg.py --config $root/$config --data-w $data_w --out $out/ca_cfg.vh
exec python3 $root/tools/gen_filelist.py --top ca_core_flat --out $out/files.f

create_project ca_axau25 $out/vivado -part $part -force
set fh [open $out/files.f]
foreach f [split [string trim [read $fh]] "\n"] { add_files -norecurse $root/$f }
close $fh
add_files -norecurse $root/boards/xdma_template/ca_core_xdma.v   ;# module-reference top: Verilog (UG994)
set_property include_dirs [list $out $root/third_party/axi/include $root/third_party/common_cells/include] [current_fileset]
add_files -fileset constrs_1 -norecurse $board_dir/axau25.xdc
update_compile_order -fileset sources_1

# ------------------------------------------------------------ block design
create_bd_design ca_axau25_bd

# PCIe: reference clock through the GT buffer, PERST# and four lanes from the slot.
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 pcie_refclk
set_property CONFIG.FREQ_HZ 100000000 [get_bd_intf_ports pcie_refclk]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:pcie_7x_mgt_rtl:1.0 pcie_mgt
create_bd_port -dir I -type rst pcie_perstn
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports pcie_perstn]
create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf refclk_buf
set_property CONFIG.C_BUF_TYPE IBUFDSGTE [get_bd_cells refclk_buf]
create_bd_cell -type ip -vlnv xilinx.com:ip:xdma xdma_0
set_property -dict [list \
  CONFIG.mode_selection {Advanced} \
  CONFIG.pl_link_cap_max_link_width {X4} \
  CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
  CONFIG.axi_data_width {128_bit} CONFIG.axisten_freq {250} \
  CONFIG.ref_clk_freq {100_MHz} \
  CONFIG.select_quad $gt_quad \
  CONFIG.xdma_axi_intf_mm {AXI_Memory_Mapped} \
  CONFIG.xdma_rnum_chnl {1} CONFIG.xdma_wnum_chnl {1} \
  CONFIG.axilite_master_en {true} CONFIG.axilite_master_size {64} CONFIG.axilite_master_scale {Kilobytes} \
  CONFIG.xdma_num_usr_irq {1}] [get_bd_cells xdma_0]
connect_bd_intf_net [get_bd_intf_ports pcie_refclk] [get_bd_intf_pins refclk_buf/CLK_IN_D]
connect_bd_net [get_bd_pins refclk_buf/IBUF_OUT] [get_bd_pins xdma_0/sys_clk_gt]
connect_bd_net [get_bd_pins refclk_buf/IBUF_DS_ODIV2] [get_bd_pins xdma_0/sys_clk]
connect_bd_net [get_bd_ports pcie_perstn] [get_bd_pins xdma_0/sys_rst_n]
connect_bd_intf_net [get_bd_intf_pins xdma_0/pcie_mgt] [get_bd_intf_ports pcie_mgt]

# DDR4: one x16 device at 2400 MT/s (833 ps), 200 MHz reference, 128-bit AXI4 slave. Its AXI
# reset follows the controller's user-clock reset and calibration.
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 sys_clk_200
set_property CONFIG.FREQ_HZ 200000000 [get_bd_intf_ports sys_clk_200]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddr4_rtl:1.0 c0_ddr4
create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4 ddr4_0
set_property -dict [list \
  CONFIG.C0.DDR4_MemoryType {Components} \
  CONFIG.C0.DDR4_MemoryPart $ddr_part \
  CONFIG.C0.DDR4_TimePeriod {833} \
  CONFIG.C0.DDR4_InputClockPeriod {5000} \
  CONFIG.C0.DDR4_DataWidth {16} \
  CONFIG.C0.DDR4_DataMask {DM_NO_DBI} \
  CONFIG.C0.DDR4_AxiSelection {true} \
  CONFIG.C0.DDR4_AxiDataWidth {128}] [get_bd_cells ddr4_0]
connect_bd_intf_net [get_bd_intf_ports sys_clk_200] [get_bd_intf_pins ddr4_0/C0_SYS_CLK]
connect_bd_intf_net [get_bd_intf_pins ddr4_0/C0_DDR4] [get_bd_intf_ports c0_ddr4]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant ddr_sys_rst
set_property CONFIG.CONST_VAL 0 [get_bd_cells ddr_sys_rst]
connect_bd_net [get_bd_pins ddr_sys_rst/dout] [get_bd_pins ddr4_0/sys_rst]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_ddr
set_property CONFIG.C_EXT_RESET_HIGH 1 [get_bd_cells rst_ddr]
connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk] [get_bd_pins rst_ddr/slowest_sync_clk]
connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk_sync_rst] [get_bd_pins rst_ddr/ext_reset_in]
connect_bd_net [get_bd_pins ddr4_0/c0_init_calib_complete] [get_bd_pins rst_ddr/dcm_locked]
connect_bd_net [get_bd_pins rst_ddr/peripheral_aresetn] [get_bd_pins ddr4_0/c0_ddr4_aresetn]

# Status LEDs.
create_bd_port -dir O led_ddr_calib
create_bd_port -dir O led_pcie_link
connect_bd_net [get_bd_pins ddr4_0/c0_init_calib_complete] [get_bd_ports led_ddr_calib]
connect_bd_net [get_bd_pins xdma_0/user_lnk_up] [get_bd_ports led_pcie_link]

# Engine clock (and, optionally, the core's AXI clock) from the XDMA user clock.
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_wiz
set clk_cfg [list CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $eclk_mhz CONFIG.USE_RESET {false}]
if {$own_aclk} {
  lappend clk_cfg CONFIG.CLKOUT2_USED {true} CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $core_aclk_mhz
}
set_property -dict $clk_cfg [get_bd_cells clk_wiz]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_eclk

create_bd_cell -type module -reference ca_core_xdma ca_core
set_property -dict [list CONFIG.BUF1 $buf1_addr] [get_bd_cells ca_core]

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smc_mem
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_CLKS [expr {2 + $own_aclk}]] [get_bd_cells smc_mem]
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smc_lite
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_CLKS [expr {1 + $own_aclk}]] [get_bd_cells smc_lite]

connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins smc_mem/aclk] [get_bd_pins smc_lite/aclk] \
  [get_bd_pins clk_wiz/clk_in1]
connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins smc_mem/aresetn] [get_bd_pins smc_lite/aresetn] \
  [get_bd_pins rst_eclk/ext_reset_in]
connect_bd_net [get_bd_pins clk_wiz/clk_out1] [get_bd_pins ca_core/eclk] [get_bd_pins rst_eclk/slowest_sync_clk]
connect_bd_net [get_bd_pins clk_wiz/locked] [get_bd_pins rst_eclk/dcm_locked]
connect_bd_net [get_bd_pins rst_eclk/peripheral_aresetn] [get_bd_pins ca_core/eresetn]
connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk] [get_bd_pins smc_mem/aclk1]
if {$own_aclk} {
  create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_aclk
  connect_bd_net [get_bd_pins clk_wiz/clk_out2] [get_bd_pins ca_core/aclk] [get_bd_pins smc_mem/aclk2] \
    [get_bd_pins smc_lite/aclk1] [get_bd_pins rst_aclk/slowest_sync_clk]
  connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins rst_aclk/ext_reset_in]
  connect_bd_net [get_bd_pins clk_wiz/locked] [get_bd_pins rst_aclk/dcm_locked]
  connect_bd_net [get_bd_pins rst_aclk/peripheral_aresetn] [get_bd_pins ca_core/aresetn]
} else {
  connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins ca_core/aclk]
  connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins ca_core/aresetn]
}
connect_bd_net [get_bd_pins ca_core/pass_done] [get_bd_pins xdma_0/usr_irq_req]

connect_bd_intf_net [get_bd_intf_pins xdma_0/M_AXI]      [get_bd_intf_pins smc_mem/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ca_core/m_axi]     [get_bd_intf_pins smc_mem/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins smc_mem/M00_AXI]   [get_bd_intf_pins ddr4_0/C0_DDR4_S_AXI]
connect_bd_intf_net [get_bd_intf_pins xdma_0/M_AXI_LITE] [get_bd_intf_pins smc_lite/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smc_lite/M00_AXI]  [get_bd_intf_pins ca_core/s_axil]

assign_bd_address
set_property offset 0x00000000 [get_bd_addr_segs {xdma_0/M_AXI/SEG_ddr4_0_C0_DDR4_ADDRESS_BLOCK}]
set_property offset 0x00000000 [get_bd_addr_segs {ca_core/m_axi/SEG_ddr4_0_C0_DDR4_ADDRESS_BLOCK}]
set_property offset 0x00000000 [get_bd_addr_segs {xdma_0/M_AXI_LITE/SEG_ca_core_reg0}]
# The register map spans 64 KB (Lenia GROWTH_TABLE window at 0x8000); a smaller range would drop table writes.
set_property range 64K [get_bd_addr_segs {xdma_0/M_AXI_LITE/SEG_ca_core_reg0}]

validate_bd_design
save_bd_design
make_wrapper -files [get_files ca_axau25_bd.bd] -top
add_files -norecurse $out/vivado/ca_axau25.gen/sources_1/bd/ca_axau25_bd/hdl/ca_axau25_bd_wrapper.v
set_property top ca_axau25_bd_wrapper [current_fileset]

# The core's clock domains meet only through its synchronisers and dual-clock FIFOs/RAMs, and
# the XDMA and DDR4 domains only through the SmartConnects (which constrain their own crossings),
# so the clocks of the core are asynchronous groups.
set bd ca_axau25_bd_i
set groups "-group \[get_clocks -of_objects \[get_pins $bd/xdma_0/axi_aclk\]\] \\\n  -group \[get_clocks -of_objects \[get_pins $bd/clk_wiz/clk_out1\]\]"
if {$own_aclk} {
  append groups " \\\n  -group \[get_clocks -of_objects \[get_pins $bd/clk_wiz/clk_out2\]\]"
}
set fh [open $out/clocks.xdc w]
puts $fh "# Written by boards/alinx_axau25/build.tcl.\nset_clock_groups -asynchronous \\\n  $groups"
close $fh
add_files -fileset constrs_1 -norecurse $out/clocks.xdc
set_property USED_IN_SYNTHESIS false [get_files $out/clocks.xdc]   ;# the IP clocks exist after linking

# ---------------------------------------------- synthesis to flash image
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
open_run impl_1
report_timing_summary -file $out/timing.rpt
report_utilization -file $out/utilization.rpt
set bit $out/vivado/ca_axau25.runs/impl_1/ca_axau25_bd_wrapper.bit
write_cfgmem -format mcs -size 32 -interface SPIx4 -loadbit "up 0x00000000 $bit" -force -file $out/ca_axau25.mcs
puts "Bitstream $bit, flash image $out/ca_axau25.mcs (Micron MT25QU256, mt25qu256-spi-x1_x2_x4)."
puts "Check timing.rpt: with negative slack on the XDMA user clock, rebuild with core_aclk_mhz 125."
