// Test and lint wrapper for ca_engine with the Lenia rule (integer parameters,
// flat ports; sel_i = {bank, sh[5:0]}).
module tb_lenia #(
  parameter int unsigned N           = 7,
  parameter int unsigned CELL_W      = 16,
  parameter int unsigned WEIGHT_W    = 6,
  parameter int unsigned LUT_IDX_W   = 12,
  parameter logic [ca_pkg::lenia_classes(N)*WEIGHT_W-1:0] KERNEL_DEFAULT = '0,
  parameter string       GROWTH_INIT = ""
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic [N-1:0][CELL_W-1:0] col_i,
  input  logic                     vld_i,
  input  logic                     kern_valid_i,
  input  logic [WEIGHT_W-1:0]      kern_data_i,
  output logic                     kern_done_o,
  input  logic                     gt_clk_i,
  input  logic                     gt_we_i,
  input  logic [LUT_IDX_W:0]       gt_addr_i,
  input  logic [CELL_W:0]          gt_data_i,
  input  logic [6:0]               sel_i,
  output logic [CELL_W-1:0]        cell_o,
  output logic                     vld_o
);
  ca_engine #(.N(N), .CELL_W(CELL_W), .RULE(ca_pkg::RULE_LENIA), .WEIGHT_W(WEIGHT_W), .LUT_IDX_W(LUT_IDX_W),
              .KERNEL_DEFAULT(KERNEL_DEFAULT), .GROWTH_INIT(GROWTH_INIT)) i_engine (
    .clk_i, .rst_ni, .col_i, .vld_i, .params_i('0), .kern_valid_i, .kern_data_i, .kern_done_o, .gt_clk_i, .gt_we_i,
    .gt_addr_i, .gt_data_i, .sel_i(ca_pkg::lenia_sel_t'(sel_i)), .cell_o, .vld_o);
endmodule
