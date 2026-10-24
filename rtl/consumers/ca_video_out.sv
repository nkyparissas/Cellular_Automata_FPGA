// Display consumer (spec Section 13). Frames arrive on AXI4-Stream (aclk),
// cross into the pixel clock through an async FIFO and are shown with
// generic video timing. Once per video frame, when the line counter reaches
// REQ_LINE, frame_req_o pulses in aclk ("ready for a new buffer"). The
// output waits for a word tagged tuser before showing a frame; if data runs
// out during a frame it shows black, raises underflow_o (sticky) and
// resynchronises on the next tuser.
module ca_video_out #(
  parameter int unsigned DATA_W     = 128,
  parameter int unsigned CELL_W     = 8,
  parameter int unsigned H_ACTIVE   = 1920,
  parameter int unsigned H_FP       = 88,
  parameter int unsigned H_SYNC     = 44,
  parameter int unsigned H_BP       = 148,
  parameter int unsigned V_ACTIVE   = 1080,
  parameter int unsigned V_FP       = 4,
  parameter int unsigned V_SYNC     = 5,
  parameter int unsigned V_BP       = 36,
  parameter bit          HS_POL     = 1'b1,
  parameter bit          VS_POL     = 1'b1,
  parameter int unsigned REQ_LINE   = 1081,
  parameter int unsigned FIFO_DEPTH = 256,
  parameter string       PALETTE    = "legacy8"
) (
  input  logic              aclk_i,
  input  logic              arst_ni,
  input  logic [DATA_W-1:0] s_axis_tdata_i,
  input  logic              s_axis_tvalid_i,
  output logic              s_axis_tready_o,
  input  logic              s_axis_tlast_i,
  input  logic              s_axis_tuser_i,
  output logic              frame_req_o,
  input  logic              pclk_i,
  input  logic              prst_ni,
  output logic              hsync_o,
  output logic              vsync_o,
  output logic              de_o,
  output logic [23:0]       rgb_o,
  output logic              underflow_o
);
  localparam int unsigned HT  = H_ACTIVE + H_FP + H_SYNC + H_BP;
  localparam int unsigned VT  = V_ACTIVE + V_FP + V_SYNC + V_BP;
  localparam int unsigned HW  = $clog2(HT);
  localparam int unsigned VW  = $clog2(VT);
  localparam int unsigned PER = DATA_W / CELL_W;
  localparam int unsigned PW  = PER > 1 ? $clog2(PER) : 1;

  // Row boundaries are implicit in the pixel count, so tlast is not needed.
  logic unused_tlast;
  assign unused_tlast = s_axis_tlast_i;

  // ------------------------------------------------------- stream -> pclk
  logic              f_valid, f_ready, f_user;
  logic [DATA_W-1:0] f_data;
  ca_async_fifo #(.W(DATA_W + 1), .DEPTH(FIFO_DEPTH)) i_fifo (
    .wclk_i(aclk_i), .wrst_ni(arst_ni), .w_valid_i(s_axis_tvalid_i), .w_ready_o(s_axis_tready_o),
    .w_data_i({s_axis_tuser_i, s_axis_tdata_i}),
    .rclk_i(pclk_i), .rrst_ni(prst_ni), .r_valid_o(f_valid), .r_ready_i(f_ready), .r_data_o({f_user, f_data}));

  // ------------------------------------------------------------- timing
  logic [HW-1:0] h;
  logic [VW-1:0] v;
  logic          active, frame_start;
  assign active      = h < HW'(H_ACTIVE) && v < VW'(V_ACTIVE);
  assign frame_start = h == '0 && v == '0;

  always_ff @(posedge pclk_i) begin
    if (!prst_ni) begin
      h <= '0;
      v <= '0;
    end else if (h == HW'(HT - 1)) begin
      h <= '0;
      v <= (v == VW'(VT - 1)) ? '0 : v + 1'b1;
    end else begin
      h <= h + 1'b1;
    end
  end

  // -------------------------------------------------------- pixel fetch
  logic              synced, shown;   // shown: this frame is being displayed
  logic [PW-1:0]     pix;
  logic [DATA_W-1:0] word;
  logic              need, have, drop;

  assign need = active && pix == '0;                       // a new word is due now
  assign have = f_valid && (frame_start ? f_user : !f_user);
  // Outside a shown frame, discard words until the head is a frame start.
  assign drop = !shown && f_valid && !f_user && !(frame_start && synced);
  assign f_ready = (need && shown_next && have) || drop;

  logic shown_next;
  always_comb begin
    shown_next = shown;
    if (frame_start) shown_next = f_valid && f_user;
  end

  always_ff @(posedge pclk_i) begin
    if (!prst_ni) begin
      synced      <= 1'b0;
      shown       <= 1'b0;
      pix         <= '0;
      underflow_o <= 1'b0;
    end else begin
      if (frame_start) begin
        shown <= f_valid && f_user;
        // A frame that has not arrived by its first pixel is an underflow too.
        if (synced && !(f_valid && f_user)) begin
          underflow_o <= 1'b1;
          synced      <= 1'b0;
        end
      end
      if (active) pix <= (pix == PW'(PER - 1)) ? '0 : pix + 1'b1;
      if (frame_start && !active) pix <= '0;
      if (need && shown_next) begin
        if (have) begin
          word   <= f_data;
          synced <= 1'b1;
        end else begin
          if (synced) underflow_o <= 1'b1;
          synced <= 1'b0;
          shown  <= 1'b0;
        end
      end else if (active) begin
        word <= word >> CELL_W;
      end
    end
  end

  // Pixel stage: the cell shown now is the low cell of `word` after the
  // fetch/shift above, so the visible pipeline is: counters -> word -> palette.
  logic              de_q, hs_q, vs_q, shown_q;
  logic [CELL_W-1:0] cell_q;
  always_ff @(posedge pclk_i) begin
    if (!prst_ni) begin
      de_q    <= 1'b0;
      hs_q    <= !HS_POL;
      vs_q    <= !VS_POL;
      shown_q <= 1'b0;
    end else begin
      de_q    <= active;
      hs_q    <= (h >= HW'(H_ACTIVE + H_FP) && h < HW'(H_ACTIVE + H_FP + H_SYNC)) ? HS_POL : !HS_POL;
      vs_q    <= (v >= VW'(V_ACTIVE + V_FP) && v < VW'(V_ACTIVE + V_FP + V_SYNC)) ? VS_POL : !VS_POL;
      shown_q <= shown_next && !(need && !have);
    end
  end
  assign cell_q = word[CELL_W-1:0];

  logic [23:0] rgb_pal;
  ca_palette #(.CELL_W(CELL_W), .PALETTE(PALETTE)) i_pal (.clk_i(pclk_i), .cell_i(cell_q), .rgb_o(rgb_pal));

  logic de_qq, hs_qq, vs_qq, shown_qq;
  always_ff @(posedge pclk_i) begin
    if (!prst_ni) begin
      de_qq    <= 1'b0;
      hs_qq    <= !HS_POL;
      vs_qq    <= !VS_POL;
      shown_qq <= 1'b0;
    end else begin
      de_qq    <= de_q;
      hs_qq    <= hs_q;
      vs_qq    <= vs_q;
      shown_qq <= shown_q;
    end
  end
  assign de_o    = de_qq;
  assign hsync_o = hs_qq;
  assign vsync_o = vs_qq;
  assign rgb_o   = (de_qq && shown_qq) ? rgb_pal : 24'h0;

  // ------------------------------------------------- frame request (aclk)
  logic req_tog, req_s, req_q;
  always_ff @(posedge pclk_i) begin
    if (!prst_ni) req_tog <= 1'b0;
    else if (h == '0 && v == VW'(REQ_LINE)) req_tog <= !req_tog;
  end
  ca_sync #(.W(1)) i_req_sync (.clk_i(aclk_i), .d_i(req_tog), .q_o(req_s));
  always_ff @(posedge aclk_i) begin
    if (!arst_ni) begin
      req_q       <= 1'b0;
      frame_req_o <= 1'b0;
    end else begin
      req_q       <= req_s;
      frame_req_o <= req_s != req_q;
    end
  end

  if (DATA_W % CELL_W != 0 || H_ACTIVE % PER != 0) begin : g_bad
    $error("ca_video_out: H_ACTIVE must be a whole number of DATA_W words");
  end
  if (REQ_LINE >= VT) begin : g_bad_req
    $error("ca_video_out: REQ_LINE outside the frame");
  end
endmodule
