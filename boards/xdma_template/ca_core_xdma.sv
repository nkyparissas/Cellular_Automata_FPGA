// Block-design module reference for the XDMA template: ca_core_flat with the
// configuration from ca_cfg.svh (tools/gen_cfg.py) and plain ports.
// The host reads frames from DDR through XDMA (memory-mapped), so the frame
// stream is not used: it is always accepted and the consumer handshake is
// the FRAME_REQ register. pass_done can drive an XDMA user interrupt.
module ca_core_xdma #(
  parameter int unsigned ADDR_W = 64,
  parameter logic [63:0] BUF0   = 64'h0000_0000,
  parameter logic [63:0] BUF1   = 64'h1000_0000
) (
  input  logic                aclk,
  input  logic                aresetn,
  input  logic                eclk,
  input  logic                eresetn,
  output logic [0:0]          m_axi_awid,
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
  input  logic [0:0]          m_axi_bid,
  input  logic [1:0]          m_axi_bresp,
  input  logic                m_axi_bvalid,
  output logic                m_axi_bready,
  output logic [0:0]          m_axi_arid,
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
  input  logic [0:0]          m_axi_rid,
  input  logic [DATA_W-1:0]   m_axi_rdata,
  input  logic [1:0]          m_axi_rresp,
  input  logic                m_axi_rlast,
  input  logic                m_axi_rvalid,
  output logic                m_axi_rready,
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
  output logic                pass_done
);
  `include "ca_cfg.svh"

  // The frame stream is unused in memory-mapped XDMA operation.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [DATA_W-1:0] tdata;
  logic              tvalid, tlast, tuser;
  /* verilator lint_on UNUSEDSIGNAL */

  ca_core_flat #(.GRID_X(GRID_X), .GRID_Y(GRID_Y), .CELL_W(CELL_W), .NBH(NBH),
                 .BOUNDARY(ca_pkg::boundary_e'(BND_ID)), .RULE(ca_pkg::rule_e'(RULE_ID)), .MASK(MASK),
                 .DATA_W(DATA_W), .ADDR_W(ADDR_W), .ID_W(1), .BUF0_DEFAULT(BUF0), .BUF1_DEFAULT(BUF1),
                 .PARAM_DEFAULTS(PARAMS)) i_core (
    .aclk, .aresetn, .eclk, .eresetn,
    .m_axi_awid, .m_axi_awaddr, .m_axi_awlen, .m_axi_awsize, .m_axi_awburst, .m_axi_awlock,
    .m_axi_awcache, .m_axi_awprot, .m_axi_awqos, .m_axi_awvalid, .m_axi_awready, .m_axi_wdata,
    .m_axi_wstrb, .m_axi_wlast, .m_axi_wvalid, .m_axi_wready, .m_axi_bid, .m_axi_bresp, .m_axi_bvalid,
    .m_axi_bready, .m_axi_arid, .m_axi_araddr, .m_axi_arlen, .m_axi_arsize, .m_axi_arburst,
    .m_axi_arlock, .m_axi_arcache, .m_axi_arprot, .m_axi_arqos, .m_axi_arvalid, .m_axi_arready,
    .m_axi_rid, .m_axi_rdata, .m_axi_rresp, .m_axi_rlast, .m_axi_rvalid, .m_axi_rready,
    .s_axil_awaddr, .s_axil_awprot, .s_axil_awvalid, .s_axil_awready, .s_axil_wdata, .s_axil_wstrb,
    .s_axil_wvalid, .s_axil_wready, .s_axil_bresp, .s_axil_bvalid, .s_axil_bready, .s_axil_araddr,
    .s_axil_arprot, .s_axil_arvalid, .s_axil_arready, .s_axil_rdata, .s_axil_rresp, .s_axil_rvalid,
    .s_axil_rready,
    .m_axis_tdata(tdata), .m_axis_tvalid(tvalid), .m_axis_tready(1'b1), .m_axis_tlast(tlast),
    .m_axis_tuser(tuser), .frame_req(1'b0), .pass_done);
endmodule
