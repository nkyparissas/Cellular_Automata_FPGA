// Project-wide types, rule parameter indices and row-sequence helpers
// (design spec Sections 5 and 11).
package ca_pkg;

  typedef enum logic [1:0] {
    BND_TOROIDAL    = 2'd0,
    BND_CYLINDRICAL = 2'd1,  // legacy: rows wrap horizontally, first/last r rows frozen
    BND_RECTANGULAR = 2'd2,  // legacy: zero columns, first/last r rows frozen
    BND_ZERO        = 2'd3   // full grid, zero padding on every side
  } boundary_e;

  typedef enum logic [3:0] {
    RULE_HODGEPODGE = 4'd0,
    RULE_GHM        = 4'd1,
    RULE_INTERVAL   = 4'd2
  } rule_e;

  localparam int unsigned NUM_RULE_PARAMS = 8;
  typedef logic [NUM_RULE_PARAMS-1:0][31:0] rule_params_t;

  // RULE_PARAM register indices per rule.
  localparam int unsigned HP_G       = 0;
  localparam int unsigned HP_K       = 1;
  localparam int unsigned GHM_T      = 0;
  localparam int unsigned GHM_STATES = 1;
  localparam int unsigned GHM_E      = 2;
  localparam int unsigned IV_LO1     = 0;
  localparam int unsigned IV_HI1     = 1;
  localparam int unsigned IV_LO2     = 2;
  localparam int unsigned IV_HI2     = 3;
  localparam int unsigned IV_ALIVE   = 4;

  function automatic bit full_rows(boundary_e bnd);
    return bnd == BND_TOROIDAL || bnd == BND_ZERO;
  endfunction

  // Rows streamed through the line buffer per pass.
  function automatic int unsigned virt_rows(int unsigned grid_y, int unsigned nbh, boundary_e bnd);
    return full_rows(bnd) ? grid_y + nbh - 1 : grid_y;
  endfunction

  // Rows written back per pass.
  function automatic int unsigned out_rows(int unsigned grid_y, int unsigned nbh, boundary_e bnd);
    return full_rows(bnd) ? grid_y : grid_y - (nbh - 1);
  endfunction

  // Grid row of output row 0.
  function automatic int unsigned out_row_first(int unsigned nbh, boundary_e bnd);
    return full_rows(bnd) ? 0 : (nbh - 1) / 2;
  endfunction

  // Columns outside the grid read as zero.
  function automatic bit hzero(boundary_e bnd);
    return bnd == BND_RECTANGULAR || bnd == BND_ZERO;
  endfunction

  // Latency of ca_adder_tree with n inputs.
  function automatic int unsigned tree_lat(int unsigned n);
    return n <= 1 ? 0 : $clog2(n);
  endfunction

endpackage
