// Interval rule (spec Section 11): S = masked sum of all cells; the new
// state is ALIVE when S lies in [LO1, HI1] or [LO2, HI2], 0 otherwise.
// Artificial Physics is LO1=20, HI1=23, LO2=59, HI2=100, ALIVE=1.
// Latency: tree_lat(N*N) + 1.
module ca_rule_interval #(
  parameter int unsigned    N      = 21,
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
  localparam int unsigned TL = ca_pkg::tree_lat(NN);
  localparam int unsigned SW = CELL_W + $clog2(NN + 1);

  logic [NN-1:0][CELL_W-1:0] s_in;
  for (genvar i = 0; i < N; i++) begin : g_i
    for (genvar j = 0; j < N; j++) begin : g_j
      assign s_in[i*N+j] = MASK[i*N+j] ? win_i[i][j] : '0;
    end
  end

  logic [SW-1:0] s_sum;
  ca_adder_tree #(.N_IN(NN), .IN_W(CELL_W), .OUT_W(SW)) i_s (.clk_i, .in_i(s_in), .sum_o(s_sum));
  ca_valid_delay #(.D(TL + 1)) i_vld (.clk_i, .rst_ni, .d_i(vld_i), .q_o(vld_o));

  logic [31:0] s32;
  logic        hit;
  assign s32 = 32'(s_sum);
  assign hit = (s32 >= params_i[ca_pkg::IV_LO1] && s32 <= params_i[ca_pkg::IV_HI1]) ||
               (s32 >= params_i[ca_pkg::IV_LO2] && s32 <= params_i[ca_pkg::IV_HI2]);

  always_ff @(posedge clk_i) cell_o <= hit ? CELL_W'(params_i[ca_pkg::IV_ALIVE]) : '0;
endmodule
