// Lenia rule (Lenia design spec, Section 6.1; docs/figures/lenia_engine.png).
// For every window, with class(i, j) the rank of i^2 + j^2 among the distinct
// values <= R^2 (model/ca_model/lenia.py class_map):
//   S   = sum over classes c of w[c] * (sum of the cells of class c)
//   idx = min(S >> SH, 2^LUT_IDX_W - 1)
//   q'  = clamp(q_centre + table[bank][idx], 0, 2^CELL_W - 1)
// Every stage is registered for the 200 MHz engine clock: a register stage
// after the window, per-class pre-add trees (latencies equalised), multipliers
// with input, product and output registers, an adder tree over the products,
// a two-step shift and a saturation stage, the table RAM with an output
// register, and the update. The class weights form a shift chain loaded while
// the core is idle (kern_valid_i shifts once: w[c] <= w[c+1], w[C-1] <= data),
// so each weight register sits next to its multiplier and is static during
// passes. sel_i (active bank and SH) is static during a pass.
module ca_rule_lenia #(
  parameter int unsigned N           = 27,
  parameter int unsigned CELL_W      = 16,
  parameter int unsigned WEIGHT_W    = 6,
  parameter int unsigned LUT_IDX_W   = 12,
  parameter logic [ca_pkg::lenia_classes(N)*WEIGHT_W-1:0] KERNEL_DEFAULT = '0,
  parameter string       GROWTH_INIT = ""
) (
  input  logic                            clk_i,
  input  logic                            rst_ni,
  input  logic [N-1:0][N-1:0][CELL_W-1:0] win_i,
  input  logic                            vld_i,
  input  logic                            kern_valid_i,
  input  logic [WEIGHT_W-1:0]             kern_data_i,
  input  logic                            gt_clk_i,
  input  logic                            gt_we_i,
  input  logic [LUT_IDX_W:0]              gt_addr_i,
  input  logic [CELL_W:0]                 gt_data_i,
  input  ca_pkg::lenia_sel_t              sel_i,
  output logic [CELL_W-1:0]               cell_o,
  output logic                            vld_o
);
  localparam int unsigned C       = ca_pkg::lenia_classes(N);
  localparam int unsigned R       = (N - 1) / 2;
  localparam int unsigned MAXK    = ca_pkg::lenia_max_cells(N);
  localparam int unsigned PW      = CELL_W + $clog2(MAXK);     // class sum
  localparam int unsigned MW      = PW + WEIGHT_W;             // product
  localparam int unsigned SW      = MW + $clog2(C);            // S
  localparam int unsigned EW      = CELL_W + 1;                // table entry
  localparam int unsigned PRE_LAT = ca_pkg::tree_lat(MAXK);
  localparam int unsigned MUL_LAT = 3;
  localparam int unsigned SUM_LAT = ca_pkg::tree_lat(C);
  localparam int unsigned IDX_LAT = 3;
  localparam int unsigned TAB_LAT = 2;
  localparam int unsigned LAT     = 1 + PRE_LAT + MUL_LAT + SUM_LAT + IDX_LAT + TAB_LAT + 1;

  // ----------------------------------------------------------- class map
  // Built in single passes (an elaboration-time function that rescans the map
  // per class member costs Verilator gigabytes at N = 27).
  localparam int unsigned NN = N * N;
  localparam int unsigned D2 = R * R;
  localparam int unsigned CI = $clog2(C);       // class index width (C >= 2)
  localparam int unsigned NI = $clog2(NN);      // window cell index width
  typedef logic [NN-1:0][7:0]  cmap_t;    // class of window cell i*N+j, 8'hFF outside the disk
  typedef logic [C:0][15:0]    offs_t;    // first position of each class in ORDER; [C] = cells
  typedef logic [NN-1:0][15:0] order_t;   // disk cells sorted by class

  // Evaluated at elaboration only, which the lint tool reports as unused locals
  // and, for some loop indices, as undriven bits.
  /* verilator lint_off UNUSEDSIGNAL */
  /* verilator lint_off UNDRIVEN */
  function automatic cmap_t cmap_build();
    cmap_t            m;
    logic [D2:0]      seen;
    logic [D2:0][7:0] rank;
    logic [7:0]       acc;
    int               d;
    seen = '0;
    for (int a = 0; a <= int'(R); a++)
      for (int b = 0; b <= int'(R); b++)
        if (a * a + b * b <= int'(D2)) seen[a*a + b*b] = 1'b1;
    acc = '0;
    for (int v = 0; v <= int'(D2); v++) begin
      rank[v] = acc;
      acc     = acc + 8'(seen[v]);
    end
    for (int i = 0; i < int'(N); i++) begin
      for (int j = 0; j < int'(N); j++) begin
        d = (i - int'(R)) * (i - int'(R)) + (j - int'(R)) * (j - int'(R));
        m[i*int'(N) + j] = (d > int'(D2)) ? 8'hFF : rank[d];
      end
    end
    return m;
  endfunction

  localparam cmap_t CMAP = cmap_build();

  function automatic offs_t offs_build();
    offs_t             o;
    logic [C-1:0][15:0] cnt;
    for (int c = 0; c < int'(C); c++) cnt[c] = '0;
    for (int p = 0; p < int'(NN); p++)
      if (CMAP[p] != 8'hFF) cnt[CI'(CMAP[p])] = cnt[CI'(CMAP[p])] + 16'd1;
    o[0] = '0;
    for (int c = 0; c < int'(C); c++) o[c+1] = o[c] + cnt[c];
    return o;
  endfunction

  localparam offs_t OFFS = offs_build();

  function automatic order_t order_build();
    order_t             ord;
    logic [C-1:0][15:0] fill;
    for (int p = 0; p < int'(NN); p++) ord[p] = '0;
    for (int c = 0; c < int'(C); c++) fill[c] = OFFS[c];
    for (int p = 0; p < int'(NN); p++) begin
      if (CMAP[p] != 8'hFF) begin
        ord[NI'(fill[CI'(CMAP[p])])] = 16'(p);
        fill[CI'(CMAP[p])]           = fill[CI'(CMAP[p])] + 16'd1;
      end
    end
    return ord;
  endfunction
  /* verilator lint_on UNDRIVEN */
  /* verilator lint_on UNUSEDSIGNAL */

  localparam order_t ORDER = order_build();

  // --------------------------------------------- register stage, pre-add
  // Corner cells outside the disk feed no class.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [N-1:0][N-1:0][CELL_W-1:0] win_q;
  /* verilator lint_on UNUSEDSIGNAL */
  always_ff @(posedge clk_i) win_q <= win_i;

  logic [C-1:0][PW-1:0] csum;
  for (genvar c = 0; c < C; c++) begin : g_cls
    localparam int unsigned K = int'(OFFS[c+1]) - int'(OFFS[c]);
    logic [K-1:0][CELL_W-1:0] members;
    logic [PW-1:0]            s;
    for (genvar k = 0; k < K; k++) begin : g_m
      localparam int unsigned P = int'(ORDER[int'(OFFS[c]) + k]);
      assign members[k] = win_q[P / N][P % N];
    end
    if (K == 1) begin : g_single
      assign s = PW'(members[0]);
    end else begin : g_tree
      ca_adder_tree #(.N_IN(K), .IN_W(CELL_W), .OUT_W(PW)) i_tree (.clk_i, .in_i(members), .sum_o(s));
    end
    if (ca_pkg::tree_lat(K) == PRE_LAT) begin : g_aligned
      assign csum[c] = s;
    end else begin : g_eq
      ca_delay #(.W(PW), .D(PRE_LAT - ca_pkg::tree_lat(K))) i_eq (.clk_i, .d_i(s), .q_o(csum[c]));
    end
  end

  // -------------------------------------------- weight chain, multipliers
  logic [C-1:0][WEIGHT_W-1:0] w;
  initial w = KERNEL_DEFAULT;
  always_ff @(posedge clk_i) begin
    if (rst_ni && kern_valid_i) begin   // no shift in reset (the chain itself is not reset)
      for (int unsigned c = 0; c + 1 < C; c++) w[c] <= w[c+1];
      w[C-1] <= kern_data_i;
    end
  end

  logic [C-1:0][MW-1:0] prod;
  for (genvar c = 0; c < C; c++) begin : g_mul
    logic [PW-1:0]       a_q;
    logic [WEIGHT_W-1:0] b_q;
    logic [MW-1:0]       p_q;
    always_ff @(posedge clk_i) begin
      a_q     <= csum[c];
      b_q     <= w[c];
      p_q     <= a_q * b_q;
      prod[c] <= p_q;
    end
  end

  logic [SW-1:0] s_sum;
  ca_adder_tree #(.N_IN(C), .IN_W(MW), .OUT_W(SW)) i_sum (.clk_i, .in_i(prod), .sum_o(s_sum));

  // ------------------------------------------------ index: shift, saturate
  logic [SW-1:0]        s_hi, s_lo;
  logic [LUT_IDX_W-1:0] idx;
  always_ff @(posedge clk_i) begin
    s_hi <= s_sum >> {sel_i.sh[5:3], 3'b000};
    s_lo <= s_hi >> sel_i.sh[2:0];
    idx  <= (s_lo >> LUT_IDX_W) != '0 ? '1 : s_lo[LUT_IDX_W-1:0];
  end

  // ------------------------------------------------------ table, update
  logic [EW-1:0] e_ram, e_q;
  ca_ram_sdp_asym #(.WR_W(EW), .RD_W(EW), .RD_DEPTH(1 << (LUT_IDX_W + 1)), .INIT_FILE(GROWTH_INIT)) i_table (
    .wclk_i(gt_clk_i), .we_i(gt_we_i), .waddr_i(gt_addr_i), .wdata_i(gt_data_i),
    .rclk_i(clk_i), .raddr_i({sel_i.bank, idx}), .rdata_o(e_ram));
  always_ff @(posedge clk_i) e_q <= e_ram;

  logic [CELL_W-1:0] c_d;
  ca_delay #(.W(CELL_W), .D(LAT - 1)) i_centre (.clk_i, .d_i(win_i[R][R]), .q_o(c_d));
  ca_valid_delay #(.D(LAT)) i_vld (.clk_i, .rst_ni, .d_i(vld_i), .q_o(vld_o));

  logic signed [EW:0] next;
  assign next = $signed({2'b00, c_d}) + $signed({e_q[EW-1], e_q});
  always_ff @(posedge clk_i) begin
    if (next < 0)                                   cell_o <= '0;
    else if (next > $signed({2'b00, {CELL_W{1'b1}}})) cell_o <= '1;
    else                                            cell_o <= CELL_W'(next);
  end
endmodule
