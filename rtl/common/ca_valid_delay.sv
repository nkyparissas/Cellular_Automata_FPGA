// Resettable delay line for valid bits (D = 0 is a wire), so that a reset
// clears every valid in flight.
module ca_valid_delay #(
  parameter int unsigned D = 1
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic d_i,
  output logic q_o
);
  if (D == 0) begin : g_wire
    assign q_o = d_i;
  end else begin : g_regs
    logic [D-1:0] sr;
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        sr <= '0;
      end else begin
        sr[0] <= d_i;
        for (int unsigned i = 1; i < D; i++) sr[i] <= sr[i-1];
      end
    end
    assign q_o = sr[D-1];
  end
endmodule
