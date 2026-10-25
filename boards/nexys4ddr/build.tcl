# Vivado non-project build for the Digilent Nexys 4 DDR (xc7a100tcsg324-1).
# UNVERIFIED: written without access to Vivado; expect to adjust IP property
# names for your Vivado version.
#
# Usage (from the repository root):
#   vivado -mode batch -source boards/nexys4ddr/build.tcl -tclargs configs/hodgepodge29.json
set board_dir [file normalize [file dirname [info script]]]
set root      [file normalize $board_dir/../..]
set cfg       [expr {[llength $argv] > 0 ? [lindex $argv 0] : "configs/hodgepodge29.json"}]
set part      xc7a100tcsg324-1
set out       $root/build/nexys4ddr
file mkdir $out/ip

# Configuration header and source list from the repository's Python tools.
exec python3 $root/tools/gen_cfg.py --config $root/$cfg --data-w 128 --out $out/ca_cfg.svh
exec python3 $root/tools/gen_filelist.py --top ca_display_system --out $out/files.f

create_project -in_memory -part $part
set incdirs [list $out $root/third_party/axi/include $root/third_party/common_cells/include]
set fh [open $out/files.f]
foreach f [split [string trim [read $fh]] "\n"] { read_verilog -sv $root/$f }
close $fh
read_verilog -sv $board_dir/top_nexys4ddr.sv
read_xdc $board_dir/nexys4ddr.xdc

# Clocks: 200 MHz (MIG reference and engine) and 325 MHz (MIG system) from one MMCM
# (VCO 975 MHz, CLKOUT0 4.875, CLKOUT1 3), 148.5 MHz (1080p60 pixel) from a second one
# (VCO 928.125 MHz, CLKOUT0 6.25). One MMCM cannot produce all three exactly (the best
# compromise is 3% off), so this follows the legacy design's two wizards on CLK100MHZ.
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_ca -dir $out/ip
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ {100.000} \
  CONFIG.CLK_OUT1_PORT {clk_ref_200} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
  CONFIG.CLKOUT2_USED {true} CONFIG.CLK_OUT2_PORT {clk_sys_325} CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {325.000} \
  CONFIG.USE_RESET {true} CONFIG.RESET_TYPE {ACTIVE_HIGH} CONFIG.USE_LOCKED {true}] [get_ips clk_wiz_ca]
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name clk_wiz_pix -dir $out/ip
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ {100.000} \
  CONFIG.CLK_OUT1_PORT {clk_pix_148} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {148.500} \
  CONFIG.USE_RESET {true} CONFIG.RESET_TYPE {ACTIVE_HIGH} CONFIG.USE_LOCKED {true}] [get_ips clk_wiz_pix]

# DDR2 controller with an AXI4 slave (settings in ip/mig_ddr2_axi.prj).
create_ip -name mig_7series -vendor xilinx.com -library ip -module_name mig_ddr2_axi -dir $out/ip
file copy -force $board_dir/ip/mig_ddr2_axi.prj $out/ip/mig_ddr2_axi/mig_ddr2_axi.prj
set_property -dict [list CONFIG.XML_INPUT_FILE {mig_ddr2_axi.prj} CONFIG.RESET_BOARD_INTERFACE {Custom} \
  CONFIG.MIG_DONT_TOUCH_PARAM {Custom} CONFIG.BOARD_MIG_PARAM {Custom}] [get_ips mig_ddr2_axi]

generate_target all [get_ips]
synth_ip [get_ips]

synth_design -top top_nexys4ddr -part $part -include_dirs $incdirs
opt_design
place_design
phys_opt_design
route_design
report_utilization    -file $out/utilization.rpt
report_timing_summary -file $out/timing.rpt
write_bitstream -force $out/ca_nexys4ddr.bit
