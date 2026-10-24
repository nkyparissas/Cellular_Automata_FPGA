// Large-neighbourhood CA core (spec Section 3).
//   aclk: AXI4-Lite registers, pass controller, frame reader and writer,
//         consumer stream, line-buffer write side.
//   eclk: line-buffer drain, sliding window, rule, packer.
// The frame reader (AR/R) and writer (AW/W/B) share one AXI4 master port
// through pulp-platform axi_rw_join.
module ca_core #(
  parameter int unsigned          GRID_X               = 64,
  parameter int unsigned          GRID_Y               = 24,
  parameter int unsigned          CELL_W               = 8,
  parameter int unsigned          NBH                  = 5,
  parameter ca_pkg::boundary_e    BOUNDARY             = ca_pkg::BND_TOROIDAL,
  parameter ca_pkg::rule_e        RULE                 = ca_pkg::RULE_HODGEPODGE,
  parameter logic [NBH*NBH-1:0]   MASK                 = '1,
  parameter int unsigned          DATA_W               = 128,
  parameter int unsigned          ADDR_W               = 32,
  parameter int unsigned          MAX_BURST            = 64,
  parameter int unsigned          FIFO_ROWS            = 2,
  parameter logic [63:0]          BUF0_DEFAULT         = 64'h0,
  parameter logic [63:0]          BUF1_DEFAULT         = 64'h0100_0000,
  parameter int unsigned          FRAME_REPEAT_DEFAULT = 0,
  parameter ca_pkg::rule_params_t PARAM_DEFAULTS       = '0,
  parameter type                  axi_req_t            = logic,
  parameter type                  axi_resp_t           = logic,
  parameter type                  axil_req_t           = logic,
  parameter type                  axil_resp_t          = logic
) (
  input  logic              aclk_i,
  input  logic              arst_ni,
  input  logic              eclk_i,
  input  logic              erst_ni,
  input  axil_req_t         s_axil_req_i,
  output axil_resp_t        s_axil_resp_o,
  output axi_req_t          m_axi_req_o,
  input  axi_resp_t         m_axi_resp_i,
  output logic [DATA_W-1:0] m_axis_tdata_o,
  output logic              m_axis_tvalid_o,
  input  logic              m_axis_tready_i,
  output logic              m_axis_tlast_o,
  output logic              m_axis_tuser_o,
  input  logic              frame_req_i,
  output logic              pass_done_o
);
  localparam int unsigned SLW   = $clog2(NBH + 1);
  localparam int unsigned WPR   = GRID_X * CELL_W / DATA_W;
  localparam int unsigned BW    = WPR > 1 ? $clog2(WPR) : 1;
  localparam int unsigned PW    = $clog2(NBH + 1) + 2;
  localparam int unsigned FDEP  = (FIFO_ROWS * WPR) < 4 ? 4 : (1 << $clog2(FIFO_ROWS * WPR));

  // ------------------------------------------------------- parameter checks
  if (GRID_X * CELL_W % DATA_W != 0) begin : g_bad_x
    $error("ca_core: GRID_X*CELL_W must be a multiple of DATA_W");
  end
  if ((1 << $clog2(DATA_W / CELL_W)) != DATA_W / CELL_W) begin : g_bad_ratio
    $error("ca_core: DATA_W/CELL_W must be a power of two");
  end
  if (NBH < 3 || NBH % 2 == 0) begin : g_bad_nbh
    $error("ca_core: NBH must be odd and >= 3");
  end
  if (GRID_X < NBH || GRID_Y < NBH) begin : g_bad_grid
    $error("ca_core: the grid must be at least NBH x NBH");
  end

  // ------------------------------------------------------------- resets
  logic a_rst_n, e_rst_n;
  ca_reset_sync i_arst (.clk_i(aclk_i), .arst_ni, .rst_no(a_rst_n));
  ca_reset_sync i_erst (.clk_i(eclk_i), .arst_ni(erst_ni), .rst_no(e_rst_n));

  // ---------------------------------------------------- registers, control
  logic                 run, pause, auto_, reset_state, reg_req;
  logic [15:0]          frame_repeat, gens_per_frame;
  logic [ADDR_W-1:0]    buf0, buf1;
  ca_pkg::rule_params_t rule_params, e_params;
  logic                 busy, front, pending, pass_start, fwd_en, commit, rd_done, wr_done;
  logic [31:0]          gen_count, pass_count;

  ca_regs #(.GRID_X(GRID_X), .GRID_Y(GRID_Y), .CELL_W(CELL_W), .NBH(NBH), .BND(BOUNDARY), .RULE(RULE),
            .DATA_W(DATA_W), .ADDR_W(ADDR_W), .BUF0_DEFAULT(BUF0_DEFAULT), .BUF1_DEFAULT(BUF1_DEFAULT),
            .FRAME_REPEAT_DEFAULT(FRAME_REPEAT_DEFAULT), .PARAM_DEFAULTS(PARAM_DEFAULTS),
            .axil_req_t(axil_req_t), .axil_resp_t(axil_resp_t)) i_regs (
    .clk_i(aclk_i), .rst_ni(a_rst_n), .axil_req_i(s_axil_req_i), .axil_resp_o(s_axil_resp_o),
    .run_o(run), .pause_o(pause), .auto_o(auto_), .reset_state_o(reset_state), .frame_req_o(reg_req),
    .frame_repeat_o(frame_repeat), .gens_per_frame_o(gens_per_frame), .buf0_addr_o(buf0),
    .buf1_addr_o(buf1), .rule_params_o(rule_params), .busy_i(busy), .front_i(front),
    .pending_i(pending), .gen_count_i(gen_count), .pass_count_i(pass_count));

  ca_controller i_ctrl (
    .clk_i(aclk_i), .rst_ni(a_rst_n), .run_i(run), .pause_i(pause), .auto_i(auto_),
    .reset_state_i(reset_state), .req_i(reg_req || frame_req_i), .frame_repeat_i(frame_repeat),
    .gens_per_frame_i(gens_per_frame), .pass_start_o(pass_start), .rd_fwd_en_o(fwd_en),
    .wr_commit_o(commit), .rd_done_i(rd_done), .wr_done_i(wr_done), .front_o(front), .busy_o(busy),
    .pending_o(pending), .gen_count_o(gen_count), .pass_count_o(pass_count), .pass_done_o(pass_done_o));

  // The front buffer holds the current generation: read it, write the other.
  logic [ADDR_W-1:0] rd_base, wr_base;
  assign rd_base = front ? buf1 : buf0;
  assign wr_base = front ? buf0 : buf1;

  // ------------------------------------------------------------ data path
  axi_req_t  rd_req, wr_req;
  axi_resp_t rd_resp, wr_resp;

  logic              lb_alloc_valid, lb_alloc_ready, lb_wr_en, lb_row_done;
  logic [SLW-1:0]    lb_alloc_slot, lb_wr_slot;
  logic [BW-1:0]     lb_wr_addr;
  logic [DATA_W-1:0] lb_wr_data;
  logic [PW-1:0]     popped;

  ca_frame_reader #(.GRID_X(GRID_X), .GRID_Y(GRID_Y), .CELL_W(CELL_W), .NBH(NBH), .DATA_W(DATA_W),
                    .ADDR_W(ADDR_W), .BND(BOUNDARY), .MAX_BURST(MAX_BURST),
                    .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t)) i_reader (
    .clk_i(aclk_i), .rst_ni(a_rst_n), .start_i(pass_start), .base_addr_i(rd_base), .fwd_en_i(fwd_en),
    .done_o(rd_done), .axi_req_o(rd_req), .axi_resp_i(rd_resp),
    .m_axis_tdata_o, .m_axis_tvalid_o, .m_axis_tready_i, .m_axis_tlast_o, .m_axis_tuser_o,
    .lb_alloc_valid_o(lb_alloc_valid), .lb_alloc_ready_i(lb_alloc_ready), .lb_alloc_slot_i(lb_alloc_slot),
    .lb_wr_en_o(lb_wr_en), .lb_wr_slot_o(lb_wr_slot), .lb_wr_addr_o(lb_wr_addr),
    .lb_wr_data_o(lb_wr_data), .lb_row_done_o(lb_row_done));

  logic [NBH-1:0][CELL_W-1:0] col;
  logic                       col_vld, cell_vld, word_vld, fifo_wready;
  logic [CELL_W-1:0]          new_cell;
  logic [DATA_W-1:0]          word;

  ca_line_buffer #(.GRID_X(GRID_X), .GRID_Y(GRID_Y), .CELL_W(CELL_W), .NBH(NBH), .DATA_W(DATA_W),
                   .BND(BOUNDARY), .FIFO_ROWS(FIFO_ROWS), .PW(PW)) i_lines (
    .aclk_i, .arst_ni(a_rst_n), .alloc_valid_i(lb_alloc_valid), .alloc_ready_o(lb_alloc_ready),
    .alloc_slot_o(lb_alloc_slot), .wr_en_i(lb_wr_en), .wr_slot_i(lb_wr_slot), .wr_addr_i(lb_wr_addr),
    .wr_data_i(lb_wr_data), .row_done_i(lb_row_done), .popped_i(popped),
    .eclk_i, .erst_ni(e_rst_n), .col_o(col), .vld_o(col_vld));

  ca_params_cdc i_params_cdc (
    .aclk_i, .arst_ni(a_rst_n), .capture_i(pass_start), .params_i(rule_params),
    .eclk_i, .erst_ni(e_rst_n), .params_o(e_params));

  ca_engine #(.N(NBH), .CELL_W(CELL_W), .RULE(RULE), .MASK(MASK)) i_engine (
    .clk_i(eclk_i), .rst_ni(e_rst_n), .col_i(col), .vld_i(col_vld), .params_i(e_params),
    .cell_o(new_cell), .vld_o(cell_vld));

  ca_cell_packer #(.CELL_W(CELL_W), .DATA_W(DATA_W)) i_packer (
    .clk_i(eclk_i), .rst_ni(e_rst_n), .cell_i(new_cell), .vld_i(cell_vld), .word_o(word), .word_vld_o(word_vld));

  logic              ofifo_valid, ofifo_ready;
  logic [DATA_W-1:0] ofifo_data;
  ca_async_fifo #(.W(DATA_W), .DEPTH(FDEP)) i_out_fifo (
    .wclk_i(eclk_i), .wrst_ni(e_rst_n), .w_valid_i(word_vld), .w_ready_o(fifo_wready), .w_data_i(word),
    .rclk_i(aclk_i), .rrst_ni(a_rst_n), .r_valid_o(ofifo_valid), .r_ready_i(ofifo_ready), .r_data_o(ofifo_data));

  ca_frame_writer #(.GRID_X(GRID_X), .GRID_Y(GRID_Y), .CELL_W(CELL_W), .NBH(NBH), .DATA_W(DATA_W),
                    .ADDR_W(ADDR_W), .BND(BOUNDARY), .MAX_BURST(MAX_BURST), .PW(PW),
                    .axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t)) i_writer (
    .clk_i(aclk_i), .rst_ni(a_rst_n), .start_i(pass_start), .commit_i(commit), .base_addr_i(wr_base),
    .done_o(wr_done), .s_tdata_i(ofifo_data), .s_tvalid_i(ofifo_valid), .s_tready_o(ofifo_ready),
    .popped_o(popped), .axi_req_o(wr_req), .axi_resp_i(wr_resp));

  axi_rw_join #(.axi_req_t(axi_req_t), .axi_resp_t(axi_resp_t)) i_join (
    .clk_i(aclk_i), .rst_ni(a_rst_n),
    .slv_read_req_i(rd_req), .slv_read_resp_o(rd_resp),
    .slv_write_req_i(wr_req), .slv_write_resp_o(wr_resp),
    .mst_req_o(m_axi_req_o), .mst_resp_i(m_axi_resp_i));

`ifndef SYNTHESIS
  // The drain only starts a row when the FIFO can hold it (spec Section 8).
  /* verilator lint_off SYNCASYNCNET */
  always_ff @(posedge eclk_i) begin
    if (e_rst_n && word_vld && !fifo_wready) $error("ca_core: output FIFO overflow");
  end
  /* verilator lint_on SYNCASYNCNET */
`else
  logic unused_fifo_wready;
  assign unused_fifo_wready = fifo_wready;
`endif
endmodule
