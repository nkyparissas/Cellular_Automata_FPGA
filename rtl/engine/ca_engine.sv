// Sliding window followed by the selected rule plug-in. To add a rule,
// add a value to ca_pkg::rule_e and a case arm below (docs/adding_a_rule.md).
module ca_engine #(
  parameter int unsigned     N      = 29,
  parameter int unsigned     CELL_W = 8,
  parameter ca_pkg::rule_e   RULE   = ca_pkg::RULE_HODGEPODGE,
  parameter logic [N*N-1:0]  MASK   = '1
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic [N-1:0][CELL_W-1:0] col_i,
  input  logic                     vld_i,
  input  ca_pkg::rule_params_t     params_i,
  output logic [CELL_W-1:0]        cell_o,
  output logic                     vld_o
);
  logic [N-1:0][N-1:0][CELL_W-1:0] win;
  logic                            win_vld;

  ca_window #(.N(N), .CELL_W(CELL_W)) i_window (
    .clk_i, .rst_ni, .col_i, .vld_i, .win_o(win), .vld_o(win_vld));

  case (RULE)
    ca_pkg::RULE_HODGEPODGE: begin : g_hodgepodge
      ca_rule_hodgepodge #(.N(N), .CELL_W(CELL_W), .MASK(MASK)) i_rule (
        .clk_i, .rst_ni, .win_i(win), .vld_i(win_vld), .params_i, .cell_o, .vld_o);
    end
    ca_pkg::RULE_GHM: begin : g_ghm
      ca_rule_ghm #(.N(N), .CELL_W(CELL_W), .MASK(MASK)) i_rule (
        .clk_i, .rst_ni, .win_i(win), .vld_i(win_vld), .params_i, .cell_o, .vld_o);
    end
    ca_pkg::RULE_INTERVAL: begin : g_interval
      ca_rule_interval #(.N(N), .CELL_W(CELL_W), .MASK(MASK)) i_rule (
        .clk_i, .rst_ni, .win_i(win), .vld_i(win_vld), .params_i, .cell_o, .vld_o);
    end
    default: begin : g_bad
      $error("ca_engine: unsupported RULE");
    end
  endcase
endmodule
