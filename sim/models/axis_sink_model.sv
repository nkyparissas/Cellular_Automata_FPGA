// AXI4-Stream frame sink with random backpressure.
//   +sink_stall=<0..95>  percentage of cycles tready is low
//   +sink_req=<0|1>      1: pulse frame_req_o 0..200 cycles after each frame
// Checks tuser on the first beat of a frame and tlast on every row end, and
// keeps the last complete frame in frame[].
module axis_sink_model #(
  parameter int unsigned DATA_W        = 128,
  parameter int unsigned BEATS_PER_ROW = 4,
  parameter int unsigned ROWS          = 4
) (
  input  logic              clk_i,
  input  logic              rst_ni,
  input  logic [DATA_W-1:0] tdata_i,
  input  logic              tvalid_i,
  output logic              tready_o,
  input  logic              tlast_i,
  input  logic              tuser_i,
  output logic              frame_req_o
);
  localparam int unsigned BEATS = BEATS_PER_ROW * ROWS;

  logic [DATA_W-1:0] frame [BEATS];
  logic [DATA_W-1:0] cur   [BEATS];
  int unsigned stall = 0, req_mode = 0, beat = 0, frames_seen = 0, req_wait = 0;
  bit          req_armed = 0;

  initial begin
    void'($value$plusargs("sink_stall=%d", stall));
    void'($value$plusargs("sink_req=%d", req_mode));
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tready_o    <= 1'b0;
      frame_req_o <= 1'b0;
      beat        <= 0;
    end else begin
      tready_o    <= $urandom_range(99) >= stall;
      frame_req_o <= 1'b0;
      if (req_armed) begin
        if (req_wait == 0) begin
          frame_req_o <= 1'b1;
          req_armed   <= 0;
        end else begin
          req_wait <= req_wait - 1;
        end
      end
      if (tvalid_i && tready_o) begin
        if (tuser_i != (beat == 0)) $fatal(1, "axis_sink_model: tuser=%0d on beat %0d", tuser_i, beat);
        if (tlast_i != ((beat % BEATS_PER_ROW) == BEATS_PER_ROW - 1))
          $fatal(1, "axis_sink_model: tlast=%0d on beat %0d", tlast_i, beat);
        cur[beat] = tdata_i;
        if (beat == BEATS - 1) begin
          frame       = cur;
          frames_seen <= frames_seen + 1;
          beat        <= 0;
          if (req_mode != 0) begin
            req_armed <= 1;
            req_wait  <= $urandom_range(200);
          end
        end else begin
          beat <= beat + 1;
        end
      end
    end
  end
endmodule
