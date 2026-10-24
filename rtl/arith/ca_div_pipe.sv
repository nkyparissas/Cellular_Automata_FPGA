// Pipelined unsigned restoring divider, one quotient bit per stage
// (latency NUM_W). A zero divisor yields an all-ones quotient.
module ca_div_pipe #(
  parameter int unsigned NUM_W = 18,
  parameter int unsigned DEN_W = 10
) (
  input  logic             clk_i,
  input  logic [NUM_W-1:0] num_i,
  input  logic [DEN_W-1:0] den_i,
  output logic [NUM_W-1:0] quo_o
);
  logic [NUM_W-1:0] num [NUM_W+1];
  logic [DEN_W-1:0] den [NUM_W+1];
  logic [DEN_W-1:0] rem [NUM_W+1];
  logic [NUM_W-1:0] quo [NUM_W+1];

  assign num[0] = num_i;
  assign den[0] = den_i;
  assign rem[0] = '0;
  assign quo[0] = '0;

  for (genvar k = 0; k < NUM_W; k++) begin : g_stage
    logic [DEN_W:0] trial;
    logic           take;
    assign trial = {rem[k], num[k][NUM_W-1-k]};
    assign take  = trial >= {1'b0, den[k]};
    always_ff @(posedge clk_i) begin
      num[k+1] <= num[k];
      den[k+1] <= den[k];
      rem[k+1] <= take ? DEN_W'(trial - {1'b0, den[k]}) : DEN_W'(trial);
      quo[k+1] <= {quo[k][NUM_W-2:0], take};
    end
  end

  assign quo_o = quo[NUM_W];
endmodule
