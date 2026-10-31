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
    RULE_INTERVAL   = 4'd2,
    RULE_LENIA      = 4'd3
  } rule_e;

  // Lenia growth-table selection, captured at pass start (active bank and its shift).
  typedef struct packed {
    logic       bank;
    logic [5:0] sh;
  } lenia_sel_t;

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

  // Lenia distance classes of an n x n window (n <= 101): the class of window
  // cell (i, j) is the rank of d = (i-r)^2 + (j-r)^2 among the distinct values
  // of d <= r^2, r = (n-1)/2, so class 0 is the centre; cells with d > r^2
  // belong to no class (model/ca_model/lenia.py class_map).
  localparam int LENIA_D_MAX = 2500;

  // Number of classes C.
  function automatic int unsigned lenia_classes(int unsigned n);
    int                     r;
    logic [LENIA_D_MAX:0]   seen;
    r    = int'((n - 1) / 2);
    seen = '0;
    for (int a = 0; a <= r; a++)
      for (int b = 0; b <= r; b++)
        if (a * a + b * b <= r * r) seen[a*a + b*b] = 1'b1;
    return $countones(seen);
  endfunction

  // Largest number of window cells in one class.
  function automatic int unsigned lenia_max_cells(int unsigned n);
    int                       r, m;
    logic [LENIA_D_MAX:0][7:0] cnt;
    r   = int'((n - 1) / 2);
    for (int d = 0; d <= LENIA_D_MAX; d++) cnt[d] = 8'd0;
    for (int a = -r; a <= r; a++)
      for (int b = -r; b <= r; b++)
        if (a * a + b * b <= r * r) cnt[a*a + b*b] = cnt[a*a + b*b] + 8'd1;
    m = 0;
    for (int d = 0; d <= r * r; d++) if (int'(cnt[d]) > m) m = int'(cnt[d]);
    return m;
  endfunction

endpackage
