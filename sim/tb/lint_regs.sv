// Lint-only top: ca_regs (Lenia variant) with concrete AXI4-Lite types.
`include "axi/typedef.svh"
module lint_regs (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [31:0] aw_addr_i,
  input  logic        aw_valid_i,
  input  logic [31:0] w_data_i,
  input  logic [3:0]  w_strb_i,
  input  logic        w_valid_i,
  input  logic        b_ready_i,
  input  logic [31:0] ar_addr_i,
  input  logic        ar_valid_i,
  input  logic        r_ready_i,
  output logic [31:0] r_data_o,
  output logic        r_valid_o,
  output logic        b_valid_o,
  output logic        aw_ready_o,
  output logic        ar_ready_o,
  output logic [31:0] status_o,
  input  logic        busy_i,
  input  logic        front_i,
  input  logic        pending_i,
  input  logic [31:0] gen_count_i,
  input  logic [31:0] pass_count_i,
  input  logic        kern_pending_i,
  input  logic        growth_pending_i,
  input  logic        growth_bank_i,
  input  logic [5:0]  growth_shift_i,
  input  logic [31:0] growth_gen_i,
  input  logic [31:0] lenia_cfg_i
);
  typedef logic [31:0] addr_t;
  typedef logic [31:0] data_t;
  typedef logic [3:0]  strb_t;
  `AXI_LITE_TYPEDEF_ALL(axil, addr_t, data_t, strb_t)
  axil_req_t req;
  /* verilator lint_off UNUSEDSIGNAL */
  axil_resp_t resp;   // resp fields not exported by this wrapper
  /* verilator lint_on UNUSEDSIGNAL */
  always_comb begin
    req          = '0;
    req.aw.addr  = aw_addr_i;
    req.aw_valid = aw_valid_i;
    req.w.data   = w_data_i;
    req.w.strb   = w_strb_i;
    req.w_valid  = w_valid_i;
    req.b_ready  = b_ready_i;
    req.ar.addr  = ar_addr_i;
    req.ar_valid = ar_valid_i;
    req.r_ready  = r_ready_i;
  end
  assign r_data_o   = resp.r.data;
  assign r_valid_o  = resp.r_valid;
  assign b_valid_o  = resp.b_valid;
  assign aw_ready_o = resp.aw_ready;
  assign ar_ready_o = resp.ar_ready;

  logic run, pause, auto_, reset_state, frame_req;
  logic [15:0] frame_repeat, gpf;
  logic [31:0] buf0, buf1;
  ca_pkg::rule_params_t params;
  logic        kern_wr, gt_wr, sh_wr, commit;
  logic [12:0] gt_idx;
  logic [31:0] lenia_wdata;
  ca_regs #(.RULE(ca_pkg::RULE_LENIA), .axil_req_t(axil_req_t), .axil_resp_t(axil_resp_t)) i_dut (
    .clk_i, .rst_ni, .axil_req_i(req), .axil_resp_o(resp), .run_o(run), .pause_o(pause), .auto_o(auto_),
    .reset_state_o(reset_state), .frame_req_o(frame_req), .frame_repeat_o(frame_repeat),
    .gens_per_frame_o(gpf), .buf0_addr_o(buf0), .buf1_addr_o(buf1), .rule_params_o(params),
    .busy_i, .front_i, .pending_i, .gen_count_i, .pass_count_i, .kern_wr_o(kern_wr), .gt_wr_o(gt_wr),
    .sh_wr_o(sh_wr), .commit_o(commit), .gt_idx_o(gt_idx), .lenia_wdata_o(lenia_wdata), .kern_pending_i,
    .growth_pending_i, .growth_bank_i, .growth_shift_i, .growth_gen_i, .lenia_cfg_i);
  assign status_o = {run, pause, auto_, reset_state, frame_req, ^frame_repeat, ^gpf, ^buf0, ^buf1, ^params,
                     kern_wr, gt_wr, sh_wr, commit, ^gt_idx, ^lenia_wdata, 16'b0};
endmodule
