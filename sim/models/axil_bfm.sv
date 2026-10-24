// AXI4-Lite master with blocking write/read tasks. Drives and samples on
// negedges so that the DUT sees stable values at each posedge.
module axil_bfm #(
  parameter type axil_req_t  = logic,
  parameter type axil_resp_t = logic
) (
  input  logic       clk_i,
  output axil_req_t  req_o,
  input  axil_resp_t resp_i
);
  initial req_o = '0;

  task automatic write(input logic [31:0] addr, input logic [31:0] data);
    @(negedge clk_i);
    req_o.aw.addr  = addr;
    req_o.aw_valid = 1'b1;
    req_o.w.data   = data;
    req_o.w.strb   = '1;
    req_o.w_valid  = 1'b1;
    req_o.b_ready  = 1'b0;
    fork
      begin
        while (!resp_i.aw_ready) @(negedge clk_i);
        @(negedge clk_i);
        req_o.aw_valid = 1'b0;
      end
      begin
        while (!resp_i.w_ready) @(negedge clk_i);
        @(negedge clk_i);
        req_o.w_valid = 1'b0;
      end
    join
    req_o.b_ready = 1'b1;   // raised only now, so the response cannot slip past
    while (!resp_i.b_valid) @(negedge clk_i);
    @(negedge clk_i);
    req_o.b_ready = 1'b0;
  endtask

  task automatic read(input logic [31:0] addr, output logic [31:0] data);
    @(negedge clk_i);
    req_o.ar.addr  = addr;
    req_o.ar_valid = 1'b1;
    req_o.r_ready  = 1'b0;
    while (!resp_i.ar_ready) @(negedge clk_i);
    @(negedge clk_i);
    req_o.ar_valid = 1'b0;
    req_o.r_ready  = 1'b1;
    while (!resp_i.r_valid) @(negedge clk_i);
    data = resp_i.r.data;
    @(negedge clk_i);
    req_o.r_ready = 1'b0;
  endtask
endmodule
