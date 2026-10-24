// Smoke top: proves the vendored pulp-platform/axi modules used by this
// project elaborate and lint under Verilator.
`include "axi/typedef.svh"

module tb_axi_smoke
  import axi_pkg::*;
#(
  localparam int unsigned AW = 32,
  localparam int unsigned DW = 128
) (
  input  logic clk_i,
  input  logic rst_ni,
  // axi_rw_join
  input  logic [3:0]  rw_dummy_i,
  output logic [3:0]  rw_dummy_o
);
  typedef logic [AW-1:0]   addr_t;
  typedef logic [0:0]      slv_id_t;
  typedef logic [1:0]      mst_id_t;
  typedef logic [DW-1:0]   data_t;
  typedef logic [DW/8-1:0] strb_t;
  typedef logic [0:0]      user_t;
  typedef logic [31:0]     ldata_t;
  typedef logic [3:0]      lstrb_t;

  `AXI_TYPEDEF_ALL(slv, addr_t, slv_id_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_ALL(mst, addr_t, mst_id_t, data_t, strb_t, user_t)
  `AXI_LITE_TYPEDEF_ALL(axil, addr_t, ldata_t, lstrb_t)

  // Inputs are driven from a tiny register so every port is used.
  logic [3:0] q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) q <= '0;
    else         q <= rw_dummy_i;
  end

  slv_req_t  rd_req, wr_req, join_req;
  slv_resp_t rd_resp, wr_resp, join_resp;
  assign rd_req    = '{ar_valid: q[0], r_ready: 1'b1, default: '0};
  assign wr_req    = '{aw_valid: q[1], w_valid: q[1], b_ready: 1'b1, default: '0};
  assign join_resp = '{ar_ready: 1'b1, aw_ready: 1'b1, w_ready: 1'b1, default: '0};

  axi_rw_join #(
    .axi_req_t  (slv_req_t),
    .axi_resp_t (slv_resp_t)
  ) i_rw_join (
    .clk_i, .rst_ni,
    .slv_read_req_i   (rd_req),
    .slv_read_resp_o  (rd_resp),
    .slv_write_req_i  (wr_req),
    .slv_write_resp_o (wr_resp),
    .mst_req_o        (join_req),
    .mst_resp_i       (join_resp)
  );

  slv_req_t  [1:0] mux_reqs;
  slv_resp_t [1:0] mux_resps;
  mst_req_t        mux_req;
  mst_resp_t       mux_resp;
  assign mux_reqs[1] = join_req;
  assign mux_reqs[0] = '{ar_valid: q[2], r_ready: 1'b1, default: '0};
  assign mux_resp = '{ar_ready: 1'b1, aw_ready: 1'b1, w_ready: 1'b1, default: '0};

  axi_mux #(
    .SlvAxiIDWidth (1),
    .slv_aw_chan_t (slv_aw_chan_t), .mst_aw_chan_t (mst_aw_chan_t),
    .w_chan_t      (slv_w_chan_t),
    .slv_b_chan_t  (slv_b_chan_t),  .mst_b_chan_t  (mst_b_chan_t),
    .slv_ar_chan_t (slv_ar_chan_t), .mst_ar_chan_t (mst_ar_chan_t),
    .slv_r_chan_t  (slv_r_chan_t),  .mst_r_chan_t  (mst_r_chan_t),
    .slv_req_t     (slv_req_t),     .slv_resp_t    (slv_resp_t),
    .mst_req_t     (mst_req_t),     .mst_resp_t    (mst_resp_t),
    .NoSlvPorts    (2),
    .MaxWTrans     (4)
  ) i_mux (
    .clk_i, .rst_ni,
    .test_i      (1'b0),
    .slv_reqs_i  (mux_reqs),
    .slv_resps_o (mux_resps),
    .mst_req_o   (mux_req),
    .mst_resp_i  (mux_resp)
  );

  axil_req_t  [1:0] lreqs;
  axil_resp_t [1:0] lresps;
  axil_req_t        lreq;
  axil_resp_t       lresp;
  assign lreqs[1] = '{ar_valid: q[3], r_ready: 1'b1, default: '0};
  assign lreqs[0] = '{default: '0};
  assign lresp = '{ar_ready: 1'b1, aw_ready: 1'b1, w_ready: 1'b1, default: '0};

  axi_lite_mux #(
    .aw_chan_t  (axil_aw_chan_t), .w_chan_t (axil_w_chan_t), .b_chan_t (axil_b_chan_t),
    .ar_chan_t  (axil_ar_chan_t), .r_chan_t (axil_r_chan_t),
    .axi_req_t  (axil_req_t),     .axi_resp_t (axil_resp_t),
    .NoSlvPorts (2),
    .MaxTrans   (2)
  ) i_lite_mux (
    .clk_i, .rst_ni,
    .test_i      (1'b0),
    .slv_reqs_i  (lreqs),
    .slv_resps_o (lresps),
    .mst_req_o   (lreq),
    .mst_resp_i  (lresp)
  );

  assign rw_dummy_o = {lresps[1].r_valid ^ lreq.ar_valid,
                       mux_resps[0].r_valid ^ mux_req.ar_valid,
                       rd_resp.r_valid ^ wr_resp.b_valid,
                       ^{rd_resp, wr_resp, mux_resps, lresps, lreq, mux_req}};
endmodule
