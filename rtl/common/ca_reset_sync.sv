// Active-low reset: asserted asynchronously, released synchronously to clk_i.
module ca_reset_sync (
  input  logic clk_i,
  input  logic arst_ni,
  output logic rst_no
);
  (* ASYNC_REG = "TRUE" *) logic [1:0] sr;
  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni) sr <= '0;
    else          sr <= {sr[0], 1'b1};
  end
  assign rst_no = sr[1];
endmodule
