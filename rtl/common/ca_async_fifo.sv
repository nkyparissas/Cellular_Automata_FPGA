// Dual-clock FIFO with gray-coded pointers and a first-word-fall-through
// output. The RAM read is registered so that Vivado can map it to block RAM.
module ca_async_fifo #(
  parameter int unsigned W     = 8,
  parameter int unsigned DEPTH = 16   // power of two
) (
  input  logic         wclk_i,
  input  logic         wrst_ni,
  input  logic         w_valid_i,
  output logic         w_ready_o,
  input  logic [W-1:0] w_data_i,
  input  logic         rclk_i,
  input  logic         rrst_ni,
  output logic         r_valid_o,
  input  logic         r_ready_i,
  output logic [W-1:0] r_data_o
);
  localparam int unsigned AW = $clog2(DEPTH);

  logic [W-1:0] mem [DEPTH];

  // Write side.
  logic [AW:0] wbin, wgray, rgray_w;
  logic        full;
  assign full      = wgray == {~rgray_w[AW:AW-1], rgray_w[AW-2:0]};
  assign w_ready_o = !full;

  always_ff @(posedge wclk_i) begin
    if (w_valid_i && !full) mem[wbin[AW-1:0]] <= w_data_i;
  end

  always_ff @(posedge wclk_i) begin
    if (!wrst_ni) begin
      wbin  <= '0;
      wgray <= '0;
    end else if (w_valid_i && !full) begin
      wbin  <= wbin + 1'b1;
      wgray <= (wbin + 1'b1) ^ ((wbin + 1'b1) >> 1);
    end
  end

  // Read side: fetch from RAM into the output register whenever it is free.
  logic [AW:0] rbin, rgray, wgray_r;
  logic        ram_empty, fetch;
  assign ram_empty = rgray == wgray_r;
  assign fetch     = !ram_empty && (!r_valid_o || r_ready_i);

  always_ff @(posedge rclk_i) begin
    if (fetch) r_data_o <= mem[rbin[AW-1:0]];
  end

  always_ff @(posedge rclk_i) begin
    if (!rrst_ni) begin
      rbin      <= '0;
      rgray     <= '0;
      r_valid_o <= 1'b0;
    end else begin
      if (fetch) begin
        rbin  <= rbin + 1'b1;
        rgray <= (rbin + 1'b1) ^ ((rbin + 1'b1) >> 1);
      end
      if (fetch)          r_valid_o <= 1'b1;
      else if (r_ready_i) r_valid_o <= 1'b0;
    end
  end

  ca_sync #(.W(AW+1)) i_sync_r2w (.clk_i(wclk_i), .d_i(rgray), .q_o(rgray_w));
  ca_sync #(.W(AW+1)) i_sync_w2r (.clk_i(rclk_i), .d_i(wgray), .q_o(wgray_r));

  if (DEPTH < 4 || (1 << AW) != DEPTH) begin : g_bad_depth
    $error("ca_async_fifo: DEPTH must be a power of two >= 4");
  end
endmodule
