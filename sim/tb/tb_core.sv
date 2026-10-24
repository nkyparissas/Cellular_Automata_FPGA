// CA core testbench. The configuration comes from ca_cfg.svh (tools/gen_cfg.py).
//   +seed_hex=<file> +gens=<n> +dump_gens=<a,b,...,> +dump_dir=<dir/>
//   +mem_stall +mem_lat +sink_stall +sink_req=<0|1> +aclk_ps +eclk_ps
//   +midpass_param=1   change RULE_PARAM[0] by +7 while pass 2 runs
// After every generation the frame streamed to the consumer is checked
// against the buffer that was front during that pass.
`timescale 1ns/1ps
`include "axi/typedef.svh"
module tb_core;
  `include "ca_cfg.svh"
  import ca_pkg::*;
  import ca_regs_pkg::*;

  localparam boundary_e       BND         = boundary_e'(BND_ID);
  localparam rule_e           RULE        = rule_e'(RULE_ID);
  localparam int unsigned     BYTES       = DATA_W / 8;
  localparam int unsigned     WPR         = GRID_X * CELL_W / DATA_W;
  localparam longint unsigned FRAME_BYTES = 64'(GRID_X) * GRID_Y * CELL_W / 8;
  localparam longint unsigned BUF0        = 0;
  localparam longint unsigned BUF1        = ((FRAME_BYTES + 4095) / 4096) * 4096 + 64'h1C0;
  localparam longint unsigned MEM_BYTES   = ((BUF1 + FRAME_BYTES + 8191) / 4096) * 4096;

  typedef logic [31:0]       addr_t;
  typedef logic [0:0]        id_t;
  typedef logic [DATA_W-1:0] data_t;
  typedef logic [BYTES-1:0]  strb_t;
  typedef logic [0:0]        user_t;
  typedef logic [31:0]       ldata_t;
  typedef logic [3:0]        lstrb_t;
  `AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, user_t)
  `AXI_LITE_TYPEDEF_ALL(axil, addr_t, ldata_t, lstrb_t)

  logic aclk = 0, eclk = 0, rst_n = 0;
  int unsigned aclk_ps = 5000, eclk_ps = 5000;
  initial begin
    void'($value$plusargs("aclk_ps=%d", aclk_ps));
    void'($value$plusargs("eclk_ps=%d", eclk_ps));
  end
  always #(aclk_ps * 1ps / 2) aclk = ~aclk;
  always #(eclk_ps * 1ps / 2) eclk = ~eclk;

  axi_req_t   mreq;
  axi_resp_t  mresp;
  axil_req_t  lreq;
  axil_resp_t lresp;
  logic [DATA_W-1:0] tdata;
  logic              tvalid, tready, tlast, tuser, frame_req, pass_done;

  axi_mem_model #(.DATA_W(DATA_W), .ADDR_W(32), .ID_W(1), .MEM_BYTES(MEM_BYTES),
                  .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t)) i_mem (
    .clk_i(aclk), .rst_ni(rst_n), .req_i(mreq), .resp_o(mresp));
  axis_sink_model #(.DATA_W(DATA_W), .BEATS_PER_ROW(WPR), .ROWS(GRID_Y)) i_sink (
    .clk_i(aclk), .rst_ni(rst_n), .tdata_i(tdata), .tvalid_i(tvalid), .tready_o(tready),
    .tlast_i(tlast), .tuser_i(tuser), .frame_req_o(frame_req));
  axil_bfm #(.axil_req_t(axil_req_t), .axil_resp_t(axil_resp_t)) bfm (.clk_i(aclk), .req_o(lreq), .resp_i(lresp));

  ca_core #(.GRID_X(GRID_X), .GRID_Y(GRID_Y), .CELL_W(CELL_W), .NBH(NBH), .BOUNDARY(BND), .RULE(RULE),
            .MASK(MASK), .DATA_W(DATA_W), .ADDR_W(32), .MAX_BURST(64), .FIFO_ROWS(2),
            .BUF0_DEFAULT(BUF0), .BUF1_DEFAULT(BUF1), .PARAM_DEFAULTS(PARAMS),
            .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t), .axil_req_t(axil_req_t),
            .axil_resp_t(axil_resp_t)) dut (
    .aclk_i(aclk), .arst_ni(rst_n), .eclk_i(eclk), .erst_ni(rst_n),
    .s_axil_req_i(lreq), .s_axil_resp_o(lresp), .m_axi_req_o(mreq), .m_axi_resp_i(mresp),
    .m_axis_tdata_o(tdata), .m_axis_tvalid_o(tvalid), .m_axis_tready_i(tready),
    .m_axis_tlast_o(tlast), .m_axis_tuser_o(tuser), .frame_req_i(frame_req), .pass_done_o(pass_done));

  function automatic bit in_list(string s, int g);
    int start = 0;
    for (int i = 0; i < s.len(); i++) begin
      if (s[i] == ",") begin
        if (s.substr(start, i - 1).atoi() == g) return 1;
        start = i + 1;
      end
    end
    return 0;
  endfunction

  string seed_hex, dump_dir, dump_gens;
  initial begin
    int unsigned gens = 1, sink_req = 0, midpass = 0;
    longint unsigned max_cycles = 64'd50_000_000;
    if (!$value$plusargs("seed_hex=%s", seed_hex)) $fatal(1, "+seed_hex missing");
    void'($value$plusargs("gens=%d", gens));
    if (!$value$plusargs("dump_gens=%s", dump_gens)) dump_gens = "";
    if (!$value$plusargs("dump_dir=%s", dump_dir)) dump_dir = "./";
    void'($value$plusargs("sink_req=%d", sink_req));
    void'($value$plusargs("midpass_param=%d", midpass));
    i_mem.load_hex(seed_hex, BUF0);
    if (BND == BND_CYLINDRICAL || BND == BND_RECTANGULAR) i_mem.load_hex(seed_hex, BUF1);
    repeat (5) @(posedge aclk);
    rst_n = 1;
    repeat (5) @(posedge aclk);
    bfm.write({24'h0, REG_BUF0_LO}, 32'(BUF0));
    bfm.write({24'h0, REG_BUF1_LO}, 32'(BUF1));
    bfm.write({24'h0, REG_FRAME_REPEAT}, 0);
    bfm.write({24'h0, REG_GENS_PER_FRAME}, 1);
    for (int k = 0; k < NUM_RULE_PARAMS; k++) bfm.write(32'(REG_RULE_PARAM0) + 32'(4 * k), PARAMS[k]);
    bfm.write({24'h0, REG_CTRL}, 32'(1) << CTRL_RUN);
    for (int unsigned g = 1; g <= gens; g++) begin
      if (sink_req == 0 || g == 1) bfm.write({24'h0, REG_FRAME_REQ}, 1);
      if (midpass != 0 && g == 2) begin
        while (!dut.i_ctrl.active) @(negedge aclk);
        bfm.write({24'h0, REG_RULE_PARAM0}, PARAMS[0] + 7);
      end
      while (dut.gen_count != g) @(negedge aclk);
      // The stream of this pass carried the previous generation, which now
      // sits in the back buffer.
      if (i_sink.frames_seen != g) $fatal(1, "generation %0d: sink saw %0d frames", g, i_sink.frames_seen);
      for (longint unsigned w = 0; w < FRAME_BYTES / BYTES; w++) begin
        if (i_sink.frame[w] != i_mem.mem[((dut.front ? BUF0 : BUF1) / BYTES) + w])
          $fatal(1, "generation %0d: streamed word %0d differs from the front buffer", g, w);
      end
      if (in_list(dump_gens, g))
        i_mem.dump_hex($sformatf("%sgen_%05d.hex", dump_dir, g), dut.front ? BUF1 : BUF0, FRAME_BYTES);
    end
    $display("TB_PASS gens=%0d passes=%0d", gens, dut.pass_count);
    $finish;
  end

  initial begin
    longint unsigned max_cycles = 64'd50_000_000;
    void'($value$plusargs("max_cycles=%d", max_cycles));
    repeat (max_cycles) @(posedge aclk);
    $fatal(1, "timeout: gen_count=%0d pass_count=%0d", dut.gen_count, dut.pass_count);
  end
endmodule
