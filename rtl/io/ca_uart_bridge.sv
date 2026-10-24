// UART to AXI bridge (spec Section 14), little-endian, 8N1:
//   0x10 addr[4] data[4]           register write -> 0x10
//   0x11 addr[4]                   register read  -> 0x11 data[4]
//   0x20 addr[4] len[4] bytes[len] memory write   -> 0x20 after the last response
//   0x21 addr[4] len[4]            memory read    -> 0x21 bytes[len]
// Memory addresses and lengths are multiples of DATA_W/8; every memory
// transfer is a single-beat AXI4 burst. Unknown command bytes are ignored.
module ca_uart_bridge #(
  parameter int unsigned CLK_HZ      = 100_000_000,
  parameter int unsigned BAUD        = 2_000_000,
  parameter int unsigned DATA_W      = 128,
  parameter int unsigned ADDR_W      = 32,
  parameter type         axi_req_t   = logic,
  parameter type         axi_resp_t  = logic,
  parameter type         axil_req_t  = logic,
  parameter type         axil_resp_t = logic
) (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic       rxd_i,
  output logic       txd_o,
  output axi_req_t   m_axi_req_o,
  // Single-beat master: id/resp/last/user response fields are unused.
  /* verilator lint_off UNUSEDSIGNAL */
  input  axi_resp_t  m_axi_resp_i,
  input  axil_resp_t m_axil_resp_i,
  /* verilator lint_on UNUSEDSIGNAL */
  output axil_req_t  m_axil_req_o
);
  localparam int unsigned BYTES = DATA_W / 8;
  localparam int unsigned QB    = BYTES > 5 ? BYTES : 5;   // transmit queue, bytes
  localparam int unsigned BI    = $clog2(QB + 1);

  logic [7:0] rx_data;
  logic       rx_valid, tx_ready, tx_valid;
  logic [7:0] tx_data;
  ca_uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) i_rx (.clk_i, .rst_ni, .rxd_i, .data_o(rx_data), .valid_o(rx_valid));
  ca_uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) i_tx (.clk_i, .rst_ni, .data_i(tx_data), .valid_i(tx_valid),
                                                   .ready_o(tx_ready), .txd_o);

  typedef enum logic [3:0] {
    S_CMD, S_ARG, S_REG_WR, S_REG_WR_B, S_REG_RD, S_REG_RD_R,
    S_MEM_COLLECT, S_MEM_WR, S_MEM_WR_B, S_MEM_AR, S_MEM_R, S_SEND
  } state_e;
  state_e            state, ret;
  logic [7:0]        cmd;
  logic [63:0]       args;
  logic [3:0]        argi;
  logic [ADDR_W-1:0] addr;
  logic [31:0]       len;
  logic [DATA_W-1:0] word;
  logic [BI-1:0]     bidx;
  logic [8*QB-1:0]   txq;
  logic [BI-1:0]     txn;
  logic              aw_done, w_done;

  assign tx_data  = txq[7:0];
  assign tx_valid = state == S_SEND && txn != '0 && tx_ready;

  always_comb begin
    m_axi_req_o          = '0;
    m_axi_req_o.aw.addr  = addr;
    m_axi_req_o.aw.size  = 3'($clog2(BYTES));
    m_axi_req_o.aw.burst = 2'b01;
    m_axi_req_o.aw.cache = 4'b0011;
    m_axi_req_o.aw_valid = state == S_MEM_WR && !aw_done;
    m_axi_req_o.w.data   = word;
    m_axi_req_o.w.strb   = '1;
    m_axi_req_o.w.last   = 1'b1;
    m_axi_req_o.w_valid  = state == S_MEM_WR && !w_done;
    m_axi_req_o.b_ready  = state == S_MEM_WR_B;
    m_axi_req_o.ar.addr  = addr;
    m_axi_req_o.ar.size  = 3'($clog2(BYTES));
    m_axi_req_o.ar.burst = 2'b01;
    m_axi_req_o.ar.cache = 4'b0011;
    m_axi_req_o.ar_valid = state == S_MEM_AR;
    m_axi_req_o.r_ready  = state == S_MEM_R;

    m_axil_req_o          = '0;
    m_axil_req_o.aw.addr  = args[31:0];
    m_axil_req_o.aw_valid = state == S_REG_WR && !aw_done;
    m_axil_req_o.w.data   = args[63:32];
    m_axil_req_o.w.strb   = '1;
    m_axil_req_o.w_valid  = state == S_REG_WR && !w_done;
    m_axil_req_o.b_ready  = state == S_REG_WR_B;
    m_axil_req_o.ar.addr  = args[31:0];
    m_axil_req_o.ar_valid = state == S_REG_RD;
    m_axil_req_o.r_ready  = state == S_REG_RD_R;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state   <= S_CMD;
      ret     <= S_CMD;
      cmd     <= '0;
      args    <= '0;
      argi    <= '0;
      addr    <= '0;
      len     <= '0;
      word    <= '0;
      bidx    <= '0;
      txq     <= '0;
      txn     <= '0;
      aw_done <= 1'b0;
      w_done  <= 1'b0;
    end else begin
      case (state)
        S_CMD: if (rx_valid && (rx_data == 8'h10 || rx_data == 8'h11 || rx_data == 8'h20 || rx_data == 8'h21)) begin
          cmd   <= rx_data;
          argi  <= '0;
          state <= S_ARG;
        end
        S_ARG: if (rx_valid) begin
          args[8*argi +: 8] <= rx_data;
          argi <= argi + 1'b1;
          if (argi == ((cmd == 8'h11) ? 4'd3 : 4'd7)) begin
            aw_done <= 1'b0;
            w_done  <= 1'b0;
            case (cmd)
              8'h10: state <= S_REG_WR;
              8'h11: state <= S_REG_RD;
              8'h20: begin
                addr  <= ADDR_W'(args[31:0]);
                len   <= {rx_data, args[55:32]};
                bidx  <= '0;
                if ({rx_data, args[55:32]} == '0) begin
                  txq <= (8*QB)'(8'h20);
                  txn <= BI'(1);
                  ret <= S_CMD;
                  state <= S_SEND;
                end else begin
                  state <= S_MEM_COLLECT;
                end
              end
              default: begin  // 8'h21
                addr  <= ADDR_W'(args[31:0]);
                len   <= {rx_data, args[55:32]};
                txq   <= (8*QB)'(8'h21);
                txn   <= BI'(1);
                ret   <= ({rx_data, args[55:32]} == '0) ? S_CMD : S_MEM_AR;
                state <= S_SEND;
              end
            endcase
          end
        end
        S_REG_WR: begin
          if (m_axil_resp_i.aw_ready) aw_done <= 1'b1;
          if (m_axil_resp_i.w_ready)  w_done  <= 1'b1;
          if ((aw_done || m_axil_resp_i.aw_ready) && (w_done || m_axil_resp_i.w_ready)) state <= S_REG_WR_B;
        end
        S_REG_WR_B: if (m_axil_resp_i.b_valid) begin
          txq   <= (8*QB)'(8'h10);
          txn   <= BI'(1);
          ret   <= S_CMD;
          state <= S_SEND;
        end
        S_REG_RD: if (m_axil_resp_i.ar_ready) state <= S_REG_RD_R;
        S_REG_RD_R: if (m_axil_resp_i.r_valid) begin
          txq   <= (8*QB)'({m_axil_resp_i.r.data, 8'h11});
          txn   <= BI'(5);
          ret   <= S_CMD;
          state <= S_SEND;
        end
        S_MEM_COLLECT: if (rx_valid) begin
          word[8*bidx +: 8] <= rx_data;
          if (bidx == BI'(BYTES - 1)) begin
            bidx    <= '0;
            aw_done <= 1'b0;
            w_done  <= 1'b0;
            state   <= S_MEM_WR;
          end else begin
            bidx <= bidx + 1'b1;
          end
        end
        S_MEM_WR: begin
          if (m_axi_resp_i.aw_ready) aw_done <= 1'b1;
          if (m_axi_resp_i.w_ready)  w_done  <= 1'b1;
          if ((aw_done || m_axi_resp_i.aw_ready) && (w_done || m_axi_resp_i.w_ready)) state <= S_MEM_WR_B;
        end
        S_MEM_WR_B: if (m_axi_resp_i.b_valid) begin
          addr <= addr + ADDR_W'(BYTES);
          len  <= len - 32'(BYTES);
          if (len == 32'(BYTES)) begin
            txq   <= (8*QB)'(8'h20);
            txn   <= BI'(1);
            ret   <= S_CMD;
            state <= S_SEND;
          end else begin
            state <= S_MEM_COLLECT;
          end
        end
        S_MEM_AR: if (m_axi_resp_i.ar_ready) state <= S_MEM_R;
        S_MEM_R: if (m_axi_resp_i.r_valid) begin
          txq   <= (8*QB)'(m_axi_resp_i.r.data);
          txn   <= BI'(BYTES);
          addr  <= addr + ADDR_W'(BYTES);
          len   <= len - 32'(BYTES);
          ret   <= (len == 32'(BYTES)) ? S_CMD : S_MEM_AR;
          state <= S_SEND;
        end
        default: begin  // S_SEND
          if (txn == '0) begin
            state <= ret;
          end else if (tx_ready) begin
            txq <= txq >> 8;
            txn <= txn - 1'b1;
          end
        end
      endcase
    end
  end
endmodule
