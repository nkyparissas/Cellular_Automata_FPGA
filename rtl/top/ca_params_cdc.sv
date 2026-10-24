// Moves the rule parameters into the engine clock domain. They are captured
// at pass start and copied on the toggle of a synchronised flag; passes do
// not overlap, so the values are stable long before the engine uses them.
module ca_params_cdc (
  input  logic                 aclk_i,
  input  logic                 arst_ni,
  input  logic                 capture_i,
  input  ca_pkg::rule_params_t params_i,
  input  logic                 eclk_i,
  input  logic                 erst_ni,
  output ca_pkg::rule_params_t params_o
);
  ca_pkg::rule_params_t hold;
  logic                 tog_a, tog_e, tog_e_q;

  always_ff @(posedge aclk_i or negedge arst_ni) begin
    if (!arst_ni) begin
      hold  <= '0;
      tog_a <= 1'b0;
    end else if (capture_i) begin
      hold  <= params_i;
      tog_a <= !tog_a;
    end
  end

  ca_sync #(.W(1)) i_sync (.clk_i(eclk_i), .d_i(tog_a), .q_o(tog_e));

  always_ff @(posedge eclk_i or negedge erst_ni) begin
    if (!erst_ni) begin
      tog_e_q  <= 1'b0;
      params_o <= '0;
    end else begin
      tog_e_q <= tog_e;
      if (tog_e != tog_e_q) params_o <= hold;
    end
  end
endmodule
