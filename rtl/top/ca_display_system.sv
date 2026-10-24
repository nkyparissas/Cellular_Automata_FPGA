// Board-independent system for display boards (spec Section 14):
//   ca_core + ca_video_out (frame requests come from the display)
//   + ca_uart_bridge (seed upload, frame download, register access)
//   + ca_buttons_axil (speed/pause), joined with pulp axi_mux / axi_lite_mux.
// The memory port is a flat AXI4 master for a memory controller (e.g. MIG);
// its ID is one bit wider than the core's because of the mux.
`include "axi/typedef.svh"
module ca_display_system #(
  parameter int unsigned          GRID_X       = 1920,
  parameter int unsigned          GRID_Y       = 1080,
  parameter int unsigned          CELL_W       = 8,
  parameter int unsigned          NBH          = 29,
  parameter ca_pkg::boundary_e    BOUNDARY     = ca_pkg::BND_TOROIDAL,
  parameter ca_pkg::rule_e        RULE         = ca_pkg::RULE_HODGEPODGE,
  parameter logic [NBH*NBH-1:0]   MASK         = '1,
  parameter ca_pkg::rule_params_t PARAMS       = '0,
  parameter int unsigned          DATA_W       = 128,
  parameter int unsigned          ADDR_W       = 32,
  parameter logic [63:0]          BUF0         = 64'h0,
  parameter logic [63:0]          BUF1         = 64'h0100_0000,
  parameter int unsigned          ACLK_HZ      = 100_000_000,
  parameter int unsigned          BAUD         = 2_000_000,
  parameter int unsigned          DEBOUNCE_MS  = 20,
  parameter int unsigned          SLOW_REPEAT  = 59,
  parameter int unsigned          H_FP         = 88,
  parameter int unsigned          H_SYNC       = 44,
  parameter int unsigned          H_BP         = 148,
  parameter int unsigned          V_FP         = 4,
  parameter int unsigned          V_SYNC       = 5,
  parameter int unsigned          V_BP         = 36,
  parameter string                PALETTE      = "legacy8",
  localparam int unsigned         MID_W        = 2
) (
  input  logic                aclk,      // memory controller user clock
  input  logic                aresetn,
  input  logic                eclk,
  input  logic                eresetn,
  input  logic                pclk,
  input  logic                presetn,
  // AXI4 master to the memory controller
  output logic [MID_W-1:0]    m_axi_awid,
  output logic [ADDR_W-1:0]   m_axi_awaddr,
  output logic [7:0]          m_axi_awlen,
  output logic [2:0]          m_axi_awsize,
  output logic [1:0]          m_axi_awburst,
  output logic                m_axi_awlock,
  output logic [3:0]          m_axi_awcache,
  output logic [2:0]          m_axi_awprot,
  output logic [3:0]          m_axi_awqos,
  output logic                m_axi_awvalid,
  input  logic                m_axi_awready,
  output logic [DATA_W-1:0]   m_axi_wdata,
  output logic [DATA_W/8-1:0] m_axi_wstrb,
  output logic                m_axi_wlast,
  output logic                m_axi_wvalid,
  input  logic                m_axi_wready,
  input  logic [MID_W-1:0]    m_axi_bid,
  input  logic [1:0]          m_axi_bresp,
  input  logic                m_axi_bvalid,
  output logic                m_axi_bready,
  output logic [MID_W-1:0]    m_axi_arid,
  output logic [ADDR_W-1:0]   m_axi_araddr,
  output logic [7:0]          m_axi_arlen,
  output logic [2:0]          m_axi_arsize,
  output logic [1:0]          m_axi_arburst,
  output logic                m_axi_arlock,
  output logic [3:0]          m_axi_arcache,
  output logic [2:0]          m_axi_arprot,
  output logic [3:0]          m_axi_arqos,
  output logic                m_axi_arvalid,
  input  logic                m_axi_arready,
  input  logic [MID_W-1:0]    m_axi_rid,
  input  logic [DATA_W-1:0]   m_axi_rdata,
  input  logic [1:0]          m_axi_rresp,
  input  logic                m_axi_rlast,
  input  logic                m_axi_rvalid,
  output logic                m_axi_rready,
  // Board I/O
  input  logic                uart_rxd,
  output logic                uart_txd,
  input  logic                btn_up,
  input  logic                btn_down,
  input  logic                btn_pause,
  output logic                hsync,
  output logic                vsync,
  output logic                de,
  output logic [23:0]         rgb,
  output logic                underflow,
  output logic                pass_done
);
  typedef logic [ADDR_W-1:0]   addr_t;
  typedef logic [0:0]          sid_t;
  typedef logic [MID_W-1:0]    mid_t;
  typedef logic [DATA_W-1:0]   data_t;
  typedef logic [DATA_W/8-1:0] strb_t;
  typedef logic [0:0]          user_t;
  typedef logic [31:0]         laddr_t;
  typedef logic [31:0]         ldata_t;
  typedef logic [3:0]          lstrb_t;
  `AXI_TYPEDEF_ALL(slv, addr_t, sid_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_ALL(mst, addr_t, mid_t, data_t, strb_t, user_t)
  `AXI_LITE_TYPEDEF_ALL(axil, laddr_t, ldata_t, lstrb_t)

  logic a_rst_n;
  ca_reset_sync i_arst (.clk_i(aclk), .arst_ni(aresetn), .rst_no(a_rst_n));

  // --------------------------------------------------------------- core
  slv_req_t  [1:0] mem_reqs;      // [0] core, [1] UART bridge
  slv_resp_t [1:0] mem_resps;
  axil_req_t [1:0] reg_reqs;      // [0] UART bridge, [1] buttons
  axil_resp_t [1:0] reg_resps;
  axil_req_t  core_lreq;
  axil_resp_t core_lresp;
  logic [DATA_W-1:0] tdata;
  logic              tvalid, tready, tlast, tuser, frame_req;

  ca_core #(.GRID_X(GRID_X), .GRID_Y(GRID_Y), .CELL_W(CELL_W), .NBH(NBH), .BOUNDARY(BOUNDARY), .RULE(RULE),
            .MASK(MASK), .DATA_W(DATA_W), .ADDR_W(ADDR_W), .BUF0_DEFAULT(BUF0), .BUF1_DEFAULT(BUF1),
            .FRAME_REPEAT_DEFAULT(SLOW_REPEAT), .PARAM_DEFAULTS(PARAMS),
            .axi_req_t(slv_req_t), .axi_resp_t(slv_resp_t), .axil_req_t(axil_req_t),
            .axil_resp_t(axil_resp_t)) i_core (
    .aclk_i(aclk), .arst_ni(aresetn), .eclk_i(eclk), .erst_ni(eresetn),
    .s_axil_req_i(core_lreq), .s_axil_resp_o(core_lresp), .m_axi_req_o(mem_reqs[0]),
    .m_axi_resp_i(mem_resps[0]), .m_axis_tdata_o(tdata), .m_axis_tvalid_o(tvalid),
    .m_axis_tready_i(tready), .m_axis_tlast_o(tlast), .m_axis_tuser_o(tuser),
    .frame_req_i(frame_req), .pass_done_o(pass_done));

  // ------------------------------------------------------------- display
  ca_video_out #(.DATA_W(DATA_W), .CELL_W(CELL_W), .H_ACTIVE(GRID_X), .H_FP(H_FP), .H_SYNC(H_SYNC),
                 .H_BP(H_BP), .V_ACTIVE(GRID_Y), .V_FP(V_FP), .V_SYNC(V_SYNC), .V_BP(V_BP),
                 .HS_POL(1'b1), .VS_POL(1'b1), .REQ_LINE(GRID_Y + 1), .FIFO_DEPTH(256),
                 .PALETTE(PALETTE)) i_video (
    .aclk_i(aclk), .arst_ni(a_rst_n), .s_axis_tdata_i(tdata), .s_axis_tvalid_i(tvalid),
    .s_axis_tready_o(tready), .s_axis_tlast_i(tlast), .s_axis_tuser_i(tuser), .frame_req_o(frame_req),
    .pclk_i(pclk), .prst_ni(presetn), .hsync_o(hsync), .vsync_o(vsync), .de_o(de), .rgb_o(rgb),
    .underflow_o(underflow));

  // ---------------------------------------------------- UART and buttons
  ca_uart_bridge #(.CLK_HZ(ACLK_HZ), .BAUD(BAUD), .DATA_W(DATA_W), .ADDR_W(ADDR_W),
                   .axi_req_t(slv_req_t), .axi_resp_t(slv_resp_t), .axil_req_t(axil_req_t),
                   .axil_resp_t(axil_resp_t)) i_bridge (
    .clk_i(aclk), .rst_ni(a_rst_n), .rxd_i(uart_rxd), .txd_o(uart_txd),
    .m_axi_req_o(mem_reqs[1]), .m_axi_resp_i(mem_resps[1]),
    .m_axil_req_o(reg_reqs[0]), .m_axil_resp_i(reg_resps[0]));

  ca_buttons_axil #(.CLK_HZ(ACLK_HZ), .DEBOUNCE_MS(DEBOUNCE_MS), .SLOW_REPEAT(SLOW_REPEAT),
                    .axil_req_t(axil_req_t), .axil_resp_t(axil_resp_t)) i_buttons (
    .clk_i(aclk), .rst_ni(a_rst_n), .btn_up_i(btn_up), .btn_down_i(btn_down), .btn_pause_i(btn_pause),
    .m_axil_req_o(reg_reqs[1]), .m_axil_resp_i(reg_resps[1]));

  // --------------------------------------------------------- interconnect
  axi_lite_mux #(
    .aw_chan_t(axil_aw_chan_t), .w_chan_t(axil_w_chan_t), .b_chan_t(axil_b_chan_t),
    .ar_chan_t(axil_ar_chan_t), .r_chan_t(axil_r_chan_t), .axi_req_t(axil_req_t),
    .axi_resp_t(axil_resp_t), .NoSlvPorts(2), .MaxTrans(1)
  ) i_reg_mux (
    .clk_i(aclk), .rst_ni(a_rst_n), .test_i(1'b0), .slv_reqs_i(reg_reqs), .slv_resps_o(reg_resps),
    .mst_req_o(core_lreq), .mst_resp_i(core_lresp));

  mst_req_t  mreq;
  mst_resp_t mresp;
  axi_mux #(
    .SlvAxiIDWidth(1), .slv_aw_chan_t(slv_aw_chan_t), .mst_aw_chan_t(mst_aw_chan_t),
    .w_chan_t(slv_w_chan_t), .slv_b_chan_t(slv_b_chan_t), .mst_b_chan_t(mst_b_chan_t),
    .slv_ar_chan_t(slv_ar_chan_t), .mst_ar_chan_t(mst_ar_chan_t), .slv_r_chan_t(slv_r_chan_t),
    .mst_r_chan_t(mst_r_chan_t), .slv_req_t(slv_req_t), .slv_resp_t(slv_resp_t),
    .mst_req_t(mst_req_t), .mst_resp_t(mst_resp_t), .NoSlvPorts(2), .MaxWTrans(8)
  ) i_mem_mux (
    .clk_i(aclk), .rst_ni(a_rst_n), .test_i(1'b0), .slv_reqs_i(mem_reqs), .slv_resps_o(mem_resps),
    .mst_req_o(mreq), .mst_resp_i(mresp));

  assign m_axi_awid    = mreq.aw.id;
  assign m_axi_awaddr  = mreq.aw.addr;
  assign m_axi_awlen   = mreq.aw.len;
  assign m_axi_awsize  = mreq.aw.size;
  assign m_axi_awburst = mreq.aw.burst;
  assign m_axi_awlock  = mreq.aw.lock;
  assign m_axi_awcache = mreq.aw.cache;
  assign m_axi_awprot  = mreq.aw.prot;
  assign m_axi_awqos   = mreq.aw.qos;
  assign m_axi_awvalid = mreq.aw_valid;
  assign m_axi_wdata   = mreq.w.data;
  assign m_axi_wstrb   = mreq.w.strb;
  assign m_axi_wlast   = mreq.w.last;
  assign m_axi_wvalid  = mreq.w_valid;
  assign m_axi_bready  = mreq.b_ready;
  assign m_axi_arid    = mreq.ar.id;
  assign m_axi_araddr  = mreq.ar.addr;
  assign m_axi_arlen   = mreq.ar.len;
  assign m_axi_arsize  = mreq.ar.size;
  assign m_axi_arburst = mreq.ar.burst;
  assign m_axi_arlock  = mreq.ar.lock;
  assign m_axi_arcache = mreq.ar.cache;
  assign m_axi_arprot  = mreq.ar.prot;
  assign m_axi_arqos   = mreq.ar.qos;
  assign m_axi_arvalid = mreq.ar_valid;
  assign m_axi_rready  = mreq.r_ready;
  always_comb begin
    mresp          = '0;
    mresp.aw_ready = m_axi_awready;
    mresp.w_ready  = m_axi_wready;
    mresp.b.id     = m_axi_bid;
    mresp.b.resp   = m_axi_bresp;
    mresp.b_valid  = m_axi_bvalid;
    mresp.ar_ready = m_axi_arready;
    mresp.r.id     = m_axi_rid;
    mresp.r.data   = m_axi_rdata;
    mresp.r.resp   = m_axi_rresp;
    mresp.r.last   = m_axi_rlast;
    mresp.r_valid  = m_axi_rvalid;
  end
endmodule
