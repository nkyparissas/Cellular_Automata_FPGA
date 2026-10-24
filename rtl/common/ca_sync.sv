// Multi-flop synchroniser for single bits or gray-coded vectors.
module ca_sync #(
  parameter int unsigned W      = 1,
  parameter int unsigned STAGES = 2
) (
  input  logic         clk_i,
  input  logic [W-1:0] d_i,
  output logic [W-1:0] q_o
);
  (* ASYNC_REG = "TRUE" *) logic [STAGES-1:0][W-1:0] sr;
  always_ff @(posedge clk_i) begin
    sr[0] <= d_i;
    for (int unsigned i = 1; i < STAGES; i++) sr[i] <= sr[i-1];
  end
  assign q_o = sr[STAGES-1];
endmodule
