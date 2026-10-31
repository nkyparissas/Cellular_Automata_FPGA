// CA core testbench. The configuration comes from ca_cfg.svh (tools/gen_cfg.py).
//   +seed_hex=<file> +gens=<n> +dump_gens=<a,b,...,> +dump_dir=<dir/>
//   +mem_stall +mem_lat +sink_stall +sink_req=<0|1> +aclk_ps +eclk_ps
//   +midpass_param=1   change RULE_PARAM[0] by +7 while pass 2 runs
//   +max_kcycles=<n>   watchdog, thousands of aclk cycles (default 50000)
//   +gpf=<n>           GENS_PER_FRAME n, FRAME_REQ every n generations, stream check skipped
// Lenia cores:
//   +growth_hex=<f> +growth_sh=<n>    table (one entry per line) and shift, written and committed before RUN
//   +growth2_hex=<f> +growth2_sh=<n>  second table, written to the then inactive bank before RUN
//   +growth2_gen=<g>                  commit the second table while generation g's pass runs, or with
//   +growth2_sweep=<k>                start the commit once generation g is complete and pulse frame_req_i
//                                     k cycles later (the next pass starts around the commit)
//   +kernel_hex=<f>                   class weights, class 0 first, written while RUN is clear
//   +no_wait_kernel=1                 set RUN and request at once after the kernel writes
//   +kernel_busy=1                    write KERNEL_DATA while pass 2 runs (must be ignored)
// Prints TB_GROWTH_GEN=<GROWTH_GEN> at the end; fails if a pass starts while KERNEL_PENDING is set.
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
  logic              tb_req = 1'b0;

  axi_mem_model #(.DATA_W(DATA_W), .ADDR_W(32), .ID_W(1), .MEM_BYTES(MEM_BYTES),
                  .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t)) i_mem (
    .clk_i(aclk), .rst_ni(rst_n), .req_i(mreq), .resp_o(mresp));
  axis_sink_model #(.DATA_W(DATA_W), .BEATS_PER_ROW(WPR), .ROWS(GRID_Y)) i_sink (
    .clk_i(aclk), .rst_ni(rst_n), .tdata_i(tdata), .tvalid_i(tvalid), .tready_o(tready),
    .tlast_i(tlast), .tuser_i(tuser), .frame_req_o(frame_req));
  axil_bfm #(.axil_req_t(axil_req_t), .axil_resp_t(axil_resp_t)) bfm (.clk_i(aclk), .req_o(lreq), .resp_i(lresp));

  ca_core #(.GRID_X(GRID_X), .GRID_Y(GRID_Y), .CELL_W(CELL_W), .NBH(NBH), .BOUNDARY(BND), .RULE(RULE),
            .MASK(MASK), .DATA_W(DATA_W), .ADDR_W(32), .MAX_BURST(64), .FIFO_ROWS(2),
            .BUF0_DEFAULT(BUF0), .BUF1_DEFAULT(BUF1), .PARAM_DEFAULTS(PARAMS), .WEIGHT_W(WEIGHT_W),
            .LUT_IDX_W(LUT_IDX_W), .KERNEL_DEFAULT(KERNEL_DEFAULT), .GROWTH_INIT(GROWTH_INIT),
            .GROWTH_SH_DEFAULT(GROWTH_SH),
            .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t), .axil_req_t(axil_req_t),
            .axil_resp_t(axil_resp_t)) dut (
    .aclk_i(aclk), .arst_ni(rst_n), .eclk_i(eclk), .erst_ni(rst_n),
    .s_axil_req_i(lreq), .s_axil_resp_o(lresp), .m_axi_req_o(mreq), .m_axi_resp_i(mresp),
    .m_axis_tdata_o(tdata), .m_axis_tvalid_o(tvalid), .m_axis_tready_i(tready),
    .m_axis_tlast_o(tlast), .m_axis_tuser_o(tuser), .frame_req_i(frame_req || tb_req), .pass_done_o(pass_done));

  always @(posedge aclk) begin
    if (RULE == RULE_LENIA && rst_n && dut.pass_start && dut.kern_pending)
      $fatal(1, "a pass started while KERNEL_PENDING was set");
  end

  task automatic upload_table(string file, int unsigned sh);
    int          fd = $fopen(file, "r");
    int unsigned idx = 0;
    logic [31:0] v;
    if (fd == 0) $fatal(1, "cannot open %s", file);
    while ($fscanf(fd, "%h", v) == 1) begin
      bfm.write(32'(REG_GROWTH_TABLE) + 32'(4 * idx), v);
      idx++;
    end
    $fclose(fd);
    bfm.write(32'(REG_GROWTH_SHIFT), 32'(sh));
  endtask

  task automatic wait_status_clear(int unsigned bit_i);
    logic [31:0] st;
    do bfm.read(32'(REG_STATUS), st); while (st[bit_i]);
  endtask

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

  string seed_hex, dump_dir, dump_gens, kernel_hex, growth_hex, growth2_hex;
  initial begin
    int unsigned gens = 1, sink_req = 0, midpass = 0, gpf = 1, growth_sh = 0, growth2_sh = 0, growth2_gen = 0;
    int unsigned no_wait_kernel = 0, kernel_busy = 0;
    int          sweep = -1;
    logic [31:0] st, v;
    if (!$value$plusargs("seed_hex=%s", seed_hex)) $fatal(1, "+seed_hex missing");
    void'($value$plusargs("gens=%d", gens));
    if (!$value$plusargs("dump_gens=%s", dump_gens)) dump_gens = "";
    if (!$value$plusargs("dump_dir=%s", dump_dir)) dump_dir = "./";
    void'($value$plusargs("sink_req=%d", sink_req));
    void'($value$plusargs("midpass_param=%d", midpass));
    void'($value$plusargs("gpf=%d", gpf));
    if (!$value$plusargs("kernel_hex=%s", kernel_hex)) kernel_hex = "";
    if (!$value$plusargs("growth_hex=%s", growth_hex)) growth_hex = "";
    if (!$value$plusargs("growth2_hex=%s", growth2_hex)) growth2_hex = "";
    void'($value$plusargs("growth_sh=%d", growth_sh));
    void'($value$plusargs("growth2_sh=%d", growth2_sh));
    void'($value$plusargs("growth2_gen=%d", growth2_gen));
    void'($value$plusargs("growth2_sweep=%d", sweep));
    void'($value$plusargs("no_wait_kernel=%d", no_wait_kernel));
    void'($value$plusargs("kernel_busy=%d", kernel_busy));
    i_mem.load_hex(seed_hex, BUF0);
    if (BND == BND_CYLINDRICAL || BND == BND_RECTANGULAR) i_mem.load_hex(seed_hex, BUF1);
    repeat (5) @(posedge aclk);
    rst_n = 1;
    repeat (5) @(posedge aclk);
    bfm.write(32'(REG_BUF0_LO), 32'(BUF0));
    bfm.write(32'(REG_BUF1_LO), 32'(BUF1));
    bfm.write(32'(REG_FRAME_REPEAT), 0);
    bfm.write(32'(REG_GENS_PER_FRAME), gpf);
    for (int k = 0; k < NUM_RULE_PARAMS; k++) bfm.write(32'(REG_RULE_PARAM0) + 32'(4 * k), PARAMS[k]);
    if (growth_hex != "") begin
      upload_table(growth_hex, growth_sh);
      bfm.write(32'(REG_GROWTH_COMMIT), 1);
      wait_status_clear(ST_GROWTH_PENDING);
    end
    if (growth2_hex != "") upload_table(growth2_hex, growth2_sh);
    if (kernel_hex != "") begin
      int fd = $fopen(kernel_hex, "r");
      if (fd == 0) $fatal(1, "cannot open %s", kernel_hex);
      while ($fscanf(fd, "%h", v) == 1) bfm.write(32'(REG_KERNEL_DATA), v);
      $fclose(fd);
      if (no_wait_kernel == 0) wait_status_clear(ST_KERNEL_PENDING);
    end
    bfm.write(32'(REG_CTRL), 32'(1) << CTRL_RUN);
    for (int unsigned g = 1; g <= gens; g++) begin
      if (sweep >= 0 && growth2_gen != 0 && g == growth2_gen + 1) begin
        fork
          bfm.write(32'(REG_GROWTH_COMMIT), 1);
          begin
            repeat (sweep) @(posedge aclk);
            @(negedge aclk);
            tb_req = 1'b1;
            @(negedge aclk);
            tb_req = 1'b0;
          end
        join
      end else if ((sink_req == 0 || g == 1) && (g - 1) % gpf == 0) begin
        bfm.write(32'(REG_FRAME_REQ), 1);
      end
      if (sweep < 0 && growth2_gen != 0 && g == growth2_gen) begin
        while (!dut.i_ctrl.active) @(negedge aclk);
        bfm.write(32'(REG_GROWTH_COMMIT), 1);
      end
      if (kernel_busy != 0 && g == 2) begin
        while (!dut.i_ctrl.active) @(negedge aclk);
        bfm.write(32'(REG_KERNEL_DATA), 32'h3F);
        bfm.read(32'(REG_STATUS), st);
        if (st[ST_KERNEL_PENDING]) $fatal(1, "a kernel word was accepted while a pass ran");
      end
      if (midpass != 0 && g == 2) begin
        while (!dut.i_ctrl.active) @(negedge aclk);
        bfm.write(32'(REG_RULE_PARAM0), PARAMS[0] + 7);
      end
      while (dut.gen_count != g) @(negedge aclk);
      // The stream of this pass carried the previous generation, which now
      // sits in the back buffer (fast-forward passes do not stream).
      if (gpf == 1) begin
        if (i_sink.frames_seen != g) $fatal(1, "generation %0d: sink saw %0d frames", g, i_sink.frames_seen);
        for (longint unsigned w = 0; w < FRAME_BYTES / BYTES; w++) begin
          if (i_sink.frame[w] != i_mem.mem[((dut.front ? BUF0 : BUF1) / BYTES) + w])
            $fatal(1, "generation %0d: streamed word %0d differs from the front buffer", g, w);
        end
      end
      if (in_list(dump_gens, g))
        i_mem.dump_hex($sformatf("%sgen_%05d.hex", dump_dir, g), dut.front ? BUF1 : BUF0, FRAME_BYTES);
    end
    bfm.read(32'(REG_GROWTH_GEN), v);
    $display("TB_GROWTH_GEN=%0d", v);
    $display("TB_PASS gens=%0d passes=%0d", gens, dut.pass_count);
    $finish;
  end

  // Watchdog in thousands of aclk cycles (+max_kcycles), which keeps long
  // runs within 32-bit plusarg parsing.
  initial begin
    int unsigned max_kcycles = 50_000;
    void'($value$plusargs("max_kcycles=%d", max_kcycles));
    repeat (max_kcycles) repeat (1000) @(posedge aclk);
    $fatal(1, "timeout: gen_count=%0d pass_count=%0d", dut.gen_count, dut.pass_count);
  end
endmodule
