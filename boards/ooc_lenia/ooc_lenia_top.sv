// Out-of-context timing wrapper for the Lenia datapath (ca_window + ca_rule_lenia
// through ca_engine) with registered inputs and outputs, so that every timed path
// starts and ends at a flip-flop (boards/ooc_lenia/ooc_lenia.tcl).
module ooc_lenia_top #(
  parameter int unsigned N         = 27,
  parameter int unsigned CELL_W    = 16,
  parameter int unsigned WEIGHT_W  = 6,
  parameter int unsigned LUT_IDX_W = 12
) (
  input  logic                     clk_i,      // engine clock (200 MHz target)
  input  logic                     rst_ni,
  input  logic [N-1:0][CELL_W-1:0] col_i,
  input  logic                     vld_i,
  input  logic                     kern_valid_i,
  input  logic [WEIGHT_W-1:0]      kern_data_i,
  input  logic [6:0]               sel_i,      // {bank, sh}
  input  logic                     gt_clk_i,   // register clock (table write port)
  input  logic                     gt_we_i,
  input  logic [LUT_IDX_W:0]       gt_addr_i,
  input  logic [CELL_W:0]          gt_data_i,
  output logic [CELL_W-1:0]        cell_o,
  output logic                     vld_o,
  output logic                     kern_done_o
);
  logic [N-1:0][CELL_W-1:0] col_q;
  logic                     vld_q, kern_valid_q, gt_we_q, vld_e, kern_done_e;
  logic [WEIGHT_W-1:0]      kern_data_q;
  logic [6:0]               sel_q;
  logic [LUT_IDX_W:0]       gt_addr_q;
  logic [CELL_W:0]          gt_data_q;
  logic [CELL_W-1:0]        cell_e;

  always_ff @(posedge clk_i) begin
    col_q        <= col_i;
    kern_data_q  <= kern_data_i;
    sel_q        <= sel_i;
    cell_o       <= cell_e;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      vld_q        <= 1'b0;
      kern_valid_q <= 1'b0;
      vld_o        <= 1'b0;
      kern_done_o  <= 1'b0;
    end else begin
      vld_q        <= vld_i;
      kern_valid_q <= kern_valid_i;
      vld_o        <= vld_e;
      kern_done_o  <= kern_done_e;
    end
  end
  always_ff @(posedge gt_clk_i) begin
    gt_we_q   <= gt_we_i;
    gt_addr_q <= gt_addr_i;
    gt_data_q <= gt_data_i;
  end

  ca_engine #(.N(N), .CELL_W(CELL_W), .RULE(ca_pkg::RULE_LENIA), .WEIGHT_W(WEIGHT_W), .LUT_IDX_W(LUT_IDX_W)) i_engine (
    .clk_i, .rst_ni, .col_i(col_q), .vld_i(vld_q), .params_i('0), .kern_valid_i(kern_valid_q),
    .kern_data_i(kern_data_q), .kern_done_o(kern_done_e), .gt_clk_i, .gt_we_i(gt_we_q), .gt_addr_i(gt_addr_q),
    .gt_data_i(gt_data_q), .sel_i(ca_pkg::lenia_sel_t'(sel_q)), .cell_o(cell_e), .vld_o(vld_e));
endmodule
