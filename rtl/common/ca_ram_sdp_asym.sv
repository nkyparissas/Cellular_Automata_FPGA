// Simple dual-port RAM with a wide write port and a narrow, registered read
// port (latency 1). Narrow index k reads bits [(k % R)*RD_W +: RD_W] of wide
// word k / R, R = WR_W / RD_W. Coded after the Vivado UG901 asymmetric-RAM
// template so that block RAM is inferred.
module ca_ram_sdp_asym #(
  parameter int unsigned WR_W     = 128,
  parameter int unsigned RD_W     = 8,
  parameter int unsigned RD_DEPTH = 1024,
  localparam int unsigned RATIO   = WR_W / RD_W,
  localparam int unsigned RA      = $clog2(RD_DEPTH),
  localparam int unsigned WA      = (RD_DEPTH / RATIO) > 1 ? $clog2(RD_DEPTH / RATIO) : 1
) (
  input  logic            wclk_i,
  input  logic            we_i,
  input  logic [WA-1:0]   waddr_i,
  input  logic [WR_W-1:0] wdata_i,
  input  logic            rclk_i,
  input  logic [RA-1:0]   raddr_i,
  output logic [RD_W-1:0] rdata_o
);
  localparam int unsigned LR = $clog2(RATIO);

  logic [RD_W-1:0] ram [RD_DEPTH];

  if (RATIO == 1) begin : g_sym
    always_ff @(posedge wclk_i) begin
      if (we_i) ram[RA'(waddr_i)] <= wdata_i;
    end
  end else begin : g_asym
    always_ff @(posedge wclk_i) begin
      if (we_i) begin
        for (int unsigned i = 0; i < RATIO; i++) begin
          ram[RA'({waddr_i, LR'(i)})] <= wdata_i[i*RD_W +: RD_W];
        end
      end
    end
  end

  always_ff @(posedge rclk_i) rdata_o <= ram[raddr_i];

  if (WR_W % RD_W != 0 || (1 << LR) != RATIO || RD_DEPTH % RATIO != 0) begin : g_bad
    $error("ca_ram_sdp_asym: WR_W/RD_W must be a power of two dividing RD_DEPTH");
  end
endmodule
