// Cell-to-RGB palettes of the display consumer (values equal
// model/ca_model/grids.py palette_lut). Latency 1.
//   "gray"             linear grey ramp
//   "legacy4_windows"  legacy Windows 16-colour palette (4-bit DAC values x 17)
//   "legacy4_gradient" legacy 4-bit grey gradient
//   "legacy8"          legacy black-red-white gradient for 8-bit cells
module ca_palette #(
  parameter int unsigned CELL_W  = 8,
  parameter string       PALETTE = "gray"
) (
  input  logic              clk_i,
  input  logic [CELL_W-1:0] cell_i,
  output logic [23:0]       rgb_o
);
  localparam int unsigned N = 1 << CELL_W;

  // 4-bit DAC triplets {r, g, b} of the legacy Windows palette.
  localparam logic [11:0] WIN16 [16] = '{
    12'h000, 12'hB00, 12'h0B0, 12'hB60, 12'h00B, 12'hB0B, 12'h0BB, 12'hBBB,
    12'h666, 12'hF22, 12'h6F6, 12'hFF2, 12'h22F, 12'hF6F, 12'h6FF, 12'hFFF};

  // Evaluated at elaboration only (table initialisation), which the lint tool
  // reports as unused locals.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [23:0] lut(int unsigned c);
    logic [7:0] g;
    if (PALETTE == "legacy4_windows") begin
      return {8'(WIN16[c[3:0]][11:8] * 17), 8'(WIN16[c[3:0]][7:4] * 17), 8'(WIN16[c[3:0]][3:0] * 17)};
    end else if (PALETTE == "legacy4_gradient") begin
      g = 8'(c * 17);
      return {g, g, g};
    end else if (PALETTE == "legacy8") begin
      if ((c >> 4) == 0) return {8'((c & 15) * 17), 8'd0, 8'd0};
      return {8'd255, 8'((c >> 4) * 17), 8'((c >> 4) * 17)};
    end
    // "gray": round(c * 255 / (N - 1))
    g = 8'((c * 255 * 2 + (N - 1)) / (2 * (N - 1)));
    return {g, g, g};
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  logic [23:0] table_q [N];
  initial for (int unsigned c = 0; c < N; c++) table_q[c] = lut(c);

  always_ff @(posedge clk_i) rgb_o <= table_q[cell_i];

  if ((PALETTE == "legacy4_windows" || PALETTE == "legacy4_gradient") && CELL_W != 4) begin : g_bad4
    $error("ca_palette: 4-bit palette with CELL_W != 4");
  end
  if (PALETTE == "legacy8" && CELL_W != 8) begin : g_bad8
    $error("ca_palette: legacy8 palette needs CELL_W = 8");
  end
endmodule
