// Exposes ca_pkg helper results for the unit test (grid_y = 20, nbh = 5).
module tb_pkg_funcs (
  output logic [63:0] virt_o,
  output logic [63:0] outr_o,
  output logic [63:0] first_o,
  output logic [3:0]  hzero_o,
  output logic [39:0] tlat_o
);
  import ca_pkg::*;
  for (genvar b = 0; b < 4; b++) begin : g_b
    localparam boundary_e B = boundary_e'(b);
    assign virt_o[16*b +: 16]  = 16'(virt_rows(20, 5, B));
    assign outr_o[16*b +: 16]  = 16'(out_rows(20, 5, B));
    assign first_o[16*b +: 16] = 16'(out_row_first(5, B));
    assign hzero_o[b]          = hzero(B);
  end
  assign tlat_o = {8'(tree_lat(841)), 8'(tree_lat(441)), 8'(tree_lat(9)), 8'(tree_lat(2)), 8'(tree_lat(1))};
endmodule
