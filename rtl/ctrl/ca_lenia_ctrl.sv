// Lenia configuration path (Lenia design spec, Sections 6.2 and 6.3).
//   Kernel: KERNEL_DATA words are accepted while RUN is clear and no pass is
//   busy, cross to eclk through an async FIFO and shift the weight chain of
//   ca_rule_lenia once per word. KERNEL_PENDING compares the words accepted
//   with a gray-coded count (eclk -> aclk) of the words whose shift has reached
//   class 0 (kern_done_i, C cycles after the word), so it clears only after the
//   last shift; while it is set, hold_o stops pass starts.
//   Growth table: table and shift writes go to the inactive bank and are
//   ignored while a commit is pending; the banks swap in any cycle in which no
//   pass is running, GEN_COUNT is latched into GROWTH_GEN, and the active bank
//   with its SH reaches the engine through ca_params_cdc at the next pass start.
//   A commit never holds a pass. The active bank and the SH values are
//   configuration and survive a reset; the pending flags and GROWTH_GEN do not.
module ca_lenia_ctrl #(
  parameter int unsigned C          = 69,
  parameter int unsigned WEIGHT_W   = 6,
  parameter int unsigned LUT_IDX_W  = 12,
  parameter int unsigned CELL_W     = 16,
  parameter int unsigned SH_DEFAULT = 0
) (
  // Register side (aclk): one-cycle strobes from ca_regs with their data.
  input  logic                aclk_i,
  input  logic                arst_ni,
  input  logic                kern_wr_i,
  input  logic                gt_wr_i,
  input  logic                sh_wr_i,
  input  logic                commit_i,
  input  logic [12:0]         gt_idx_i,
  input  logic [31:0]         wdata_i,
  // Pass controller.
  input  logic                run_i,
  input  logic                busy_i,
  input  logic                active_i,
  input  logic [31:0]         gen_count_i,
  output logic                hold_o,
  // Status and read-back.
  output logic                kern_pending_o,
  output logic                growth_pending_o,
  output logic [5:0]          sh_inactive_o,
  output logic [31:0]         growth_gen_o,
  output ca_pkg::lenia_sel_t  sel_o,
  // Growth-table write port (aclk).
  output logic                gt_we_o,
  output logic [LUT_IDX_W:0]  gt_addr_o,
  output logic [CELL_W:0]     gt_data_o,
  // Weight chain (eclk): one shift per valid cycle.
  input  logic                eclk_i,
  input  logic                erst_ni,
  output logic                kern_valid_o,
  output logic [WEIGHT_W-1:0] kern_data_o,
  input  logic                kern_done_i
);
  // Words accepted but not yet through the chain: at most KD in the FIFO, C in
  // the chain and a few in the count's crossing, below 2^KCW = 4 * KD.
  localparam int unsigned KD  = C <= 4 ? 4 : (1 << $clog2(C));
  localparam int unsigned KCW = $clog2(KD) + 2;

  // ------------------------------------------------------------- kernel
  logic           kf_ready, kern_take;
  logic [KCW-1:0] accepted, shifted_e, shifted_a;

  assign kern_take = kern_wr_i && !run_i && !busy_i && kf_ready;

  ca_async_fifo #(.W(WEIGHT_W), .DEPTH(KD)) i_kfifo (
    .wclk_i(aclk_i), .wrst_ni(arst_ni), .w_valid_i(kern_take), .w_ready_o(kf_ready),
    .w_data_i(wdata_i[WEIGHT_W-1:0]),
    .rclk_i(eclk_i), .rrst_ni(erst_ni), .r_valid_o(kern_valid_o), .r_ready_i(1'b1), .r_data_o(kern_data_o));

  always_ff @(posedge eclk_i) begin
    if (!erst_ni)          shifted_e <= '0;
    else if (kern_done_i)  shifted_e <= shifted_e + 1'b1;
  end

  ca_gray_xfer #(.W(KCW)) i_x_shifted (
    .src_clk_i(eclk_i), .src_rst_ni(erst_ni), .src_bin_i(shifted_e),
    .dst_clk_i(aclk_i), .dst_rst_ni(arst_ni), .dst_bin_o(shifted_a));

  always_ff @(posedge aclk_i) begin
    if (!arst_ni)       accepted <= '0;
    else if (kern_take) accepted <= accepted + 1'b1;
  end

  assign kern_pending_o = accepted != shifted_a;
  assign hold_o         = kern_pending_o;

  // -------------------------------------------------------- growth table
  logic           bank, pending, swap;
  logic [1:0][5:0] sh;

  // Power-up values (FPGA initial values). pending also has one so that no
  // swap can happen before the first reset (simulators start it at random).
  initial begin
    bank    = 1'b0;
    sh      = {2{6'(SH_DEFAULT)}};
    pending = 1'b0;
  end

  // No swap in reset: a reset cancels a pending commit and keeps the bank.
  assign swap = arst_ni && pending && !active_i;

  always_ff @(posedge aclk_i) begin
    if (sh_wr_i && !pending) sh[!bank] <= wdata_i[5:0];
    if (swap)                bank      <= !bank;
  end

  always_ff @(posedge aclk_i) begin
    if (!arst_ni) begin
      pending      <= 1'b0;
      growth_gen_o <= '0;
    end else if (swap) begin
      pending      <= 1'b0;
      growth_gen_o <= gen_count_i;
    end else if (commit_i) begin
      pending      <= 1'b1;
    end
  end

  assign gt_we_o          = gt_wr_i && !pending && (gt_idx_i >> LUT_IDX_W) == '0;
  assign gt_addr_o        = {!bank, gt_idx_i[LUT_IDX_W-1:0]};
  assign gt_data_o        = wdata_i[CELL_W:0];
  assign growth_pending_o = pending;
  assign sh_inactive_o    = sh[!bank];
  assign sel_o            = '{bank: bank, sh: sh[bank]};

  if (CELL_W + 1 < 32) begin : g_unused_wdata
    logic unused_wdata;
    assign unused_wdata = ^wdata_i[31:CELL_W+1];
  end
endmodule
