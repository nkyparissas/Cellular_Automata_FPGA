// Lint-only top: ca_frame_writer with concrete AXI types (1080p, 8-bit cells, 128-bit bus).
`include "axi/typedef.svh"
module lint_writer (
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          start_i,
  input  logic          commit_i,
  input  logic [31:0]   base_addr_i,
  output logic          done_o,
  input  logic [127:0]  s_tdata_i,
  input  logic          s_tvalid_i,
  output logic          s_tready_o,
  output logic [6:0]    popped_o,
  output logic [31:0]   aw_addr_o,
  output logic [7:0]    aw_len_o,
  output logic          aw_valid_o,
  input  logic          aw_ready_i,
  output logic [127:0]  w_data_o,
  output logic          w_last_o,
  output logic          w_valid_o,
  input  logic          w_ready_i,
  input  logic          b_valid_i,
  output logic          b_ready_o
);
  typedef logic [31:0]  addr_t;
  typedef logic [0:0]   id_t;
  typedef logic [127:0] data_t;
  typedef logic [15:0]  strb_t;
  typedef logic [0:0]   user_t;
  `AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, user_t)
  /* verilator lint_off UNUSEDSIGNAL */
  axi_req_t  req;   // only the write-channel fields are observed
  /* verilator lint_on UNUSEDSIGNAL */
  axi_resp_t resp;
  always_comb begin
    resp          = '0;
    resp.aw_ready = aw_ready_i;
    resp.w_ready  = w_ready_i;
    resp.b_valid  = b_valid_i;
  end
  assign aw_addr_o  = req.aw.addr;
  assign aw_len_o   = req.aw.len;
  assign aw_valid_o = req.aw_valid;
  assign w_data_o   = req.w.data;
  assign w_last_o   = req.w.last;
  assign w_valid_o  = req.w_valid;
  assign b_ready_o  = req.b_ready;

  ca_frame_writer #(.GRID_X(1920), .GRID_Y(1080), .CELL_W(8), .NBH(29), .DATA_W(128), .ADDR_W(32),
                    .BND(ca_pkg::BND_TOROIDAL), .MAX_BURST(64), .PW(7),
                    .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t)) i_dut (
    .clk_i, .rst_ni, .start_i, .commit_i, .base_addr_i, .done_o, .s_tdata_i, .s_tvalid_i, .s_tready_o,
    .popped_o, .axi_req_o(req), .axi_resp_i(resp));
endmodule
