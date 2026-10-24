// ca_frame_reader testbench: memory model + stream sink + line-buffer stub.
// Every row written to the line buffer is dumped to +out_file (one row per
// line, DATA_W words in hex). Two passes are run back to back.
`timescale 1ns/1ps
`include "axi/typedef.svh"
module tb_reader #(
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
  localparam int unsigned SLOTS = NBH + 1;
  localparam int unsigned SLW   = $clog2(SLOTS);
  localparam int unsigned BW    = BPR > 1 ? $clog2(BPR) : 1;
  localparam int unsigned V     = virt_rows(GRID_Y, NBH, BND);

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

  logic [DATA_W-1:0] tdata;
  logic              tvalid, tready, tlast, tuser, frame_req;
  axis_sink_model #(.DATA_W(DATA_W), .BEATS_PER_ROW(BPR), .ROWS(GRID_Y)) i_sink (
    .clk_i(clk), .rst_ni(rst_n), .tdata_i(tdata), .tvalid_i(tvalid), .tready_o(tready),
    .tlast_i(tlast), .tuser_i(tuser), .frame_req_o(frame_req));

  logic              start = 0, fwd_en = 1, done;
  logic              alloc_valid, alloc_ready, wr_en, row_done;
  logic [SLW-1:0]    alloc_slot, wr_slot;
  logic [BW-1:0]     wr_addr;
  logic [DATA_W-1:0] wr_data;

  ca_frame_reader #(.GRID_X(GRID_X), .GRID_Y(GRID_Y), .CELL_W(CELL_W), .NBH(NBH), .DATA_W(DATA_W),
                    .ADDR_W(32), .BND(BND), .MAX_BURST(MAX_BURST),
                    .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t)) dut (
    .clk_i(clk), .rst_ni(rst_n), .start_i(start), .base_addr_i(32'(BASE)), .fwd_en_i(fwd_en),
    .done_o(done), .axi_req_o(req), .axi_resp_i(resp),
    .m_axis_tdata_o(tdata), .m_axis_tvalid_o(tvalid), .m_axis_tready_i(tready),
    .m_axis_tlast_o(tlast), .m_axis_tuser_o(tuser),
    .lb_alloc_valid_o(alloc_valid), .lb_alloc_ready_i(alloc_ready), .lb_alloc_slot_i(alloc_slot),
    .lb_wr_en_o(wr_en), .lb_wr_slot_o(wr_slot), .lb_wr_addr_o(wr_addr), .lb_wr_data_o(wr_data),
    .lb_row_done_o(row_done));

  // Line-buffer stub (RTL style, race-free).
  int unsigned  fd, rows_seen = 0, done_q = 0;
  logic [SLW-1:0] slot_q[$];
  logic [DATA_W-1:0] row [BPR];
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      alloc_ready <= 1'b0;
      alloc_slot  <= '0;
    end else begin
      alloc_ready <= $urandom_range(99) < 70;
      if (alloc_valid && alloc_ready) begin
        slot_q.push_back(alloc_slot);
        alloc_slot <= (alloc_slot == SLW'(SLOTS - 1)) ? '0 : alloc_slot + 1'b1;
      end
      if (row_done) begin
        if (done_q == 0) $fatal(1, "row_done without a completed row");
        done_q--;
        rows_seen++;
      end
      if (wr_en) begin
        if (slot_q.size() == 0 || wr_slot != slot_q[0]) $fatal(1, "write to unallocated slot %0d", wr_slot);
        row[wr_addr] = wr_data;
        if (wr_addr == BW'(BPR - 1)) begin   // row complete: retire its slot and dump it
          for (int unsigned b = 0; b < BPR; b++) $fwrite(fd, "%0h ", row[b]);
          $fwrite(fd, "\n");
          void'(slot_q.pop_front());
          done_q++;
        end
      end
    end
  end

  int unsigned trace = 0;
  initial void'($value$plusargs("trace=%d", trace));
  always_ff @(posedge clk) if (trace != 0 && rst_n) begin
    if (alloc_valid && alloc_ready) $display("%0t alloc slot=%0d istate=%0d v=%0d", $time, alloc_slot, dut.istate, dut.v);
    if (req.ar_valid && resp.ar_ready) $display("%0t AR addr=%0h len=%0d", $time, req.ar.addr, req.ar.len);
    if (resp.r_valid && req.r_ready) $display("%0t R last=%0d beat=%0d", $time, resp.r.last, dut.beat);
    if (row_done) $display("%0t row_done", $time);
  end

  string frame_hex, out_file;
  initial begin
    int unsigned nofwd = 0;
    void'($value$plusargs("nofwd=%d", nofwd));
    if (!$value$plusargs("frame_hex=%s", frame_hex)) $fatal(1, "+frame_hex missing");
    if (!$value$plusargs("out_file=%s", out_file)) $fatal(1, "+out_file missing");
    fd = $fopen(out_file, "w");
    i_mem.load_hex(frame_hex, BASE);
    fwd_en = nofwd == 0;
    repeat (3) @(posedge clk);
    rst_n = 1;
    for (int p = 0; p < 2; p++) begin
      @(negedge clk);
      start = 1;
      @(negedge clk);
      start = 0;
      while (!done) @(negedge clk);
    end
    repeat (10) @(posedge clk);
    $fclose(fd);
    if (rows_seen != 2 * V) $fatal(1, "rows_seen %0d, expected %0d", rows_seen, 2 * V);
    if (nofwd != 0) begin
      if (i_sink.frames_seen != 0) $fatal(1, "stream active with fwd_en=0");
    end else begin
      if (i_sink.frames_seen != 2) $fatal(1, "sink saw %0d frames", i_sink.frames_seen);
      for (int unsigned b = 0; b < BPR * GRID_Y; b++)
        if (i_sink.frame[b] != i_mem.mem[BASE / BYTES + b]) $fatal(1, "stream beat %0d differs", b);
    end
    $display("TB_PASS rows=%0d frames=%0d", rows_seen, i_sink.frames_seen);
    $finish;
  end

  initial begin
    repeat (2000000) @(posedge clk);
    $fatal(1, "timeout rows_seen=%0d", rows_seen);
  end
endmodule
