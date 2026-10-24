// UART receiver, 8 data bits, no parity, 1 stop bit, sampled mid-bit.
module ca_uart_rx #(
  parameter int unsigned CLK_HZ = 100_000_000,
  parameter int unsigned BAUD   = 2_000_000
) (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic       rxd_i,
  output logic [7:0] data_o,
  output logic       valid_o
);
  localparam int unsigned DIV = CLK_HZ / BAUD;
  localparam int unsigned DW  = $clog2(DIV + 1);

  logic          rxd;
  logic [DW-1:0] cnt;
  logic [3:0]    bit_idx;
  logic          busy;

  ca_sync #(.W(1)) i_sync (.clk_i, .d_i(rxd_i), .q_o(rxd));

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      busy    <= 1'b0;
      cnt     <= '0;
      bit_idx <= '0;
      data_o  <= '0;
      valid_o <= 1'b0;
    end else begin
      valid_o <= 1'b0;
      if (!busy) begin
        if (!rxd) begin                       // start bit
          busy    <= 1'b1;
          cnt     <= DW'(DIV / 2);
          bit_idx <= '0;
        end
      end else if (cnt != '0) begin
        cnt <= cnt - 1'b1;
      end else begin
        cnt <= DW'(DIV - 1);
        if (bit_idx == 4'd0) begin            // middle of the start bit
          if (rxd) busy <= 1'b0;              // glitch, not a start bit
        end else if (bit_idx <= 4'd8) begin
          data_o <= {rxd, data_o[7:1]};
        end else begin                        // stop bit
          busy    <= 1'b0;
          valid_o <= rxd;
        end
        bit_idx <= bit_idx + 1'b1;
      end
    end
  end
endmodule
