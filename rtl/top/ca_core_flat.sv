// ca_core with Xilinx-style flat AXI4 / AXI4-Lite / AXI4-Stream ports, for
// plain RTL board tops and Verilog/VHDL wrappers (a Vivado module reference
// must be Verilog or VHDL, see boards/xdma_template/ca_core_xdma.v). Every
// parameter is integral so that such wrappers can set it: BOUNDARY and RULE
// take the ca_pkg::boundary_e / rule_e values as integers.
`include "axi/typedef.svh"
module ca_core_flat #(
  parameter int unsigned          GRID_X               = 64,
  parameter int unsigned          GRID_Y               = 24,
  parameter int unsigned          CELL_W               = 8,
  parameter int unsigned          NBH                  = 5,
  parameter int unsigned          BOUNDARY             = 32'(ca_pkg::BND_TOROIDAL),
  parameter int unsigned          RULE                 = 32'(ca_pkg::RULE_HODGEPODGE),
  parameter logic [NBH*NBH-1:0]   MASK                 = '1,
  parameter int unsigned          DATA_W               = 128,
  parameter int unsigned          ADDR_W               = 32,
  parameter int unsigned          ID_W                 = 1,
  parameter int unsigned          MAX_BURST            = 64,
  parameter int unsigned          FIFO_ROWS            = 2,
  parameter logic [63:0]          BUF0_DEFAULT         = 64'h0,
  parameter logic [63:0]          BUF1_DEFAULT         = 64'h0100_0000,
  parameter int unsigned          FRAME_REPEAT_DEFAULT = 0,
  parameter ca_pkg::rule_params_t PARAM_DEFAULTS       = '0
) (
  input  logic                aclk,
  input  logic                aresetn,
  input  logic                eclk,
  input  logic                eresetn,
  // AXI4 master to memory
  output logic [ID_W-1:0]     m_axi_awid,
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
  input  logic [ID_W-1:0]     m_axi_bid,
  input  logic [1:0]          m_axi_bresp,
  input  logic                m_axi_bvalid,
  output logic                m_axi_bready,
  output logic [ID_W-1:0]     m_axi_arid,
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
  input  logic [ID_W-1:0]     m_axi_rid,
  input  logic [DATA_W-1:0]   m_axi_rdata,
  input  logic [1:0]          m_axi_rresp,
  input  logic                m_axi_rlast,
  input  logic                m_axi_rvalid,
  output logic                m_axi_rready,
  // AXI4-Lite control slave
  input  logic [31:0]         s_axil_awaddr,
  input  logic [2:0]          s_axil_awprot,
  input  logic                s_axil_awvalid,
  output logic                s_axil_awready,
  input  logic [31:0]         s_axil_wdata,
  input  logic [3:0]          s_axil_wstrb,
  input  logic                s_axil_wvalid,
  output logic                s_axil_wready,
  output logic [1:0]          s_axil_bresp,
  output logic                s_axil_bvalid,
  input  logic                s_axil_bready,
  input  logic [31:0]         s_axil_araddr,
  input  logic [2:0]          s_axil_arprot,
  input  logic                s_axil_arvalid,
  output logic                s_axil_arready,
  output logic [31:0]         s_axil_rdata,
  output logic [1:0]          s_axil_rresp,
  output logic                s_axil_rvalid,
  input  logic                s_axil_rready,
  // AXI4-Stream frame output and consumer handshake
  output logic [DATA_W-1:0]   m_axis_tdata,
  output logic                m_axis_tvalid,
  input  logic                m_axis_tready,
  output logic                m_axis_tlast,
  output logic                m_axis_tuser,
  input  logic                frame_req,
  output logic                pass_done
);
  typedef logic [ADDR_W-1:0]   addr_t;
  typedef logic [ID_W-1:0]     id_t;
  typedef logic [DATA_W-1:0]   data_t;
  typedef logic [DATA_W/8-1:0] strb_t;
  typedef logic [0:0]          user_t;
  typedef logic [31:0]         laddr_t;
  typedef logic [31:0]         ldata_t;
  typedef logic [3:0]          lstrb_t;
  `AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, user_t)
  `AXI_LITE_TYPEDEF_ALL(axil, laddr_t, ldata_t, lstrb_t)

  /* verilator lint_off UNUSEDSIGNAL */
  axi_req_t   req;    // region, atop and user fields have no flat port
  /* verilator lint_on UNUSEDSIGNAL */
  axi_resp_t  resp;
  axil_req_t  lreq;
  axil_resp_t lresp;

  ca_core #(.GRID_X(GRID_X), .GRID_Y(GRID_Y), .CELL_W(CELL_W), .NBH(NBH),
            .BOUNDARY(ca_pkg::boundary_e'(BOUNDARY)), .RULE(ca_pkg::rule_e'(RULE)),
            .MASK(MASK), .DATA_W(DATA_W), .ADDR_W(ADDR_W), .MAX_BURST(MAX_BURST),
            .FIFO_ROWS(FIFO_ROWS), .BUF0_DEFAULT(BUF0_DEFAULT), .BUF1_DEFAULT(BUF1_DEFAULT),
            .FRAME_REPEAT_DEFAULT(FRAME_REPEAT_DEFAULT), .PARAM_DEFAULTS(PARAM_DEFAULTS),
            .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t), .axil_req_t(axil_req_t),
            .axil_resp_t(axil_resp_t)) i_core (
    .aclk_i(aclk), .arst_ni(aresetn), .eclk_i(eclk), .erst_ni(eresetn),
    .s_axil_req_i(lreq), .s_axil_resp_o(lresp), .m_axi_req_o(req), .m_axi_resp_i(resp),
    .m_axis_tdata_o(m_axis_tdata), .m_axis_tvalid_o(m_axis_tvalid), .m_axis_tready_i(m_axis_tready),
    .m_axis_tlast_o(m_axis_tlast), .m_axis_tuser_o(m_axis_tuser), .frame_req_i(frame_req),
    .pass_done_o(pass_done));

  assign m_axi_awid    = req.aw.id;
  assign m_axi_awaddr  = req.aw.addr;
  assign m_axi_awlen   = req.aw.len;
  assign m_axi_awsize  = req.aw.size;
  assign m_axi_awburst = req.aw.burst;
  assign m_axi_awlock  = req.aw.lock;
  assign m_axi_awcache = req.aw.cache;
  assign m_axi_awprot  = req.aw.prot;
  assign m_axi_awqos   = req.aw.qos;
  assign m_axi_awvalid = req.aw_valid;
  assign m_axi_wdata   = req.w.data;
  assign m_axi_wstrb   = req.w.strb;
  assign m_axi_wlast   = req.w.last;
  assign m_axi_wvalid  = req.w_valid;
  assign m_axi_bready  = req.b_ready;
  assign m_axi_arid    = req.ar.id;
  assign m_axi_araddr  = req.ar.addr;
  assign m_axi_arlen   = req.ar.len;
  assign m_axi_arsize  = req.ar.size;
  assign m_axi_arburst = req.ar.burst;
  assign m_axi_arlock  = req.ar.lock;
  assign m_axi_arcache = req.ar.cache;
  assign m_axi_arprot  = req.ar.prot;
  assign m_axi_arqos   = req.ar.qos;
  assign m_axi_arvalid = req.ar_valid;
  assign m_axi_rready  = req.r_ready;

  always_comb begin
    resp          = '0;
    resp.aw_ready = m_axi_awready;
    resp.w_ready  = m_axi_wready;
    resp.b.id     = m_axi_bid;
    resp.b.resp   = m_axi_bresp;
    resp.b_valid  = m_axi_bvalid;
    resp.ar_ready = m_axi_arready;
    resp.r.id     = m_axi_rid;
    resp.r.data   = m_axi_rdata;
    resp.r.resp   = m_axi_rresp;
    resp.r.last   = m_axi_rlast;
    resp.r_valid  = m_axi_rvalid;

    lreq          = '0;
    lreq.aw.addr  = s_axil_awaddr;
    lreq.aw.prot  = s_axil_awprot;
    lreq.aw_valid = s_axil_awvalid;
    lreq.w.data   = s_axil_wdata;
    lreq.w.strb   = s_axil_wstrb;
    lreq.w_valid  = s_axil_wvalid;
    lreq.b_ready  = s_axil_bready;
    lreq.ar.addr  = s_axil_araddr;
    lreq.ar.prot  = s_axil_arprot;
    lreq.ar_valid = s_axil_arvalid;
    lreq.r_ready  = s_axil_rready;
  end

  assign s_axil_awready = lresp.aw_ready;
  assign s_axil_wready  = lresp.w_ready;
  assign s_axil_bresp   = lresp.b.resp;
  assign s_axil_bvalid  = lresp.b_valid;
  assign s_axil_arready = lresp.ar_ready;
  assign s_axil_rdata   = lresp.r.data;
  assign s_axil_rresp   = lresp.r.resp;
  assign s_axil_rvalid  = lresp.r_valid;
endmodule
