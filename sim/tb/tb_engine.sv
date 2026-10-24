// Test and lint wrapper for ca_engine with integer parameters.
module tb_engine #(
  parameter int unsigned    N       = 21,
  parameter int unsigned    CELL_W  = 4,
  parameter int unsigned    RULE_ID = 2,
  parameter logic [N*N-1:0] MASK    = '1
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic [N-1:0][CELL_W-1:0] col_i,
  input  logic                     vld_i,
  input  ca_pkg::rule_params_t     params_i,
  output logic [CELL_W-1:0]        cell_o,
  output logic                     vld_o
);
  ca_engine #(.N(N), .CELL_W(CELL_W), .RULE(ca_pkg::rule_e'(RULE_ID)), .MASK(MASK)) i_engine (
    .clk_i, .rst_ni, .col_i, .vld_i, .params_i, .cell_o, .vld_o);
endmodule
