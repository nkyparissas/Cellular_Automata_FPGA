// AXI4-Lite master with blocking write/read tasks. Drives and samples on
// negedges so that the DUT sees stable values at each posedge.
//   +axil_early  keep BREADY/RREADY high for the whole transaction (as many
//                masters do) instead of raising them after the address phase
// In both modes a BVALID/RVALID seen before the AW/W or AR handshake has
// completed is a protocol error (AXI4 A3.3.1) and stops the simulation.
module axil_bfm #(
  parameter type axil_req_t  = logic,
  parameter type axil_resp_t = logic
) (
  input  logic       clk_i,
  output axil_req_t  req_o,
  input  axil_resp_t resp_i
);
  bit early;
  initial begin
    req_o = '0;
    early = $test$plusargs("axil_early");
  end

  task automatic write(input logic [31:0] addr, input logic [31:0] data);
    bit aw_hs, w_hs;
    @(negedge clk_i);
    req_o.aw.addr  = addr;
    req_o.aw_valid = 1'b1;
    req_o.w.data   = data;
    req_o.w.strb   = '1;
    req_o.w_valid  = 1'b1;
    req_o.b_ready  = early;
    // A ready seen at a negedge completes its handshake at the next posedge.
    while (req_o.aw_valid || req_o.w_valid) begin
      if (resp_i.b_valid) $fatal(1, "axil_bfm: BVALID before the AW/W handshakes completed");
      aw_hs = req_o.aw_valid && resp_i.aw_ready;
      w_hs  = req_o.w_valid && resp_i.w_ready;
      @(negedge clk_i);
      if (aw_hs) req_o.aw_valid = 1'b0;
      if (w_hs)  req_o.w_valid  = 1'b0;
    end
    req_o.b_ready = 1'b1;
    while (!resp_i.b_valid) @(negedge clk_i);
    @(negedge clk_i);
    req_o.b_ready = 1'b0;
  endtask

  task automatic read(input logic [31:0] addr, output logic [31:0] data);
    bit ar_hs;
    @(negedge clk_i);
    req_o.ar.addr  = addr;
    req_o.ar_valid = 1'b1;
    req_o.r_ready  = early;
    while (req_o.ar_valid) begin
      if (resp_i.r_valid) $fatal(1, "axil_bfm: RVALID before the AR handshake completed");
      ar_hs = resp_i.ar_ready;
      @(negedge clk_i);
      if (ar_hs) req_o.ar_valid = 1'b0;
    end
    req_o.r_ready = 1'b1;
    while (!resp_i.r_valid) @(negedge clk_i);
    data = resp_i.r.data;
    @(negedge clk_i);
    req_o.r_ready = 1'b0;
  endtask
endmodule
