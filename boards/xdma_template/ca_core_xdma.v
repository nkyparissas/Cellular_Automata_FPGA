// Block-design module reference for the XDMA template: ca_core_flat with the
// configuration from ca_cfg.vh (tools/gen_cfg.py) and plain ports.
// Vivado module references must be Verilog or VHDL at the top (UG994), so
// this wrapper is Verilog-2001; the core underneath is SystemVerilog.
// The host reads frames from DDR through XDMA (memory-mapped), so the frame
// stream is not used: it is always accepted and the consumer handshake is
// the FRAME_REQ register. pass_done can drive an XDMA user interrupt.
`include "ca_cfg.vh"
module ca_core_xdma #(
  parameter        ADDR_W = 64,
  parameter [63:0] BUF0   = 64'h0000_0000,
  parameter [63:0] BUF1   = 64'h1000_0000
) (
  input  wire                    aclk,
  input  wire                    aresetn,
  input  wire                    eclk,
  input  wire                    eresetn,
  output wire [0:0]              m_axi_awid,
  output wire [ADDR_W-1:0]       m_axi_awaddr,
  output wire [7:0]              m_axi_awlen,
  output wire [2:0]              m_axi_awsize,
  output wire [1:0]              m_axi_awburst,
  output wire                    m_axi_awlock,
  output wire [3:0]              m_axi_awcache,
  output wire [2:0]              m_axi_awprot,
  output wire [3:0]              m_axi_awqos,
  output wire                    m_axi_awvalid,
  input  wire                    m_axi_awready,
  output wire [`CA_DATA_W-1:0]   m_axi_wdata,
  output wire [`CA_DATA_W/8-1:0] m_axi_wstrb,
  output wire                    m_axi_wlast,
  output wire                    m_axi_wvalid,
  input  wire                    m_axi_wready,
  input  wire [0:0]              m_axi_bid,
  input  wire [1:0]              m_axi_bresp,
  input  wire                    m_axi_bvalid,
  output wire                    m_axi_bready,
  output wire [0:0]              m_axi_arid,
  output wire [ADDR_W-1:0]       m_axi_araddr,
  output wire [7:0]              m_axi_arlen,
  output wire [2:0]              m_axi_arsize,
  output wire [1:0]              m_axi_arburst,
  output wire                    m_axi_arlock,
  output wire [3:0]              m_axi_arcache,
  output wire [2:0]              m_axi_arprot,
  output wire [3:0]              m_axi_arqos,
  output wire                    m_axi_arvalid,
  input  wire                    m_axi_arready,
  input  wire [0:0]              m_axi_rid,
  input  wire [`CA_DATA_W-1:0]   m_axi_rdata,
  input  wire [1:0]              m_axi_rresp,
  input  wire                    m_axi_rlast,
  input  wire                    m_axi_rvalid,
  output wire                    m_axi_rready,
  input  wire [31:0]             s_axil_awaddr,
  input  wire [2:0]              s_axil_awprot,
  input  wire                    s_axil_awvalid,
  output wire                    s_axil_awready,
  input  wire [31:0]             s_axil_wdata,
  input  wire [3:0]              s_axil_wstrb,
  input  wire                    s_axil_wvalid,
  output wire                    s_axil_wready,
  output wire [1:0]              s_axil_bresp,
  output wire                    s_axil_bvalid,
  input  wire                    s_axil_bready,
  input  wire [31:0]             s_axil_araddr,
  input  wire [2:0]              s_axil_arprot,
  input  wire                    s_axil_arvalid,
  output wire                    s_axil_arready,
  output wire [31:0]             s_axil_rdata,
  output wire [1:0]              s_axil_rresp,
  output wire                    s_axil_rvalid,
  input  wire                    s_axil_rready,
  output wire                    pass_done
);
  // The frame stream is unused in memory-mapped XDMA operation.
  /* verilator lint_off UNUSEDSIGNAL */
  wire [`CA_DATA_W-1:0] tdata;
  wire                  tvalid, tlast, tuser;
  /* verilator lint_on UNUSEDSIGNAL */

  ca_core_flat #(.GRID_X(`CA_GRID_X), .GRID_Y(`CA_GRID_Y), .CELL_W(`CA_CELL_W), .NBH(`CA_NBH),
                 .BOUNDARY(`CA_BND_ID), .RULE(`CA_RULE_ID), .MASK(`CA_MASK), .DATA_W(`CA_DATA_W),
                 .ADDR_W(ADDR_W), .ID_W(1), .BUF0_DEFAULT(BUF0), .BUF1_DEFAULT(BUF1),
                 .PARAM_DEFAULTS(`CA_PARAMS)) i_core (
    .aclk(aclk), .aresetn(aresetn), .eclk(eclk), .eresetn(eresetn),
    .m_axi_awid(m_axi_awid), .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst), .m_axi_awlock(m_axi_awlock),
    .m_axi_awcache(m_axi_awcache), .m_axi_awprot(m_axi_awprot), .m_axi_awqos(m_axi_awqos),
    .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready), .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready), .m_axi_bid(m_axi_bid), .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready), .m_axi_arid(m_axi_arid),
    .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst), .m_axi_arlock(m_axi_arlock), .m_axi_arcache(m_axi_arcache),
    .m_axi_arprot(m_axi_arprot), .m_axi_arqos(m_axi_arqos), .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready), .m_axi_rid(m_axi_rid), .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready),
    .s_axil_awaddr(s_axil_awaddr), .s_axil_awprot(s_axil_awprot), .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready), .s_axil_wdata(s_axil_wdata), .s_axil_wstrb(s_axil_wstrb),
    .s_axil_wvalid(s_axil_wvalid), .s_axil_wready(s_axil_wready), .s_axil_bresp(s_axil_bresp),
    .s_axil_bvalid(s_axil_bvalid), .s_axil_bready(s_axil_bready), .s_axil_araddr(s_axil_araddr),
    .s_axil_arprot(s_axil_arprot), .s_axil_arvalid(s_axil_arvalid), .s_axil_arready(s_axil_arready),
    .s_axil_rdata(s_axil_rdata), .s_axil_rresp(s_axil_rresp), .s_axil_rvalid(s_axil_rvalid),
    .s_axil_rready(s_axil_rready),
    .m_axis_tdata(tdata), .m_axis_tvalid(tvalid), .m_axis_tready(1'b1), .m_axis_tlast(tlast),
    .m_axis_tuser(tuser), .frame_req(1'b0), .pass_done(pass_done));
endmodule
