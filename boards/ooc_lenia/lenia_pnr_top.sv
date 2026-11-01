// Open-source place-and-route harness for the Lenia datapath (ca_window +
// ca_rule_lenia through ca_engine) on the Nexys 4 DDR part, xc7a100tcsg324-1
// (boards/ooc_lenia/run_openxc7.sh). The column input comes from a rule-90
// scrambler fed by an LFSR (every bit's next value is the XOR of its two
// neighbours), so no register's input equals another register's output and
// synthesis cannot merge window registers the way a plain shift register would
// let it. The outputs are folded into one register, so only a clock, a reset
// and one LED are pins; nothing can be optimised away. The reset pin passes
// through ca_reset_sync, as in ca_core, so the reset's fan-out is timed.
// Paths that are static in the real core (weights, table selection, table
// writes) toggle here and are timed as ordinary single-cycle paths, which is
// conservative. The table write port runs on the engine clock.
module lenia_pnr_top #(
  parameter int unsigned N         = 27,
  parameter int unsigned CELL_W    = 16,
  parameter int unsigned WEIGHT_W  = 6,
  parameter int unsigned LUT_IDX_W = 12
) (
  input  logic clk_i,     // engine clock, constrained to the target frequency
  input  logic rst_ni,
  output logic led_o
);
  localparam int unsigned CW = N * CELL_W;

  logic rst_n;
  ca_reset_sync i_rst (.clk_i, .arst_ni(rst_ni), .rst_no(rst_n));

  // Galois LFSR, x^32 + x^22 + x^2 + x + 1 (data path: power-up value, no reset).
  logic [31:0] lfsr;
  initial lfsr = 32'h1;
  always_ff @(posedge clk_i) lfsr <= {lfsr[30:0], 1'b0} ^ (lfsr[31] ? 32'h0040_0007 : 32'h0);

  logic [CW-1:0]        col_sr;
  logic [LUT_IDX_W:0]   gt_addr;
  logic [CELL_W:0]      gt_data;
  logic                 gt_we, kern_valid, vld;
  logic [WEIGHT_W-1:0]  kern_data;
  logic [6:0]           sel;
  always_ff @(posedge clk_i) begin
    col_sr     <= {col_sr[CW-2:0], lfsr[0]} ^ {lfsr[1], col_sr[CW-1:1]};
    vld        <= lfsr[8];
    kern_valid <= lfsr[15:9] == '0;
    kern_data  <= WEIGHT_W'(lfsr[21:16]);
    sel        <= {lfsr[22], lfsr[28:23]};
    gt_we      <= lfsr[29] & lfsr[30];
    gt_addr    <= gt_addr + 1'b1;
    gt_data    <= (CELL_W + 1)'({lfsr, lfsr});
  end

  logic [CELL_W-1:0] new_cell;
  logic              cell_vld, kern_done;
  ca_engine #(.N(N), .CELL_W(CELL_W), .RULE(ca_pkg::RULE_LENIA), .WEIGHT_W(WEIGHT_W), .LUT_IDX_W(LUT_IDX_W)) i_engine (
    .clk_i, .rst_ni(rst_n), .col_i(col_sr), .vld_i(vld), .params_i('0), .kern_valid_i(kern_valid),
    .kern_data_i(kern_data), .kern_done_o(kern_done), .gt_clk_i(clk_i), .gt_we_i(gt_we), .gt_addr_i(gt_addr),
    .gt_data_i(gt_data), .sel_i(ca_pkg::lenia_sel_t'(sel)), .cell_o(new_cell), .vld_o(cell_vld));

  logic [CELL_W+1:0] fold;
  always_ff @(posedge clk_i) begin
    fold  <= fold ^ {kern_done, cell_vld, new_cell};
    led_o <= ^fold;
  end
endmodule
