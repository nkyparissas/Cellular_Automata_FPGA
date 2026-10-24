// Greenberg-Hastings model (spec Section 11). X = masked count of excited
// neighbours (1 <= state <= E, centre excluded).
//   c > 0 : (c + 1 >= STATES) ? 0 : c + 1
//   c = 0 : (X >= T) ? 1 : 0
// Latency: tree_lat(N*N) + 1.
module ca_rule_ghm #(
  parameter int unsigned    N      = 29,
  parameter int unsigned    CELL_W = 4,
  parameter logic [N*N-1:0] MASK   = '1
) (
  input  logic                            clk_i,
  input  logic                            rst_ni,
  input  logic [N-1:0][N-1:0][CELL_W-1:0] win_i,
  input  logic                            vld_i,
  input  ca_pkg::rule_params_t            params_i,
  output logic [CELL_W-1:0]               cell_o,
  output logic                            vld_o
);
  localparam int unsigned NN = N * N;
  localparam int unsigned R  = (N - 1) / 2;
  localparam int unsigned TL = ca_pkg::tree_lat(NN);
  localparam int unsigned XW = $clog2(NN + 1);

  logic [NN-1:0][0:0] x_in;
  for (genvar i = 0; i < N; i++) begin : g_i
    for (genvar j = 0; j < N; j++) begin : g_j
      if (MASK[i*N+j] && !(i == R && j == R)) begin : g_on
        assign x_in[i*N+j] = (win_i[i][j] != '0) && (32'(win_i[i][j]) <= params_i[ca_pkg::GHM_E]);
      end else begin : g_off
        assign x_in[i*N+j] = 1'b0;
      end
    end
  end

  logic [XW-1:0] x_sum;
  ca_adder_tree #(.N_IN(NN), .IN_W(1), .OUT_W(XW)) i_x (.clk_i, .in_i(x_in), .sum_o(x_sum));

  logic [CELL_W-1:0] c_d;
  ca_delay #(.W(CELL_W), .D(TL)) i_centre (.clk_i, .d_i(win_i[R][R]), .q_o(c_d));
  ca_valid_delay #(.D(TL + 1)) i_vld (.clk_i, .rst_ni, .d_i(vld_i), .q_o(vld_o));

  logic [32:0] next;
  assign next = 33'(c_d) + 33'd1;

  always_ff @(posedge clk_i) begin
    if (c_d != '0) cell_o <= (next >= 33'(params_i[ca_pkg::GHM_STATES])) ? '0 : CELL_W'(next);
    else           cell_o <= (32'(x_sum) >= params_i[ca_pkg::GHM_T]) ? CELL_W'(1) : '0;
  end
endmodule
