# Out-of-context synthesis and implementation of the Lenia datapath
# (ca_window + ca_rule_lenia, registered I/O) on the Artix-7 100T at the
# 200 MHz engine clock (Lenia design spec, Section 9.7).
# UNVERIFIED: written without access to Vivado.
#
# Usage (from the repository root):
#   vivado -mode batch -source boards/ooc_lenia/ooc_lenia.tcl [-tclargs N CELL_W]
# Reports: build/ooc_lenia/timing.rpt and build/ooc_lenia/utilization.rpt.
set here [file normalize [file dirname [info script]]]
set root [file normalize $here/../..]
set n    [expr {[llength $argv] > 0 ? [lindex $argv 0] : 27}]
set cw   [expr {[llength $argv] > 1 ? [lindex $argv 1] : 16}]
set part xc7a100tcsg324-1
set out  $root/build/ooc_lenia
file mkdir $out

exec python3 $root/tools/gen_filelist.py --top ooc_lenia_top --extra-dir boards/ooc_lenia --out $out/files.f

create_project -in_memory -part $part
set fh [open $out/files.f]
foreach f [split [string trim [read $fh]] "\n"] { read_verilog -sv $root/$f }
close $fh
read_xdc -mode out_of_context $here/ooc_lenia.xdc

synth_design -top ooc_lenia_top -part $part -mode out_of_context -generic N=$n -generic CELL_W=$cw \
  -include_dirs [list $root/third_party/axi/include $root/third_party/common_cells/include]
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file $out/timing.rpt
report_utilization -file $out/utilization.rpt
puts "ooc_lenia: N=$n CELL_W=$cw, reports in $out"
