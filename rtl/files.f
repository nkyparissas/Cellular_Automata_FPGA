// Verilator / cocotb file list. Paths are relative to the repository root.
// Third-party packages first, then project packages, then modules found by -y.
+incdir+third_party/axi/include
+incdir+third_party/common_cells/include
-y third_party/common_cells/src
-y third_party/axi/src
third_party/common_cells/src/cf_math_pkg.sv
third_party/axi/src/axi_pkg.sv
