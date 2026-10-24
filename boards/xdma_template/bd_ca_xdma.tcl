# Generic Vivado block design: PCIe XDMA (memory-mapped) + DDR controller + CA core.
# UNVERIFIED TEMPLATE: written without Vivado and without a target board. Adapt the
# variables below, then run from the repository root:
#   vivado -mode batch -source boards/xdma_template/bd_ca_xdma.tcl
#
# Data paths:
#   host <-> XDMA M_AXI (H2C/C2H DMA)  -> smc_mem S00 -> DDR      (seed upload, frame download)
#   CA core m_axi (reader + writer)    -> smc_mem S01 -> DDR      (passes)
#   host <-> XDMA M_AXI_LITE (BAR 0)   -> smc_lite    -> CA core s_axil (registers, doorbell)
# Address map: DDR at 0x0 in the XDMA M_AXI space, so the C2H/H2C file offset used by
# the host equals the DDR address; core registers at 0x0 of the AXI-Lite BAR.

# ---------------------------------------------------------------- adapt
set part          "xcu50-fsvh2104-2-e"           ;# example device
set board_part    ""                             ;# e.g. a board file part; empty: no board automation
set pcie_lanes    "X8"
set pcie_gen      "8.0_GT/s"                     ;# Gen3
set ddr_interface "ddr4_sdram"                   ;# board interface name used by board automation
set eclk_mhz      200                            ;# engine clock
set grid_x        1920
set grid_y        1080
set config        "configs/hodgepodge29.json"    ;# grid_x/grid_y must match this file
set data_w        512                            ;# AXI data width of the core's memory port
set buf1_addr     0x10000000                     ;# second frame buffer (first one at 0x0)

# ------------------------------------------------------------- sources
set root [file normalize [file dirname [info script]]/../..]
set out  $root/build/xdma_template
file mkdir $out
exec python3 $root/tools/gen_cfg.py --config $root/$config --data-w $data_w --out $out/ca_cfg.svh
exec python3 $root/tools/gen_filelist.py --top ca_core_flat --out $out/files.f

create_project ca_xdma $out/vivado -part $part -force
if {$board_part ne ""} { set_property board_part $board_part [current_project] }
set fh [open $out/files.f]
foreach f [split [string trim [read $fh]] "\n"] { add_files -norecurse $root/$f }
close $fh
add_files -norecurse $root/boards/xdma_template/ca_core_xdma.sv
set_property include_dirs [list $out $root/third_party/axi/include $root/third_party/common_cells/include] [current_fileset]
update_compile_order -fileset sources_1

# ------------------------------------------------------------ block design
create_bd_design ca_xdma_bd

create_bd_cell -type ip -vlnv xilinx.com:ip:xdma xdma_0
set_property -dict [list \
  CONFIG.mode_selection {Advanced} \
  CONFIG.pl_link_cap_max_link_width $pcie_lanes \
  CONFIG.pl_link_cap_max_link_speed $pcie_gen \
  CONFIG.xdma_axi_intf_mm {AXI_Memory_Mapped} \
  CONFIG.xdma_rnum_chnl {1} CONFIG.xdma_wnum_chnl {1} \
  CONFIG.axilite_master_en {true} CONFIG.axilite_master_size {64} CONFIG.axilite_master_scale {Kilobytes} \
  CONFIG.xdma_num_usr_irq {1}] [get_bd_cells xdma_0]
if {$board_part ne ""} {
  apply_bd_automation -rule xilinx.com:bd_rule:xdma -config {lane_width {X8} link_speed {8.0 GT/s (PCIe Gen 3)} axi_intf {AXI Memory Mapped} bar_size {Disable} bypass_size {Disable} c2h {1} h2c {1}} [get_bd_cells xdma_0]
} else {
  make_bd_intf_pins_external [get_bd_intf_pins xdma_0/pcie_mgt]
  # Reference clock buffer and reset must be added for the chosen board.
}

create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4 ddr4_0
if {$board_part ne ""} {
  apply_bd_automation -rule xilinx.com:bd_rule:board -config [list Board_Interface $ddr_interface] [get_bd_intf_pins ddr4_0/C0_DDR4]
}

create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_eclk
set_property -dict [list CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $eclk_mhz CONFIG.USE_RESET {false}] [get_bd_cells clk_eclk]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_eclk

create_bd_cell -type module -reference ca_core_xdma ca_core
set_property -dict [list CONFIG.BUF1 $buf1_addr] [get_bd_cells ca_core]

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smc_mem
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_CLKS {2}] [get_bd_cells smc_mem]
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smc_lite
set_property -dict [list CONFIG.NUM_SI {1}] [get_bd_cells smc_lite]

# Clocks and resets: the core's AXI side runs on the XDMA user clock.
connect_bd_net [get_bd_pins xdma_0/axi_aclk] [get_bd_pins ca_core/aclk] [get_bd_pins smc_mem/aclk] \
  [get_bd_pins smc_lite/aclk] [get_bd_pins clk_eclk/clk_in1]
connect_bd_net [get_bd_pins xdma_0/axi_aresetn] [get_bd_pins ca_core/aresetn] [get_bd_pins smc_mem/aresetn] \
  [get_bd_pins smc_lite/aresetn] [get_bd_pins rst_eclk/ext_reset_in]
connect_bd_net [get_bd_pins clk_eclk/clk_out1] [get_bd_pins ca_core/eclk] [get_bd_pins rst_eclk/slowest_sync_clk]
connect_bd_net [get_bd_pins clk_eclk/locked] [get_bd_pins rst_eclk/dcm_locked]
connect_bd_net [get_bd_pins rst_eclk/peripheral_aresetn] [get_bd_pins ca_core/eresetn]
connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk] [get_bd_pins smc_mem/aclk1]
connect_bd_net [get_bd_pins ca_core/pass_done] [get_bd_pins xdma_0/usr_irq_req]

# AXI connections.
connect_bd_intf_net [get_bd_intf_pins xdma_0/M_AXI]      [get_bd_intf_pins smc_mem/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ca_core/m_axi]     [get_bd_intf_pins smc_mem/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins smc_mem/M00_AXI]   [get_bd_intf_pins ddr4_0/C0_DDR4_S_AXI]
connect_bd_intf_net [get_bd_intf_pins xdma_0/M_AXI_LITE] [get_bd_intf_pins smc_lite/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins smc_lite/M00_AXI]  [get_bd_intf_pins ca_core/s_axil]

assign_bd_address
set_property offset 0x00000000 [get_bd_addr_segs {xdma_0/M_AXI/SEG_ddr4_0_C0_DDR4_ADDRESS_BLOCK}]
set_property offset 0x00000000 [get_bd_addr_segs {ca_core/m_axi/SEG_ddr4_0_C0_DDR4_ADDRESS_BLOCK}]
set_property offset 0x00000000 [get_bd_addr_segs {xdma_0/M_AXI_LITE/SEG_ca_core_reg0}]

validate_bd_design
save_bd_design
make_wrapper -files [get_files ca_xdma_bd.bd] -top
add_files -norecurse [glob $out/vivado/ca_xdma.gen/sources_1/bd/ca_xdma_bd/hdl/ca_xdma_bd_wrapper.v]
set_property top ca_xdma_bd_wrapper [current_fileset]
puts "Block design created. Add board constraints (PCIe reference clock, reset, DDR pins if not from board files), then run synthesis."
