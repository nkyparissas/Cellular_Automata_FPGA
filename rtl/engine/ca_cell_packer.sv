// Packs a stream of cells into DATA_W-bit words, first cell in the low bits.
module ca_cell_packer #(
  parameter int unsigned CELL_W = 8,
  parameter int unsigned DATA_W = 128
) (
  input  logic              clk_i,
  input  logic              rst_ni,
  input  logic [CELL_W-1:0] cell_i,
  input  logic              vld_i,
  output logic [DATA_W-1:0] word_o,
  output logic              word_vld_o
);
  localparam int unsigned PER = DATA_W / CELL_W;
  localparam int unsigned CW  = PER > 1 ? $clog2(PER) : 1;

  logic [DATA_W-1:0] acc;
  logic [CW-1:0]     cnt;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cnt        <= '0;
      word_vld_o <= 1'b0;
    end else begin
      word_vld_o <= vld_i && (cnt == CW'(PER - 1));
      if (vld_i) cnt <= (cnt == CW'(PER - 1)) ? '0 : cnt + 1'b1;
    end
  end

  // Shift in from the top so the first cell ends up in the low bits.
  always_ff @(posedge clk_i) begin
    if (vld_i) acc <= {cell_i, acc[DATA_W-1:CELL_W]};
  end
  assign word_o = acc;

  if (DATA_W % CELL_W != 0) begin : g_bad
    $error("ca_cell_packer: DATA_W must be a multiple of CELL_W");
  end
endmodule
