// ca_video_out testbench with a small video timing. A source streams the
// next frame of +frames_hex on every frame request (skipping request
// +starve_req if given); every displayed pixel is written to +out_file as
// "<frame> <rgb>" lines.
`timescale 1ns/1ps
module tb_video #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned CELL_W = 8,
  parameter int unsigned PAL_ID = 0,      // 0 gray, 1 legacy4_windows, 2 legacy4_gradient, 3 legacy8
  parameter int unsigned NFRAMES = 6
);
  localparam int unsigned HA = 16, HFP = 2, HS = 3, HB = 2, VA = 8, VFP = 1, VS = 2, VB = 1;
  localparam int unsigned HT = HA + HFP + HS + HB, VT = VA + VFP + VS + VB;
  localparam int unsigned WPF = HA * VA * CELL_W / DATA_W;
  localparam string       PAL = PAL_ID == 1 ? "legacy4_windows" : PAL_ID == 2 ? "legacy4_gradient" :
                                PAL_ID == 3 ? "legacy8" : "gray";

  logic aclk = 0, pclk = 0, rst_n = 0;
  always #3 aclk = ~aclk;
  always #5 pclk = ~pclk;

  logic [DATA_W-1:0] tdata;
  logic              tvalid = 0, tready, tlast, tuser, frame_req, hs, vs, de, underflow;
  logic [23:0]       rgb;

  ca_video_out #(.DATA_W(DATA_W), .CELL_W(CELL_W), .H_ACTIVE(HA), .H_FP(HFP), .H_SYNC(HS), .H_BP(HB),
                 .V_ACTIVE(VA), .V_FP(VFP), .V_SYNC(VS), .V_BP(VB), .HS_POL(1'b1), .VS_POL(1'b0),
                 .REQ_LINE(VA + 1), .FIFO_DEPTH(16), .PALETTE(PAL)) dut (
    .aclk_i(aclk), .arst_ni(rst_n), .s_axis_tdata_i(tdata), .s_axis_tvalid_i(tvalid),
    .s_axis_tready_o(tready), .s_axis_tlast_i(tlast), .s_axis_tuser_i(tuser), .frame_req_o(frame_req),
    .pclk_i(pclk), .prst_ni(rst_n), .hsync_o(hs), .vsync_o(vs), .de_o(de), .rgb_o(rgb), .underflow_o(underflow));

  logic [DATA_W-1:0] frames [NFRAMES * WPF];
  string frames_hex, out_file;
  int fd, starve = -1, reqs = 0, served = 0, vframe = -1;

  // Source: on each request stream the next frame (aclk, negedge driven).
  initial begin
    if (!$value$plusargs("frames_hex=%s", frames_hex)) $fatal(1, "+frames_hex missing");
    if (!$value$plusargs("out_file=%s", out_file)) $fatal(1, "+out_file missing");
    void'($value$plusargs("starve_req=%d", starve));
    $readmemh(frames_hex, frames);
    fd = $fopen(out_file, "w");
    repeat (4) @(posedge aclk);
    rst_n = 1;
    forever begin
      @(negedge aclk);
      if (frame_req) begin
        reqs++;
        if (reqs - 1 != starve) begin   // frames repeat cyclically after NFRAMES
          for (int unsigned w = 0; w < WPF; w++) begin
            tvalid = 1;
            tdata  = frames[(served % NFRAMES) * WPF + w];
            tuser  = w == 0;
            tlast  = ((w + 1) % (HA * CELL_W / DATA_W)) == 0;
            while (!tready) @(negedge aclk);
            @(negedge aclk);
          end
          tvalid = 0;
          served++;
        end
      end
    end
  end

  // Monitor: video frame index increments at each vsync start; check widths.
  int hs_len = 0, vs_lines = 0;
  logic vs_q = 1;
  always @(posedge pclk) begin
    if (rst_n) begin
      if (hs) hs_len++;
      else begin
        if (hs_len != 0 && hs_len != HS) $fatal(1, "hsync width %0d", hs_len);
        hs_len = 0;
      end
      if (vs_q && !vs) vframe++;           // active-low vsync starts
      vs_q = vs;
      if (de) $fwrite(fd, "%0d %06h\n", vframe, rgb);
      if (vframe == NFRAMES + 2) begin
        $fclose(fd);
        if (reqs < NFRAMES + 1) $fatal(1, "only %0d frame requests", reqs);
        $display("TB_PASS reqs=%0d served=%0d underflow=%0d", reqs, served, underflow);
        $finish;
      end
    end
  end

  initial begin
    repeat ((NFRAMES + 5) * HT * VT * 2) @(posedge pclk);
    $fatal(1, "timeout");
  end
endmodule
