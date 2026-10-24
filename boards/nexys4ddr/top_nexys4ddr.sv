// Digilent Nexys 4 DDR top level: clocks, DDR2 MIG (AXI4), VGA, UART, buttons.
// Everything board-independent lives in rtl/top/ca_display_system.sv.
// The CA configuration comes from ca_cfg.svh (tools/gen_cfg.py) on the include path.
module top_nexys4ddr (
  input  logic        CLK100MHZ,
  input  logic        CPU_RESETN,
  input  logic        BTNU,
  input  logic        BTND,
  input  logic        BTNL,
  output logic [3:0]  VGA_R,
  output logic [3:0]  VGA_G,
  output logic [3:0]  VGA_B,
  output logic        VGA_HS,
  output logic        VGA_VS,
  input  logic        UART_TXD_IN,     // FPGA receive
  output logic        UART_RXD_OUT,    // FPGA transmit
  output logic [3:0]  LED,
  inout  wire  [15:0] ddr2_dq,
  inout  wire  [1:0]  ddr2_dqs_p,
  inout  wire  [1:0]  ddr2_dqs_n,
  output logic [12:0] ddr2_addr,
  output logic [2:0]  ddr2_ba,
  output logic        ddr2_ras_n,
  output logic        ddr2_cas_n,
  output logic        ddr2_we_n,
  output logic [0:0]  ddr2_ck_p,
  output logic [0:0]  ddr2_ck_n,
  output logic [0:0]  ddr2_cke,
  output logic [1:0]  ddr2_dm,
  output logic [0:0]  ddr2_odt
);
  `include "ca_cfg.svh"

  localparam int unsigned UI_HZ = 81_250_000;   // MIG 4:1 at 325 MHz memory clock
  localparam int unsigned MID_W = 2;

  // ------------------------------------------------------------- clocks
  logic clk_ref_200, clk_sys_325, clk_pix_148, clk_locked;
  clk_wiz_ca i_clk (
    .clk_in1(CLK100MHZ), .reset(!CPU_RESETN), .locked(clk_locked),
    .clk_ref_200(clk_ref_200), .clk_sys_325(clk_sys_325), .clk_pix_148(clk_pix_148));

  logic ui_clk, ui_rst, calib_done, mmcm_locked, sys_ok;
  assign sys_ok = clk_locked && CPU_RESETN;

  // ------------------------------------------------------- memory (MIG)
  logic [MID_W-1:0]  awid, bid, arid, rid;
  logic [31:0]       awaddr, araddr;
  logic [7:0]        awlen, arlen;
  logic [2:0]        awsize, arsize, awprot, arprot;
  logic [1:0]        awburst, arburst, bresp, rresp;
  logic              awlock, arlock, awvalid, awready, wlast, wvalid, wready, bvalid, bready;
  logic              arvalid, arready, rlast, rvalid, rready;
  logic [3:0]        awcache, arcache, awqos, arqos;
  logic [DATA_W-1:0] wdata, rdata;
  logic [DATA_W/8-1:0] wstrb;
  logic [3:0]        bid_w, rid_w;              // MIG ID width is 4
  logic              sr_active, ref_ack, zq_ack;
  logic [11:0]       device_temp;

  mig_ddr2_axi i_mig (
    .ddr2_dq, .ddr2_dqs_p, .ddr2_dqs_n, .ddr2_addr, .ddr2_ba, .ddr2_ras_n, .ddr2_cas_n, .ddr2_we_n,
    .ddr2_ck_p, .ddr2_ck_n, .ddr2_cke, .ddr2_dm, .ddr2_odt,
    .sys_clk_i(clk_sys_325), .clk_ref_i(clk_ref_200), .sys_rst(sys_ok),   // active low (see ip/mig_ddr2_axi.prj)
    .ui_clk(ui_clk), .ui_clk_sync_rst(ui_rst), .mmcm_locked(mmcm_locked), .aresetn(!ui_rst),
    .app_sr_req(1'b0), .app_ref_req(1'b0), .app_zq_req(1'b0),
    .app_sr_active(sr_active), .app_ref_ack(ref_ack), .app_zq_ack(zq_ack), .init_calib_complete(calib_done),
    .s_axi_awid({2'b0, awid}), .s_axi_awaddr(awaddr[26:0]), .s_axi_awlen(awlen), .s_axi_awsize(awsize),
    .s_axi_awburst(awburst), .s_axi_awlock(awlock), .s_axi_awcache(awcache), .s_axi_awprot(awprot),
    .s_axi_awqos(awqos), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bid(bid_w), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axi_arid({2'b0, arid}), .s_axi_araddr(araddr[26:0]), .s_axi_arlen(arlen), .s_axi_arsize(arsize),
    .s_axi_arburst(arburst), .s_axi_arlock(arlock), .s_axi_arcache(arcache), .s_axi_arprot(arprot),
    .s_axi_arqos(arqos), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rid(rid_w), .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rlast(rlast), .s_axi_rvalid(rvalid),
    .s_axi_rready(rready), .device_temp(device_temp));
  assign bid = bid_w[MID_W-1:0];
  assign rid = rid_w[MID_W-1:0];

  // ------------------------------------------------- CA display system
  logic hsync, vsync, de, underflow, pass_done;
  logic [23:0] rgb;
  logic run_rst_n, pix_rst_n, eng_rst_n;
  assign run_rst_n = !ui_rst && calib_done;
  ca_reset_sync i_prst (.clk_i(clk_pix_148), .arst_ni(run_rst_n), .rst_no(pix_rst_n));
  ca_reset_sync i_erst (.clk_i(clk_ref_200), .arst_ni(run_rst_n), .rst_no(eng_rst_n));

  ca_display_system #(.GRID_X(GRID_X), .GRID_Y(GRID_Y), .CELL_W(CELL_W), .NBH(NBH),
                      .BOUNDARY(ca_pkg::boundary_e'(BND_ID)), .RULE(ca_pkg::rule_e'(RULE_ID)),
                      .MASK(MASK), .PARAMS(PARAMS), .DATA_W(DATA_W), .ADDR_W(32),
                      .BUF0(64'h0), .BUF1(64'h0100_0000), .ACLK_HZ(UI_HZ), .BAUD(2_000_000),
                      .DEBOUNCE_MS(20), .SLOW_REPEAT(59), .PALETTE(CELL_W == 8 ? "legacy8" : "legacy4_windows")) i_sys (
    .aclk(ui_clk), .aresetn(run_rst_n), .eclk(clk_ref_200), .eresetn(eng_rst_n),
    .pclk(clk_pix_148), .presetn(pix_rst_n),
    .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
    .m_axi_awburst(awburst), .m_axi_awlock(awlock), .m_axi_awcache(awcache), .m_axi_awprot(awprot),
    .m_axi_awqos(awqos), .m_axi_awvalid(awvalid), .m_axi_awready(awready), .m_axi_wdata(wdata),
    .m_axi_wstrb(wstrb), .m_axi_wlast(wlast), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
    .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
    .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
    .m_axi_arburst(arburst), .m_axi_arlock(arlock), .m_axi_arcache(arcache), .m_axi_arprot(arprot),
    .m_axi_arqos(arqos), .m_axi_arvalid(arvalid), .m_axi_arready(arready), .m_axi_rid(rid),
    .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast), .m_axi_rvalid(rvalid),
    .m_axi_rready(rready),
    .uart_rxd(UART_TXD_IN), .uart_txd(UART_RXD_OUT), .btn_up(BTNU), .btn_down(BTND), .btn_pause(BTNL),
    .hsync, .vsync, .de, .rgb, .underflow, .pass_done);

  // 4-bit VGA DAC.
  assign VGA_R  = rgb[23:20];
  assign VGA_G  = rgb[15:12];
  assign VGA_B  = rgb[7:4];
  assign VGA_HS = hsync;
  assign VGA_VS = vsync;

  logic pass_led;
  always_ff @(posedge ui_clk) if (pass_done) pass_led <= !pass_led;
  assign LED = {underflow, pass_led, mmcm_locked, calib_done};

  // Outputs this board does not use (VGA needs no DE and only 4 bits per colour; 128 MB needs 27 address bits).
  /* verilator lint_off UNUSEDSIGNAL */
  logic unused;
  assign unused = ^{awaddr[31:27], araddr[31:27], bid_w[3:2], rid_w[3:2], de, sr_active, ref_ack,
                    zq_ack, device_temp, rgb[19:16], rgb[11:8], rgb[3:0]};
  /* verilator lint_on UNUSEDSIGNAL */
endmodule
