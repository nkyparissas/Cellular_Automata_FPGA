// Brings an active-low reset from a pin or another clock domain into clk_i.
// The design uses synchronous resets only, so the input level is simply
// synchronised: assertion and release both take effect after two edges of
// clk_i, and clk_i must run while the reset is applied.
module ca_reset_sync (
  input  logic clk_i,
  input  logic arst_ni,   // asynchronous to clk_i
  output logic rst_no
);
  (* ASYNC_REG = "TRUE" *) logic [1:0] sr;
  always_ff @(posedge clk_i) sr <= {sr[0], arst_ni};
  assign rst_no = sr[1];
endmodule
