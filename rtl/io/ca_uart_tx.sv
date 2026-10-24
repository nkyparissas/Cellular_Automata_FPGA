// UART transmitter, 8 data bits, no parity, 1 stop bit.
module ca_uart_tx #(
  parameter int unsigned CLK_HZ = 100_000_000,
  parameter int unsigned BAUD   = 2_000_000
) (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic [7:0] data_i,
  input  logic       valid_i,
  output logic       ready_o,
  output logic       txd_o
);
  localparam int unsigned DIV = CLK_HZ / BAUD;
  localparam int unsigned DW  = $clog2(DIV + 1);

  logic [9:0]    shreg;
  logic [3:0]    left;
  logic [DW-1:0] cnt;

  // Ready only once the stop bit has lasted a full bit period.
  assign ready_o = left == '0 && cnt == '0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      shreg <= '1;
      left  <= '0;
      cnt   <= '0;
      txd_o <= 1'b1;
    end else if (cnt != '0) begin
      cnt <= cnt - 1'b1;
    end else if (left != '0) begin
      txd_o <= shreg[0];
      shreg <= {1'b1, shreg[9:1]};
      left  <= left - 1'b1;
      cnt   <= DW'(DIV - 1);
    end else if (valid_i) begin
      shreg <= {1'b1, data_i, 1'b0};
      left  <= 4'd10;
    end
  end
endmodule
