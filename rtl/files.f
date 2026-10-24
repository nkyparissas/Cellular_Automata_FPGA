// Verilator / cocotb file list. Paths are relative to the repository root.
// Third-party packages first, then project packages, then modules found by -y.
+incdir+third_party/axi/include
+incdir+third_party/common_cells/include
-y third_party/common_cells/src
-y third_party/axi/src
third_party/common_cells/src/cf_math_pkg.sv
third_party/axi/src/axi_pkg.sv
rtl/pkg/ca_pkg.sv
rtl/ctrl/ca_regs_pkg.sv
-y rtl/common
-y rtl/arith
-y rtl/engine
-y rtl/rules
-y rtl/mem
-y rtl/ctrl
-y rtl/top
-y rtl/consumers
-y rtl/io
