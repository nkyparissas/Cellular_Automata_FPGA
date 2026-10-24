// Fixed delay line of D clock cycles (D = 0 is a wire). No reset: data path.
module ca_delay #(
  parameter int unsigned W = 1,
  parameter int unsigned D = 1
) (
  input  logic         clk_i,
  input  logic [W-1:0] d_i,
  output logic [W-1:0] q_o
);
  if (D == 0) begin : g_wire
    assign q_o = d_i;
  end else begin : g_regs
    logic [D-1:0][W-1:0] sr;
    always_ff @(posedge clk_i) begin
      sr[0] <= d_i;
      for (int unsigned i = 1; i < D; i++) sr[i] <= sr[i-1];
    end
    assign q_o = sr[D-1];
  end
endmodule
