// AXI4 frame reader (spec Sections 5 and 8). For every virtual row of a pass
// it allocates a line-buffer slot, issues the row's read bursts (at most
// MAX_BURST beats, never across 4 KB) and writes the returned beats into
// that slot; zero rows are written without memory traffic. Rows of the
// frame proper are forwarded to the consumer stream when fwd_en_i is set,
// and the consumer's backpressure stalls the R channel.
// Only the AR and R fields of axi_req_o are driven.
module ca_frame_reader #(
  parameter int unsigned       GRID_X    = 64,
  parameter int unsigned       GRID_Y    = 24,
  parameter int unsigned       CELL_W    = 8,
  parameter int unsigned       NBH       = 5,
  parameter int unsigned       DATA_W    = 128,
  parameter int unsigned       ADDR_W    = 32,
  parameter ca_pkg::boundary_e BND       = ca_pkg::BND_TOROIDAL,
  parameter int unsigned       MAX_BURST = 64,
  parameter type               axi_req_t  = logic,
  parameter type               axi_resp_t = logic,
  localparam int unsigned      SLW       = $clog2(NBH + 1),
  localparam int unsigned      BPR       = GRID_X * CELL_W / DATA_W,
  localparam int unsigned      BW        = BPR > 1 ? $clog2(BPR) : 1
) (
  input  logic              clk_i,
  input  logic              rst_ni,
  input  logic              start_i,
  input  logic [ADDR_W-1:0] base_addr_i,
  input  logic              fwd_en_i,
  output logic              done_o,
  output axi_req_t          axi_req_o,
  // Read-only master: the write-channel and R id/resp/last fields are unused.
  /* verilator lint_off UNUSEDSIGNAL */
  input  axi_resp_t         axi_resp_i,
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [DATA_W-1:0] m_axis_tdata_o,
  output logic              m_axis_tvalid_o,
  input  logic              m_axis_tready_i,
  output logic              m_axis_tlast_o,
  output logic              m_axis_tuser_o,
  output logic              lb_alloc_valid_o,
  input  logic              lb_alloc_ready_i,
  input  logic [SLW-1:0]    lb_alloc_slot_i,
  output logic              lb_wr_en_o,
  output logic [SLW-1:0]    lb_wr_slot_o,
  output logic [BW-1:0]     lb_wr_addr_o,
  output logic [DATA_W-1:0] lb_wr_data_o,
  output logic              lb_row_done_o
);
  localparam int unsigned R         = (NBH - 1) / 2;
  localparam int unsigned V         = ca_pkg::virt_rows(GRID_Y, NBH, BND);
  localparam int unsigned VW        = $clog2(V + 1);
  localparam int unsigned BYTES     = DATA_W / 8;
  localparam int unsigned SIZE      = $clog2(BYTES);
  localparam int unsigned ROW_BYTES = GRID_X * CELL_W / 8;
  localparam int unsigned CW        = $clog2(BPR + 1);
  localparam int unsigned DQ        = 4;   // row descriptors in flight

  typedef struct packed {
    logic [SLW-1:0] slot;
    logic           zero;
    logic           fwd;
    logic           sof;
  } desc_t;

  // ------------------------------------------------------------- issue side
  typedef enum logic [1:0] {I_IDLE, I_ALLOC, I_AR} istate_e;
  istate_e           istate;
  logic [VW-1:0]     v;
  logic [ADDR_W-1:0] base_q, ar_addr;
  logic              fwd_q;
  logic [CW-1:0]     ar_rem;
  logic              desc_full, desc_push, desc_empty, desc_pop;
  desc_t             desc_in, desc_out;
  logic              r_ready, beat_go, last_beat;
  logic [BW-1:0]     beat;
  logic [VW-1:0]     rows_rx;

  // Virtual row v -> memory row, zero flag, forward flag (spec Section 5).
  logic              v_zero, v_fwd;
  logic [VW-1:0]     v_src;
  always_comb begin
    v_zero = 1'b0;
    v_fwd  = 1'b1;
    v_src  = v;
    if (BND == ca_pkg::BND_TOROIDAL) begin
      v_src = (v < VW'(R)) ? VW'(int'(v) + GRID_Y - R) :
              (v >= VW'(GRID_Y + R)) ? VW'(int'(v) - GRID_Y - R) : VW'(int'(v) - R);
      v_fwd = v >= VW'(R) && v < VW'(GRID_Y + R);
    end else if (BND == ca_pkg::BND_ZERO) begin
      v_zero = v < VW'(R) || v >= VW'(GRID_Y + R);
      v_src  = VW'(v - R);
      v_fwd  = !v_zero;
    end
  end

  // Burst length: remaining beats, MAX_BURST and the distance to 4 KB.
  logic [12:0] to_4k;
  logic [CW-1:0] ar_len;
  always_comb begin
    to_4k  = 13'(13'd4096 - 13'(ar_addr[11:0])) >> SIZE;
    ar_len = ar_rem;
    if (32'(ar_len) > 32'(MAX_BURST)) ar_len = CW'(MAX_BURST);  // MAX_BURST < ar_rem fits in CW
    if (32'(ar_len) > 32'(to_4k)) ar_len = CW'(to_4k);
  end

  assign lb_alloc_valid_o = istate == I_ALLOC && !desc_full;
  assign desc_push        = lb_alloc_valid_o && lb_alloc_ready_i;
  assign desc_in          = '{slot: lb_alloc_slot_i, zero: v_zero, fwd: v_fwd && fwd_q,
                              sof: v_fwd && v_src == '0};

  always_comb begin
    axi_req_o          = '0;
    axi_req_o.ar.addr  = ar_addr;
    axi_req_o.ar.len   = 8'(ar_len - 1'b1);
    axi_req_o.ar.size  = 3'(SIZE);
    axi_req_o.ar.burst = 2'b01;
    axi_req_o.ar.cache = 4'b0011;
    axi_req_o.ar_valid = istate == I_AR;
    axi_req_o.r_ready  = r_ready;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      istate  <= I_IDLE;
      v       <= '0;
      base_q  <= '0;
      fwd_q   <= 1'b0;
      ar_addr <= '0;
      ar_rem  <= '0;
    end else begin
      case (istate)
        I_IDLE: if (start_i) begin
          base_q <= base_addr_i;
          fwd_q  <= fwd_en_i;
          v      <= '0;
          istate <= I_ALLOC;
        end
        I_ALLOC: if (desc_push) begin
          if (v_zero) begin
            v      <= v + 1'b1;
            istate <= (v == VW'(V - 1)) ? I_IDLE : I_ALLOC;
          end else begin
            ar_addr <= base_q + ADDR_W'(v_src) * ADDR_W'(ROW_BYTES);
            ar_rem  <= CW'(BPR);
            istate  <= I_AR;
          end
        end
        default: if (axi_resp_i.ar_ready) begin  // I_AR
          ar_addr <= ar_addr + ADDR_W'(ar_len) * ADDR_W'(BYTES);
          ar_rem  <= ar_rem - ar_len;
          if (ar_rem == ar_len) begin
            v      <= v + 1'b1;
            istate <= (v == VW'(V - 1)) ? I_IDLE : I_ALLOC;
          end
        end
      endcase
    end
  end

  // Descriptor FIFO (issue order == return order: single AXI ID).
  desc_t        dq [DQ];
  logic [2:0]   dq_wr, dq_rd;
  assign desc_full  = (dq_wr - dq_rd) == 3'(DQ);
  assign desc_empty = dq_wr == dq_rd;
  assign desc_out   = dq[dq_rd[1:0]];
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dq_wr <= '0;
      dq_rd <= '0;
    end else begin
      if (desc_push) begin
        dq[dq_wr[1:0]] <= desc_in;
        dq_wr          <= dq_wr + 1'b1;
      end
      if (desc_pop) dq_rd <= dq_rd + 1'b1;
    end
  end

  // ----------------------------------------------------------- receive side
  assign last_beat = beat == BW'(BPR - 1);
  always_comb begin
    beat_go = 1'b0;
    r_ready = 1'b0;
    if (!desc_empty) begin
      if (desc_out.zero) begin
        beat_go = 1'b1;
      end else begin
        r_ready = !desc_out.fwd || m_axis_tready_i;
        beat_go = axi_resp_i.r_valid && r_ready;
      end
    end
  end

  assign desc_pop        = beat_go && last_beat;
  assign lb_wr_en_o      = beat_go;
  assign lb_wr_slot_o    = desc_out.slot;
  assign lb_wr_addr_o    = beat;
  assign lb_wr_data_o    = desc_out.zero ? '0 : axi_resp_i.r.data;
  assign m_axis_tvalid_o = !desc_empty && !desc_out.zero && desc_out.fwd && axi_resp_i.r_valid;
  assign m_axis_tdata_o  = axi_resp_i.r.data;
  assign m_axis_tlast_o  = last_beat;
  assign m_axis_tuser_o  = desc_out.sof && beat == '0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      beat          <= '0;
      rows_rx       <= '0;
      lb_row_done_o <= 1'b0;
      done_o        <= 1'b0;
    end else begin
      lb_row_done_o <= desc_pop;
      done_o        <= 1'b0;
      if (beat_go) beat <= last_beat ? '0 : beat + 1'b1;
      if (desc_pop) begin
        if (rows_rx == VW'(V - 1)) begin
          rows_rx <= '0;
          done_o  <= 1'b1;
        end else begin
          rows_rx <= rows_rx + 1'b1;
        end
      end
    end
  end

  if (GRID_X * CELL_W % DATA_W != 0) begin : g_bad
    $error("ca_frame_reader: GRID_X*CELL_W must be a multiple of DATA_W");
  end
endmodule
