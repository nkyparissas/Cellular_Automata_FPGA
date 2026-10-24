// ca_display_system testbench with a 64x24 grid and a small video timing.
//   +case=protocol  UART bridge: register and memory write/read-back
//   +case=debounce  button bounce shorter than the debounce time is ignored
//   +case=system    seed over UART, "up" button, RUN, display-driven passes,
//                   "pause" button, frame read back over UART (+out_file)
`timescale 1ns/1ps
module tb_display;
  import ca_regs_pkg::*;
  localparam int unsigned GX = 64, GY = 24, CW = 8, NBH = 5, DW = 128, BYTES = DW / 8;
  localparam int unsigned FRAME = GX * GY * CW / 8;
  localparam int unsigned ACLK_HZ = 100_000_000, BAUD = ACLK_HZ / 16, BIT = ACLK_HZ / BAUD;
  localparam logic [63:0] BUF0 = 64'h0, BUF1 = 64'h1000;
  localparam ca_pkg::rule_params_t PARAMS = {32'd0, 32'd0, 32'd0, 32'd0, 32'd0, 32'd0, 32'd3, 32'd20};

  logic aclk = 0, eclk = 0, pclk = 0, rst_n = 0;
  always #5 aclk = ~aclk;
  always #2.5 eclk = ~eclk;
  always #4 pclk = ~pclk;

  // Flat memory port -> memory model (ID width 2 after the mux).
  `include "axi/typedef.svh"
  typedef logic [31:0] addr_t;
  typedef logic [1:0]  id_t;
  typedef logic [DW-1:0] data_t;
  typedef logic [BYTES-1:0] strb_t;
  typedef logic [0:0] user_t;
  `AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, user_t)
  axi_req_t  mreq;
  axi_resp_t mresp;
  axi_mem_model #(.DATA_W(DW), .ADDR_W(32), .ID_W(2), .MEM_BYTES(64'd65536),
                  .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t)) i_mem (
    .clk_i(aclk), .rst_ni(rst_n), .req_i(mreq), .resp_o(mresp));

  logic rxd = 1, txd, up = 0, down = 0, pause = 0, hs, vs, de, underflow, pass_done;
  logic [23:0] rgb;

  ca_display_system #(.GRID_X(GX), .GRID_Y(GY), .CELL_W(CW), .NBH(NBH), .BOUNDARY(ca_pkg::BND_TOROIDAL),
                      .RULE(ca_pkg::RULE_HODGEPODGE), .PARAMS(PARAMS), .DATA_W(DW), .ADDR_W(32),
                      .BUF0(BUF0), .BUF1(BUF1), .ACLK_HZ(ACLK_HZ), .BAUD(BAUD), .DEBOUNCE_MS(1),
                      .SLOW_REPEAT(59), .H_FP(4), .H_SYNC(4), .H_BP(4), .V_FP(2), .V_SYNC(2), .V_BP(2),
                      .PALETTE("legacy8")) dut (
    .aclk, .aresetn(rst_n), .eclk, .eresetn(rst_n), .pclk, .presetn(rst_n),
    .m_axi_awid(mreq.aw.id), .m_axi_awaddr(mreq.aw.addr), .m_axi_awlen(mreq.aw.len),
    .m_axi_awsize(mreq.aw.size), .m_axi_awburst(mreq.aw.burst), .m_axi_awlock(mreq.aw.lock),
    .m_axi_awcache(mreq.aw.cache), .m_axi_awprot(mreq.aw.prot), .m_axi_awqos(mreq.aw.qos),
    .m_axi_awvalid(mreq.aw_valid), .m_axi_awready(mresp.aw_ready), .m_axi_wdata(mreq.w.data),
    .m_axi_wstrb(mreq.w.strb), .m_axi_wlast(mreq.w.last), .m_axi_wvalid(mreq.w_valid),
    .m_axi_wready(mresp.w_ready), .m_axi_bid(mresp.b.id), .m_axi_bresp(mresp.b.resp),
    .m_axi_bvalid(mresp.b_valid), .m_axi_bready(mreq.b_ready), .m_axi_arid(mreq.ar.id),
    .m_axi_araddr(mreq.ar.addr), .m_axi_arlen(mreq.ar.len), .m_axi_arsize(mreq.ar.size),
    .m_axi_arburst(mreq.ar.burst), .m_axi_arlock(mreq.ar.lock), .m_axi_arcache(mreq.ar.cache),
    .m_axi_arprot(mreq.ar.prot), .m_axi_arqos(mreq.ar.qos), .m_axi_arvalid(mreq.ar_valid),
    .m_axi_arready(mresp.ar_ready), .m_axi_rid(mresp.r.id), .m_axi_rdata(mresp.r.data),
    .m_axi_rresp(mresp.r.resp), .m_axi_rlast(mresp.r.last), .m_axi_rvalid(mresp.r_valid),
    .m_axi_rready(mreq.r_ready),
    .uart_rxd(rxd), .uart_txd(txd), .btn_up(up), .btn_down(down), .btn_pause(pause),
    .hsync(hs), .vsync(vs), .de(de), .rgb(rgb), .underflow(underflow), .pass_done(pass_done));
  // Fields without flat ports.
  assign mreq.aw.region = '0;
  assign mreq.aw.atop   = '0;
  assign mreq.aw.user   = '0;
  assign mreq.w.user    = '0;
  assign mreq.ar.region = '0;
  assign mreq.ar.user   = '0;

  // ------------------------------------------------------------ UART BFM
  task automatic send_byte(input logic [7:0] b);
    rxd = 0;
    repeat (BIT) @(posedge aclk);
    for (int i = 0; i < 8; i++) begin
      rxd = b[i];
      repeat (BIT) @(posedge aclk);
    end
    rxd = 1;
    repeat (BIT) @(posedge aclk);
  endtask
  task automatic recv_byte(output logic [7:0] b);
    while (txd) @(posedge aclk);
    repeat (BIT / 2) @(posedge aclk);
    for (int i = 0; i < 8; i++) begin
      repeat (BIT) @(posedge aclk);
      b[i] = txd;
    end
    repeat (BIT) @(posedge aclk);
  endtask
  task automatic send_word(input logic [31:0] w);
    for (int i = 0; i < 4; i++) send_byte(w[8*i +: 8]);
  endtask
  task automatic expect_byte(input logic [7:0] e);
    logic [7:0] b;
    recv_byte(b);
    if (b != e) $fatal(1, "UART reply 0x%0h, expected 0x%0h", b, e);
  endtask
  task automatic reg_write(input logic [7:0] a, input logic [31:0] d);
    send_byte(8'h10); send_word({24'h0, a}); send_word(d);
    expect_byte(8'h10);
  endtask
  task automatic reg_read(input logic [7:0] a, output logic [31:0] d);
    send_byte(8'h11); send_word({24'h0, a});
    expect_byte(8'h11);
    for (int i = 0; i < 4; i++) recv_byte(d[8*i +: 8]);
  endtask
  task automatic mem_write(input logic [31:0] a, input logic [7:0] data [], input int n);
    send_byte(8'h20); send_word(a); send_word(n);
    for (int i = 0; i < n; i++) send_byte(data[i]);
    expect_byte(8'h20);
  endtask
  task automatic mem_read(input logic [31:0] a, input int n, output logic [7:0] data []);
    data = new[n];
    send_byte(8'h21); send_word(a); send_word(n);
    expect_byte(8'h21);
    for (int i = 0; i < n; i++) recv_byte(data[i]);
  endtask
  task automatic press(ref logic btn, input int cycles);
    btn = 1;
    repeat (cycles) @(posedge aclk);
    btn = 0;
    repeat (cycles) @(posedge aclk);
  endtask

  localparam int unsigned DEB = ACLK_HZ / 1000;     // DEBOUNCE_MS = 1
  string tc, seed_hex, out_file;
  initial begin
    logic [31:0] d;
    logic [7:0]  bytes [], back [];
    if (!$value$plusargs("case=%s", tc)) $fatal(1, "+case missing");
    repeat (5) @(posedge aclk);
    rst_n = 1;
    repeat (20) @(posedge aclk);
    case (tc)
      "protocol": begin
        reg_read(REG_ID, d);
        if (d != CA_ID) $fatal(1, "ID 0x%0h", d);
        reg_write(REG_FRAME_REPEAT, 32'h1234);
        reg_read(REG_FRAME_REPEAT, d);
        if (d != 32'h1234) $fatal(1, "FRAME_REPEAT 0x%0h", d);
        bytes = new[64];
        foreach (bytes[i]) bytes[i] = 8'(i * 7 + 3);
        mem_write(32'h2000, bytes, 64);
        mem_read(32'h2000, 64, back);
        foreach (bytes[i]) if (back[i] != bytes[i]) $fatal(1, "memory byte %0d", i);
        if (i_mem.mem[32'h2000 / BYTES][7:0] != 8'd3) $fatal(1, "little-endian layout broken");
      end
      "debounce": begin
        reg_read(REG_FRAME_REPEAT, d);
        if (d != 59) $fatal(1, "reset FRAME_REPEAT %0d", d);
        repeat (5) press(up, DEB / 4);           // bounce: too short to count
        reg_read(REG_FRAME_REPEAT, d);
        if (d != 59) $fatal(1, "bounce was taken as a press (FRAME_REPEAT %0d)", d);
        press(up, 3 * DEB);
        reg_read(REG_FRAME_REPEAT, d);
        if (d != 0) $fatal(1, "press ignored (FRAME_REPEAT %0d)", d);
        press(down, 3 * DEB);
        reg_read(REG_FRAME_REPEAT, d);
        if (d != 59) $fatal(1, "down press ignored (FRAME_REPEAT %0d)", d);
      end
      "system": begin
        int unsigned g, g2;
        logic [7:0] seed [FRAME];
        if (!$value$plusargs("seed_hex=%s", seed_hex)) $fatal(1, "+seed_hex missing");
        if (!$value$plusargs("out_file=%s", out_file)) $fatal(1, "+out_file missing");
        $readmemh(seed_hex, seed);
        bytes = new[FRAME];
        foreach (bytes[i]) bytes[i] = seed[i];
        mem_write(32'(BUF0), bytes, FRAME);
        press(up, 3 * DEB);                       // one generation per displayed frame
        reg_write(REG_CTRL, 32'(1) << CTRL_RUN);
        while (dut.i_core.gen_count < 3) @(posedge aclk);
        press(pause, 3 * DEB);
        reg_read(REG_GEN_COUNT, g);
        repeat (6 * 76 * 30 * 2) @(posedge aclk);  // several video frames
        reg_read(REG_GEN_COUNT, g2);
        if (g2 != g) $fatal(1, "generations advanced while paused (%0d -> %0d)", g, g2);
        reg_read(REG_STATUS, d);
        mem_read(d[ST_FRONT] ? 32'(BUF1) : 32'(BUF0), FRAME, back);
        begin
          int fd = $fopen(out_file, "w");
          foreach (back[i]) $fwrite(fd, "%02h\n", back[i]);
          $fclose(fd);
        end
        if (underflow) $display("note: display underflow seen");
        $display("TB_GEN %0d", g);
      end
      default: $fatal(1, "unknown case %s", tc);
    endcase
    $display("TB_PASS case=%s", tc);
    $finish;
  end

  initial begin
    repeat (20_000_000) @(posedge aclk);
    $fatal(1, "timeout in case %s", tc);
  end
endmodule
