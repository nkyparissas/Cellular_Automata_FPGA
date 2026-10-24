// Dual-clock grid-lines buffer (spec Sections 5, 6 and 8).
//
// The reader (aclk) allocates one of NBH+1 row slots per virtual row and
// writes the row in DATA_W-bit beats. The drain (eclk) streams one
// neighbourhood column per cycle: for output row o it reads the NBH slots
// holding virtual rows o .. o+NBH-1 at column addresses (k-R) mod GRID_X,
// k = 0 .. GRID_X+2R-1, and tags column k valid for k >= 2R. Columns outside
// the grid read as zero in the zero-edge modes. Gray-coded counters carry
// rows written (aclk -> eclk), rows released (eclk -> aclk) and rows popped
// by the frame writer (aclk -> eclk); the drain starts a row only when the
// output FIFO can take it (FIFO_ROWS rows in flight).
module ca_line_buffer #(
  parameter int unsigned       GRID_X    = 64,
  parameter int unsigned       GRID_Y    = 24,
  parameter int unsigned       CELL_W    = 8,
  parameter int unsigned       NBH       = 5,
  parameter int unsigned       DATA_W    = 128,
  parameter ca_pkg::boundary_e BND       = ca_pkg::BND_TOROIDAL,
  parameter int unsigned       FIFO_ROWS = 2,
  parameter int unsigned       PW        = $clog2(NBH + 1) + 2,
  localparam int unsigned      SLOTS     = NBH + 1,
  localparam int unsigned      SLW       = $clog2(SLOTS),
  localparam int unsigned      BPR       = GRID_X * CELL_W / DATA_W,
  localparam int unsigned      BW        = BPR > 1 ? $clog2(BPR) : 1
) (
  // Reader side (aclk).
  input  logic                       aclk_i,
  input  logic                       arst_ni,
  input  logic                       alloc_valid_i,
  output logic                       alloc_ready_o,
  output logic [SLW-1:0]             alloc_slot_o,
  input  logic                       wr_en_i,
  input  logic [SLW-1:0]             wr_slot_i,
  input  logic [BW-1:0]              wr_addr_i,
  input  logic [DATA_W-1:0]          wr_data_i,
  input  logic                       row_done_i,
  input  logic [PW-1:0]              popped_i,
  // Engine side (eclk).
  input  logic                       eclk_i,
  input  logic                       erst_ni,
  output logic [NBH-1:0][CELL_W-1:0] col_o,
  output logic                       vld_o
);
  localparam int unsigned R    = (NBH - 1) / 2;
  localparam int unsigned XW   = $clog2(GRID_X);
  localparam int unsigned KMAX = GRID_X + 2 * R;
  localparam int unsigned KW   = $clog2(KMAX + 1);
  localparam int unsigned O    = ca_pkg::out_rows(GRID_Y, NBH, BND);
  localparam int unsigned OW   = $clog2(O + 1);
  localparam bit          HZ   = ca_pkg::hzero(BND);

  // ------------------------------------------------------------ aclk side
  logic [PW-1:0]  alloc_ptr, written_ptr, rel_a;
  logic [SLW-1:0] wslot;

  assign alloc_ready_o = PW'(alloc_ptr - rel_a) < PW'(SLOTS);
  assign alloc_slot_o  = wslot;

  always_ff @(posedge aclk_i) begin
    if (!arst_ni) begin
      alloc_ptr   <= '0;
      written_ptr <= '0;
      wslot       <= '0;
    end else begin
      if (alloc_valid_i && alloc_ready_o) begin
        alloc_ptr <= alloc_ptr + 1'b1;
        wslot     <= (wslot == SLW'(SLOTS - 1)) ? '0 : wslot + 1'b1;
      end
      if (row_done_i) written_ptr <= written_ptr + 1'b1;
    end
  end

  // ------------------------------------------------------------- crossings
  logic [PW-1:0] rel_ptr, wr_e, pop_e;
  ca_gray_xfer #(.W(PW)) i_x_written (.src_clk_i(aclk_i), .src_rst_ni(arst_ni), .src_bin_i(written_ptr),
                                      .dst_clk_i(eclk_i), .dst_rst_ni(erst_ni), .dst_bin_o(wr_e));
  ca_gray_xfer #(.W(PW)) i_x_popped  (.src_clk_i(aclk_i), .src_rst_ni(arst_ni), .src_bin_i(popped_i),
                                      .dst_clk_i(eclk_i), .dst_rst_ni(erst_ni), .dst_bin_o(pop_e));
  ca_gray_xfer #(.W(PW)) i_x_release (.src_clk_i(eclk_i), .src_rst_ni(erst_ni), .src_bin_i(rel_ptr),
                                      .dst_clk_i(aclk_i), .dst_rst_ni(arst_ni), .dst_bin_o(rel_a));

  // ------------------------------------------------------------ row RAMs
  logic [XW-1:0]     raddr;
  logic [CELL_W-1:0] rdata [SLOTS];
  for (genvar s = 0; s < SLOTS; s++) begin : g_slot
    ca_ram_sdp_asym #(.WR_W(DATA_W), .RD_W(CELL_W), .RD_DEPTH(GRID_X)) i_ram (
      .wclk_i(aclk_i), .we_i(wr_en_i && wr_slot_i == SLW'(s)), .waddr_i(wr_addr_i),
      .wdata_i(wr_data_i), .rclk_i(eclk_i), .raddr_i(raddr), .rdata_o(rdata[s]));
  end

  // ------------------------------------------------------- drain (eclk)
  typedef enum logic [1:0] {S_IDLE, S_ROW, S_FLUSH} state_e;
  state_e         state;
  logic [PW-1:0]  started;
  logic [SLW-1:0] base;        // slot of window row 0
  logic [KW-1:0]  k;
  logic [OW-1:0]  out_cnt;
  logic [SLW:0]   flush_cnt;
  logic           can_start;

  assign can_start = PW'(wr_e - rel_ptr) >= PW'(NBH) && PW'(started - pop_e) < PW'(FIFO_ROWS);

  logic [SLW-1:0] base_inc;
  assign base_inc = (base == SLW'(SLOTS - 1)) ? '0 : base + 1'b1;

  always_ff @(posedge eclk_i) begin
    if (!erst_ni) begin
      state     <= S_IDLE;
      rel_ptr   <= '0;
      started   <= '0;
      base      <= '0;
      k         <= '0;
      raddr     <= '0;
      out_cnt   <= '0;
      flush_cnt <= '0;
    end else begin
      case (state)
        S_IDLE: if (can_start) begin
          state   <= S_ROW;
          k       <= '0;
          raddr   <= (R == 0) ? '0 : XW'(GRID_X - R);
          started <= started + 1'b1;
        end
        S_ROW: begin
          k     <= k + 1'b1;
          raddr <= (raddr == XW'(GRID_X - 1)) ? '0 : raddr + 1'b1;
          if (k == KW'(KMAX - 1)) begin
            rel_ptr <= rel_ptr + 1'b1;
            base    <= base_inc;
            if (out_cnt == OW'(O - 1)) begin
              out_cnt   <= '0;
              flush_cnt <= '0;
              state     <= S_FLUSH;
            end else begin
              out_cnt <= out_cnt + 1'b1;
              state   <= S_IDLE;
            end
          end
        end
        default: begin  // S_FLUSH: release the NBH-1 rows left in the window
          rel_ptr   <= rel_ptr + 1'b1;
          base      <= base_inc;
          flush_cnt <= flush_cnt + 1'b1;
          if (flush_cnt == (SLW + 1)'(NBH - 2)) state <= S_IDLE;
        end
      endcase
    end
  end

  // Stage 1: control aligned with the RAM output (read latency 1).
  logic           s1_act, s1_zero, s1_cv;
  logic [SLW-1:0] s1_base;
  always_ff @(posedge eclk_i) begin
    if (!erst_ni) begin
      s1_act  <= 1'b0;
      s1_zero <= 1'b0;
      s1_cv   <= 1'b0;
      s1_base <= '0;
    end else begin
      s1_act  <= state == S_ROW;
      s1_zero <= HZ && (k < KW'(R) || k >= KW'(GRID_X + R));
      s1_cv   <= k >= KW'(2 * R);
      s1_base <= base;
    end
  end

  // Stage 2: rotate the NBH+1 slot outputs into window-row order.
  always_ff @(posedge eclk_i) begin
    for (int unsigned i = 0; i < NBH; i++) begin
      automatic logic [SLW:0] s = (SLW + 1)'(s1_base) + (SLW + 1)'(i);
      if (s >= (SLW + 1)'(SLOTS)) s = s - (SLW + 1)'(SLOTS);
      col_o[i] <= s1_zero ? '0 : rdata[s[SLW-1:0]];
    end
  end

  always_ff @(posedge eclk_i) begin
    if (!erst_ni) vld_o <= 1'b0;
    else          vld_o <= s1_act && s1_cv;
  end

  if (GRID_X * CELL_W % DATA_W != 0) begin : g_bad_x
    $error("ca_line_buffer: GRID_X*CELL_W must be a multiple of DATA_W");
  end
  if (FIFO_ROWS >= (1 << (PW - 1))) begin : g_bad_fifo
    $error("ca_line_buffer: FIFO_ROWS too large for PW");
  end
endmodule
