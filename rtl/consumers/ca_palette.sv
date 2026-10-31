// Cell-to-RGB palettes of the display consumer (values equal
// model/ca_model/grids.py palette_lut). Latency 1.
//   "gray"             linear grey ramp
//   "legacy4_windows"  legacy Windows 16-colour palette (4-bit DAC values x 17)
//   "legacy4_gradient" legacy 4-bit grey gradient
//   "legacy8"          legacy black-red-white gradient for 8-bit cells
//   "viridis"          viridis colour map (cells of 8 bits or more)
// Cells wider than 8 bits index the table with their top 8 bits.
module ca_palette #(
  parameter int unsigned CELL_W  = 8,
  parameter string       PALETTE = "gray"
) (
  input  logic              clk_i,
  input  logic [CELL_W-1:0] cell_i,
  output logic [23:0]       rgb_o
);
  localparam int unsigned IW = CELL_W < 8 ? CELL_W : 8;
  localparam int unsigned N  = 1 << IW;

  // 4-bit DAC triplets {r, g, b} of the legacy Windows palette.
  localparam logic [11:0] WIN16 [16] = '{
    12'h000, 12'hB00, 12'h0B0, 12'hB60, 12'h00B, 12'hB0B, 12'h0BB, 12'hBBB,
    12'h666, 12'hF22, 12'h6F6, 12'hFF2, 12'h22F, 12'hF6F, 12'h6FF, 12'hFFF};

  // viridis (model/ca_model/viridis.py, CC0 data of BIDS/colormap).
  localparam logic [23:0] VIRIDIS [256] = '{
    24'h440154, 24'h440256, 24'h450457, 24'h450559, 24'h46075A, 24'h46085C, 24'h460A5D, 24'h460B5E,
    24'h470D60, 24'h470E61, 24'h471063, 24'h471164, 24'h471365, 24'h481467, 24'h481668, 24'h481769,
    24'h48186A, 24'h481A6C, 24'h481B6D, 24'h481C6E, 24'h481D6F, 24'h481F70, 24'h482071, 24'h482173,
    24'h482374, 24'h482475, 24'h482576, 24'h482677, 24'h482878, 24'h482979, 24'h472A7A, 24'h472C7A,
    24'h472D7B, 24'h472E7C, 24'h472F7D, 24'h46307E, 24'h46327E, 24'h46337F, 24'h463480, 24'h453581,
    24'h453781, 24'h453882, 24'h443983, 24'h443A83, 24'h443B84, 24'h433D84, 24'h433E85, 24'h423F85,
    24'h424086, 24'h424186, 24'h414287, 24'h414487, 24'h404588, 24'h404688, 24'h3F4788, 24'h3F4889,
    24'h3E4989, 24'h3E4A89, 24'h3E4C8A, 24'h3D4D8A, 24'h3D4E8A, 24'h3C4F8A, 24'h3C508B, 24'h3B518B,
    24'h3B528B, 24'h3A538B, 24'h3A548C, 24'h39558C, 24'h39568C, 24'h38588C, 24'h38598C, 24'h375A8C,
    24'h375B8D, 24'h365C8D, 24'h365D8D, 24'h355E8D, 24'h355F8D, 24'h34608D, 24'h34618D, 24'h33628D,
    24'h33638D, 24'h32648E, 24'h32658E, 24'h31668E, 24'h31678E, 24'h31688E, 24'h30698E, 24'h306A8E,
    24'h2F6B8E, 24'h2F6C8E, 24'h2E6D8E, 24'h2E6E8E, 24'h2E6F8E, 24'h2D708E, 24'h2D718E, 24'h2C718E,
    24'h2C728E, 24'h2C738E, 24'h2B748E, 24'h2B758E, 24'h2A768E, 24'h2A778E, 24'h2A788E, 24'h29798E,
    24'h297A8E, 24'h297B8E, 24'h287C8E, 24'h287D8E, 24'h277E8E, 24'h277F8E, 24'h27808E, 24'h26818E,
    24'h26828E, 24'h26828E, 24'h25838E, 24'h25848E, 24'h25858E, 24'h24868E, 24'h24878E, 24'h23888E,
    24'h23898E, 24'h238A8D, 24'h228B8D, 24'h228C8D, 24'h228D8D, 24'h218E8D, 24'h218F8D, 24'h21908D,
    24'h21918C, 24'h20928C, 24'h20928C, 24'h20938C, 24'h1F948C, 24'h1F958B, 24'h1F968B, 24'h1F978B,
    24'h1F988B, 24'h1F998A, 24'h1F9A8A, 24'h1E9B8A, 24'h1E9C89, 24'h1E9D89, 24'h1F9E89, 24'h1F9F88,
    24'h1FA088, 24'h1FA188, 24'h1FA187, 24'h1FA287, 24'h20A386, 24'h20A486, 24'h21A585, 24'h21A685,
    24'h22A785, 24'h22A884, 24'h23A983, 24'h24AA83, 24'h25AB82, 24'h25AC82, 24'h26AD81, 24'h27AD81,
    24'h28AE80, 24'h29AF7F, 24'h2AB07F, 24'h2CB17E, 24'h2DB27D, 24'h2EB37C, 24'h2FB47C, 24'h31B57B,
    24'h32B67A, 24'h34B679, 24'h35B779, 24'h37B878, 24'h38B977, 24'h3ABA76, 24'h3BBB75, 24'h3DBC74,
    24'h3FBC73, 24'h40BD72, 24'h42BE71, 24'h44BF70, 24'h46C06F, 24'h48C16E, 24'h4AC16D, 24'h4CC26C,
    24'h4EC36B, 24'h50C46A, 24'h52C569, 24'h54C568, 24'h56C667, 24'h58C765, 24'h5AC864, 24'h5CC863,
    24'h5EC962, 24'h60CA60, 24'h63CB5F, 24'h65CB5E, 24'h67CC5C, 24'h69CD5B, 24'h6CCD5A, 24'h6ECE58,
    24'h70CF57, 24'h73D056, 24'h75D054, 24'h77D153, 24'h7AD151, 24'h7CD250, 24'h7FD34E, 24'h81D34D,
    24'h84D44B, 24'h86D549, 24'h89D548, 24'h8BD646, 24'h8ED645, 24'h90D743, 24'h93D741, 24'h95D840,
    24'h98D83E, 24'h9BD93C, 24'h9DD93B, 24'hA0DA39, 24'hA2DA37, 24'hA5DB36, 24'hA8DB34, 24'hAADC32,
    24'hADDC30, 24'hB0DD2F, 24'hB2DD2D, 24'hB5DE2B, 24'hB8DE29, 24'hBADE28, 24'hBDDF26, 24'hC0DF25,
    24'hC2DF23, 24'hC5E021, 24'hC8E020, 24'hCAE11F, 24'hCDE11D, 24'hD0E11C, 24'hD2E21B, 24'hD5E21A,
    24'hD8E219, 24'hDAE319, 24'hDDE318, 24'hDFE318, 24'hE2E418, 24'hE5E419, 24'hE7E419, 24'hEAE51A,
    24'hECE51B, 24'hEFE51C, 24'hF1E51D, 24'hF4E61E, 24'hF6E620, 24'hF8E621, 24'hFBE723, 24'hFDE725};

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
    end else if (PALETTE == "viridis") begin
      return VIRIDIS[c[7:0]];
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

  always_ff @(posedge clk_i) rgb_o <= table_q[cell_i[CELL_W-1 -: IW]];

  if (CELL_W > 8) begin : g_unused_low
    logic unused_low;
    assign unused_low = ^cell_i[CELL_W-9:0];   // only the top 8 bits select a colour
  end

  if ((PALETTE == "legacy4_windows" || PALETTE == "legacy4_gradient") && CELL_W != 4) begin : g_bad4
    $error("ca_palette: 4-bit palette with CELL_W != 4");
  end
  if (PALETTE == "viridis" && CELL_W < 8) begin : g_badv
    $error("ca_palette: viridis needs CELL_W >= 8");
  end
  if (PALETTE == "legacy8" && CELL_W != 8) begin : g_bad8
    $error("ca_palette: legacy8 palette needs CELL_W = 8");
  end
endmodule
