// Lint-only top: ca_frame_reader with concrete AXI types (1080p, 8-bit cells, 128-bit bus).
`include "axi/typedef.svh"
module lint_reader (
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          start_i,
  input  logic [31:0]   base_addr_i,
  input  logic          fwd_en_i,
  output logic          done_o,
  output logic [127:0]  m_axis_tdata_o,
  output logic          m_axis_tvalid_o,
  input  logic          m_axis_tready_i,
  output logic          m_axis_tlast_o,
  output logic          m_axis_tuser_o,
  output logic          lb_alloc_valid_o,
  input  logic          lb_alloc_ready_i,
  input  logic [4:0]    lb_alloc_slot_i,
  output logic          lb_wr_en_o,
  output logic [4:0]    lb_wr_slot_o,
  output logic [6:0]    lb_wr_addr_o,
  output logic [127:0]  lb_wr_data_o,
  output logic          lb_row_done_o,
  output logic [31:0]   ar_addr_o,
  output logic          ar_valid_o,
  input  logic          ar_ready_i,
  input  logic [127:0]  r_data_i,
  input  logic          r_valid_i,
  input  logic          r_last_i,
  output logic          r_ready_o
);
  typedef logic [31:0]  addr_t;
  typedef logic [0:0]   id_t;
  typedef logic [127:0] data_t;
  typedef logic [15:0]  strb_t;
  typedef logic [0:0]   user_t;
  `AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, user_t)
  /* verilator lint_off UNUSEDSIGNAL */
  axi_req_t  req;   // only the read-channel fields are observed
  /* verilator lint_on UNUSEDSIGNAL */
  axi_resp_t resp;
  always_comb begin
    resp          = '0;
    resp.ar_ready = ar_ready_i;
    resp.r_valid  = r_valid_i;
    resp.r.data   = r_data_i;
    resp.r.last   = r_last_i;
  end
  assign ar_addr_o  = req.ar.addr;
  assign ar_valid_o = req.ar_valid;
  assign r_ready_o  = req.r_ready;

  ca_frame_reader #(.GRID_X(1920), .GRID_Y(1080), .CELL_W(8), .NBH(29), .DATA_W(128), .ADDR_W(32),
                    .BND(ca_pkg::BND_TOROIDAL), .MAX_BURST(64),
                    .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t)) i_dut (
    .clk_i, .rst_ni, .start_i, .base_addr_i, .fwd_en_i, .done_o, .axi_req_o(req), .axi_resp_i(resp),
    .m_axis_tdata_o, .m_axis_tvalid_o, .m_axis_tready_i, .m_axis_tlast_o, .m_axis_tuser_o,
    .lb_alloc_valid_o, .lb_alloc_ready_i, .lb_alloc_slot_i, .lb_wr_en_o, .lb_wr_slot_o,
    .lb_wr_addr_o, .lb_wr_data_o, .lb_row_done_o);
endmodule
