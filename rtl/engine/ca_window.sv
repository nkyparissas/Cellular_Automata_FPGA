// N x N sliding window. Each cycle every row shifts left by one column and
// col_i enters at column N-1, so win_o[i][j] is grid row y-r+i, column x-r+j
// of the window whose newest column arrived last. Latency 1 (vld_o follows).
module ca_window #(
  parameter int unsigned N      = 29,
  parameter int unsigned CELL_W = 8
) (
  input  logic                            clk_i,
  input  logic                            rst_ni,
  input  logic [N-1:0][CELL_W-1:0]        col_i,
  input  logic                            vld_i,
  output logic [N-1:0][N-1:0][CELL_W-1:0] win_o,
  output logic                            vld_o
);
  always_ff @(posedge clk_i) begin
    for (int unsigned i = 0; i < N; i++) begin
      for (int unsigned j = 0; j + 1 < N; j++) win_o[i][j] <= win_o[i][j+1];
      win_o[i][N-1] <= col_i[i];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) vld_o <= 1'b0;
    else         vld_o <= vld_i;
  end
endmodule
