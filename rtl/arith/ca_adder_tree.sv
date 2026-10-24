// Pipelined binary adder tree: one register per level, latency
// ca_pkg::tree_lat(N_IN) (0 for a single input). Unsigned.
module ca_adder_tree #(
  parameter int unsigned N_IN  = 8,
  parameter int unsigned IN_W  = 8,
  parameter int unsigned OUT_W = 11
) (
  input  logic                      clk_i,
  input  logic [N_IN-1:0][IN_W-1:0] in_i,
  output logic [OUT_W-1:0]          sum_o
);
  localparam int unsigned LAT = ca_pkg::tree_lat(N_IN);

  // Number of partial sums after l levels. Used at elaboration time only,
  // so the lint tool reports the argument as unused.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic int unsigned cnt(int unsigned l);
    return (N_IN + (1 << l) - 1) >> l;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  for (genvar l = 0; l <= LAT; l++) begin : g_lvl
    logic [OUT_W-1:0] v [cnt(l)];
    if (l == 0) begin : g_in
      for (genvar i = 0; i < N_IN; i++) begin : g_i
        assign v[i] = OUT_W'(in_i[i]);
      end
    end else begin : g_add
      for (genvar i = 0; i < cnt(l); i++) begin : g_i
        if (2 * i + 1 < cnt(l - 1)) begin : g_pair
          always_ff @(posedge clk_i) v[i] <= g_lvl[l-1].v[2*i] + g_lvl[l-1].v[2*i+1];
        end else begin : g_pass
          always_ff @(posedge clk_i) v[i] <= g_lvl[l-1].v[2*i];
        end
      end
    end
  end

  assign sum_o = g_lvl[LAT].v[0];
endmodule
