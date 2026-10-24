// Lint-only top: GHM engine at the legacy size (N = 29, 4-bit cells).
module lint_engine_ghm (
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic [28:0][3:0]       col_i,
  input  logic                   vld_i,
  input  ca_pkg::rule_params_t   params_i,
  output logic [3:0]             cell_o,
  output logic                   vld_o
);
  tb_engine #(.N(29), .CELL_W(4), .RULE_ID(1)) i_dut (.clk_i, .rst_ni, .col_i, .vld_i, .params_i, .cell_o, .vld_o);
endmodule
