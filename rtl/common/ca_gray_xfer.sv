// Transfers a counter that changes by at most one per source cycle into
// another clock domain. The destination sees a monotonic, possibly lagging copy.
module ca_gray_xfer #(
  parameter int unsigned W = 8
) (
  input  logic         src_clk_i,
  input  logic         src_rst_ni,
  input  logic [W-1:0] src_bin_i,
  input  logic         dst_clk_i,
  input  logic         dst_rst_ni,
  output logic [W-1:0] dst_bin_o
);
  logic [W-1:0] gray_q, gray_s;

  always_ff @(posedge src_clk_i) begin
    if (!src_rst_ni) gray_q <= '0;
    else             gray_q <= src_bin_i ^ (src_bin_i >> 1);
  end

  ca_sync #(.W(W)) i_sync (.clk_i(dst_clk_i), .d_i(gray_q), .q_o(gray_s));

  logic [W-1:0] bin_d;
  always_comb begin
    bin_d[W-1] = gray_s[W-1];
    for (int i = int'(W) - 2; i >= 0; i--) bin_d[i] = bin_d[i+1] ^ gray_s[i];
  end

  always_ff @(posedge dst_clk_i) begin
    if (!dst_rst_ni) dst_bin_o <= '0;
    else             dst_bin_o <= bin_d;
  end
endmodule
