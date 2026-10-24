// ca_frame_writer testbench: a stream source pushes the output rows of one
// pass (+rows_hex) with random gaps; memory around the frame is dumped to
// +out_file afterwards.
`timescale 1ns/1ps
`include "axi/typedef.svh"
module tb_writer #(
  parameter int unsigned GRID_X    = 64,
  parameter int unsigned GRID_Y    = 8,
  parameter int unsigned CELL_W    = 8,
  parameter int unsigned NBH       = 5,
  parameter int unsigned DATA_W    = 64,
  parameter int unsigned BND_ID    = 0,
  parameter int unsigned BASE      = 32'h2000,
  parameter int unsigned MAX_BURST = 16
);
  import ca_pkg::*;
  localparam boundary_e   BND   = boundary_e'(BND_ID);
  localparam int unsigned BYTES = DATA_W / 8;
  localparam int unsigned BPR   = GRID_X * CELL_W / DATA_W;
  localparam int unsigned O     = out_rows(GRID_Y, NBH, BND);
  localparam int unsigned PW    = $clog2(NBH + 1) + 2;
  localparam int unsigned ROWB  = GRID_X * CELL_W / 8;

  typedef logic [31:0]       addr_t;
  typedef logic [0:0]        id_t;
  typedef logic [DATA_W-1:0] data_t;
  typedef logic [BYTES-1:0]  strb_t;
  typedef logic [0:0]        user_t;
  `AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, user_t)

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  axi_req_t  req;
  axi_resp_t resp;
  axi_mem_model #(.DATA_W(DATA_W), .ADDR_W(32), .ID_W(1), .MEM_BYTES(64'd1048576),
                  .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t)) i_mem (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .resp_o(resp));

  logic              start = 0, commit = 1, done, s_valid = 0, s_ready;
  logic [DATA_W-1:0] s_data;
  logic [PW-1:0]     popped;

  ca_frame_writer #(.GRID_X(GRID_X), .GRID_Y(GRID_Y), .CELL_W(CELL_W), .NBH(NBH), .DATA_W(DATA_W),
                    .ADDR_W(32), .BND(BND), .MAX_BURST(MAX_BURST), .PW(PW),
                    .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t)) dut (
    .clk_i(clk), .rst_ni(rst_n), .start_i(start), .commit_i(commit), .base_addr_i(32'(BASE)),
    .done_o(done), .s_tdata_i(s_data), .s_tvalid_i(s_valid), .s_tready_o(s_ready),
    .popped_o(popped), .axi_req_o(req), .axi_resp_i(resp));

  logic [DATA_W-1:0] rows [O * BPR];
  string rows_hex, out_file;
  int unsigned gap = 0, discard = 0, n_done = 0;

  int unsigned trace = 0;
  initial void'($value$plusargs("trace=%d", trace));
  always_ff @(posedge clk) begin
    if (done && rst_n) n_done <= n_done + 1;
    if (trace != 0 && rst_n && done)
      $display("%0t state=%0d done=%0d row=%0d b_out=%0d", $time, dut.state, done, dut.row, dut.b_out);
  end

  initial begin
    void'($value$plusargs("src_gap=%d", gap));
    void'($value$plusargs("discard=%d", discard));
    if (!$value$plusargs("rows_hex=%s", rows_hex)) $fatal(1, "+rows_hex missing");
    if (!$value$plusargs("out_file=%s", out_file)) $fatal(1, "+out_file missing");
    $readmemh(rows_hex, rows);
    i_mem.fill(BASE - 64, GRID_Y * ROWB + 128, {BYTES{8'hA5}});
    commit = discard == 0;
    repeat (3) @(posedge clk);
    rst_n = 1;
    @(negedge clk);
    start = 1;
    @(negedge clk);
    start = 0;
    // Stream source.
    for (int unsigned w = 0; w < O * BPR; w++) begin
      while ($urandom_range(99) < gap) begin
        s_valid = 0;
        @(negedge clk);
      end
      s_valid = 1;
      s_data  = rows[w];
      while (!s_ready) @(negedge clk);   // ready seen at a negedge holds for the next posedge
      @(negedge clk);                    // the handshake happened at that posedge
    end
    s_valid = 0;
    while (n_done == 0) @(negedge clk);
    repeat (5) @(negedge clk);
    if (popped != PW'(O)) $fatal(1, "popped %0d, expected %0d", popped, O);
    if (n_done != 1) $fatal(1, "done pulsed %0d times", n_done);
    i_mem.dump_hex(out_file, BASE - 64, GRID_Y * ROWB + 128);
    $display("TB_PASS writes=%0d", i_mem.writes);
    $finish;
  end

  initial begin
    repeat (2000000) @(posedge clk);
    $fatal(1, "timeout popped=%0d", popped);
  end
endmodule
