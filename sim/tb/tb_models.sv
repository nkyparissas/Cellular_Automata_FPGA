// Self-check of axi_mem_model and axis_sink_model with scripted masters.
`timescale 1ns/1ps
`include "axi/typedef.svh"
module tb_models;
  localparam int unsigned DW = 64, BYTES = DW / 8;
  typedef logic [31:0]   addr_t;
  typedef logic [0:0]    id_t;
  typedef logic [DW-1:0] data_t;
  typedef logic [BYTES-1:0] strb_t;
  typedef logic [0:0]    user_t;
  `AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, user_t)

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  axi_req_t  req = '0;
  axi_resp_t resp;
  axi_mem_model #(.DATA_W(DW), .ADDR_W(32), .ID_W(1), .MEM_BYTES(64'd65536),
                  .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t)) i_mem (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .resp_o(resp));

  task automatic write_burst(input addr_t addr, input int unsigned beats, input int unsigned salt);
    @(negedge clk);
    req.aw = '{addr: addr, len: 8'(beats - 1), size: 3'($clog2(BYTES)), burst: 2'b01, default: '0};
    req.aw_valid = 1;
    while (!resp.aw_ready) @(negedge clk);
    @(negedge clk);
    req.aw_valid = 0;
    for (int unsigned b = 0; b < beats; b++) begin
      req.w = '{data: data_t'({addr + b * BYTES, 32'(salt)}), strb: '1, last: b == beats - 1, default: '0};
      req.w_valid = 1;
      while (!resp.w_ready) @(negedge clk);
      @(negedge clk);
    end
    req.w_valid = 0;
    req.b_ready = 1;
    while (!resp.b_valid) @(negedge clk);
    @(negedge clk);
    req.b_ready = 0;
  endtask

  task automatic read_check(input addr_t addr, input int unsigned beats, input int unsigned salt);
    @(negedge clk);
    req.ar = '{addr: addr, len: 8'(beats - 1), size: 3'($clog2(BYTES)), burst: 2'b01, default: '0};
    req.ar_valid = 1;
    while (!resp.ar_ready) @(negedge clk);
    @(negedge clk);
    req.ar_valid = 0;
    req.r_ready = 1;
    for (int unsigned b = 0; b < beats; b++) begin
      while (!resp.r_valid) @(negedge clk);
      if (resp.r.data != data_t'({addr + b * BYTES, 32'(salt)})) $fatal(1, "read mismatch beat %0d", b);
      if (resp.r.last != (b == beats - 1)) $fatal(1, "rlast wrong on beat %0d", b);
      @(negedge clk);
    end
    req.r_ready = 0;
  endtask

  // Stream source -> sink.
  localparam int unsigned BPR = 3, ROWS = 4;
  logic [DW-1:0] tdata;
  logic          tvalid = 0, tready, tlast, tuser, frame_req;
  axis_sink_model #(.DATA_W(DW), .BEATS_PER_ROW(BPR), .ROWS(ROWS)) i_sink (
    .clk_i(clk), .rst_ni(rst_n), .tdata_i(tdata), .tvalid_i(tvalid), .tready_o(tready),
    .tlast_i(tlast), .tuser_i(tuser), .frame_req_o(frame_req));

  task automatic send_frame(input int unsigned salt);
    for (int unsigned b = 0; b < BPR * ROWS; b++) begin
      @(negedge clk);
      tvalid = 1;
      tdata  = DW'(salt * 1000 + b);
      tuser  = b == 0;
      tlast  = (b % BPR) == BPR - 1;
      @(posedge clk);
      while (!tready) @(posedge clk);
    end
    @(negedge clk);
    tvalid = 0;
  endtask

  initial begin
    int unsigned bad = 0;
    void'($value$plusargs("bad_burst=%d", bad));
    repeat (3) @(posedge clk);
    rst_n = 1;
    if (bad != 0) write_burst(32'h0FF8, 2, 9);         // crosses 0x1000
    write_burst(32'h0000, 16, 1);
    write_burst(32'h0F80, 16, 2);                      // ends exactly at 0x1000
    write_burst(32'h1000, 1, 3);
    read_check(32'h0F80, 16, 2);
    read_check(32'h0000, 16, 1);
    read_check(32'h1000, 1, 3);
    send_frame(1);
    send_frame(2);
    repeat (5) @(posedge clk);
    if (i_sink.frames_seen != 2) $fatal(1, "sink saw %0d frames", i_sink.frames_seen);
    for (int unsigned b = 0; b < BPR * ROWS; b++)
      if (i_sink.frame[b] != DW'(2000 + b)) $fatal(1, "sink frame beat %0d wrong", b);
    $display("TB_PASS frames=%0d writes=%0d reads=%0d", i_sink.frames_seen, i_mem.writes, i_mem.reads);
    $finish;
  end

  initial begin
    repeat (200000) @(posedge clk);
    $fatal(1, "timeout");
  end
endmodule
