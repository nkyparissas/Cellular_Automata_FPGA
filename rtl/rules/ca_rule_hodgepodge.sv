// Hodgepodge machine (spec Section 11). S = masked sum of all cells,
// A = masked count of non-zero neighbours (centre excluded).
//   c = 0   : min(MAX, A / K)
//   c = MAX : 0
//   else    : min(MAX, S / (A + 1) + G)
// Latency: tree_lat(N*N) + SW + 1, where SW is the width of S.
module ca_rule_hodgepodge #(
  parameter int unsigned         N      = 29,
  parameter int unsigned         CELL_W = 8,
  parameter logic [N*N-1:0]      MASK   = '1
) (
  input  logic                            clk_i,
  input  logic                            rst_ni,
  input  logic [N-1:0][N-1:0][CELL_W-1:0] win_i,
  input  logic                            vld_i,
  input  ca_pkg::rule_params_t            params_i,
  output logic [CELL_W-1:0]               cell_o,
  output logic                            vld_o
);
  localparam int unsigned NN  = N * N;
  localparam int unsigned R   = (N - 1) / 2;
  localparam int unsigned TL  = ca_pkg::tree_lat(NN);
  localparam int unsigned AW  = $clog2(NN + 1);            // A <= NN-1, A+1 <= NN
  localparam int unsigned SW  = CELL_W + $clog2(NN + 1);   // S <= NN * MAX
  localparam int unsigned LAT = TL + SW + 1;
  localparam logic [CELL_W-1:0] MAXV = '1;

  logic [NN-1:0][CELL_W-1:0] s_in;
  logic [NN-1:0][0:0]        a_in;
  for (genvar i = 0; i < N; i++) begin : g_i
    for (genvar j = 0; j < N; j++) begin : g_j
      if (MASK[i*N+j]) begin : g_on
        assign s_in[i*N+j] = win_i[i][j];
        assign a_in[i*N+j] = (i == R && j == R) ? 1'b0 : (win_i[i][j] != '0);
      end else begin : g_off
        assign s_in[i*N+j] = '0;
        assign a_in[i*N+j] = 1'b0;
      end
    end
  end

  logic [SW-1:0] s_sum;
  logic [AW-1:0] a_sum;
  ca_adder_tree #(.N_IN(NN), .IN_W(CELL_W), .OUT_W(SW)) i_s (.clk_i, .in_i(s_in), .sum_o(s_sum));
  ca_adder_tree #(.N_IN(NN), .IN_W(1),      .OUT_W(AW)) i_a (.clk_i, .in_i(a_in), .sum_o(a_sum));

  // K wider than AW bits behaves like an all-ones divisor: A / K = 0.
  logic [AW-1:0] k_den;
  assign k_den = (params_i[ca_pkg::HP_K] >> AW) != 0 ? '1 : AW'(params_i[ca_pkg::HP_K]);

  logic [SW-1:0] q_inf;
  logic [AW-1:0] q_hea, q_hea_d;
  ca_div_pipe #(.NUM_W(SW), .DEN_W(AW)) i_div_inf (
    .clk_i, .num_i(s_sum), .den_i(a_sum + 1'b1), .quo_o(q_inf));
  ca_div_pipe #(.NUM_W(AW), .DEN_W(AW)) i_div_hea (
    .clk_i, .num_i(a_sum), .den_i(k_den), .quo_o(q_hea));
  ca_delay #(.W(AW), .D(SW - AW)) i_align (.clk_i, .d_i(q_hea), .q_o(q_hea_d));

  logic [CELL_W-1:0] c_d;
  ca_delay #(.W(CELL_W), .D(TL + SW)) i_centre (.clk_i, .d_i(win_i[R][R]), .q_o(c_d));
  ca_valid_delay #(.D(LAT)) i_vld (.clk_i, .rst_ni, .d_i(vld_i), .q_o(vld_o));

  logic [33:0] inf_g;
  assign inf_g = 34'(q_inf) + 34'(params_i[ca_pkg::HP_G]);

  always_ff @(posedge clk_i) begin
    if (c_d == '0)        cell_o <= (q_hea_d > AW'(MAXV)) ? MAXV : CELL_W'(q_hea_d);
    else if (c_d == MAXV) cell_o <= '0;
    else                  cell_o <= (inf_g > 34'(MAXV)) ? MAXV : CELL_W'(inf_g);
  end
endmodule
