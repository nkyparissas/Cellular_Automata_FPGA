// Push buttons to register writes (display boards): synchronised and
// debounced; up sets FRAME_REPEAT = 0 (one generation per displayed frame),
// down sets FRAME_REPEAT = SLOW_REPEAT, pause toggles CTRL.PAUSE.
module ca_buttons_axil
  import ca_regs_pkg::*;
#(
  parameter int unsigned CLK_HZ      = 100_000_000,
  parameter int unsigned DEBOUNCE_MS = 20,
  parameter int unsigned SLOW_REPEAT = 59,
  parameter type         axil_req_t  = logic,
  parameter type         axil_resp_t = logic
) (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic       btn_up_i,
  input  logic       btn_down_i,
  input  logic       btn_pause_i,
  output axil_req_t  m_axil_req_o,
  // Only the handshakes and the read data are used.
  /* verilator lint_off UNUSEDSIGNAL */
  input  axil_resp_t m_axil_resp_i
  /* verilator lint_on UNUSEDSIGNAL */
);
  localparam int unsigned DEB = (CLK_HZ / 1000) * DEBOUNCE_MS;
  localparam int unsigned DW  = $clog2(DEB + 1);

  logic [2:0] raw, stable, stable_q;
  logic [2:0] evt;                // pending press events: {pause, down, up}
  ca_sync #(.W(3)) i_sync (.clk_i, .d_i({btn_pause_i, btn_down_i, btn_up_i}), .q_o(raw));

  for (genvar b = 0; b < 3; b++) begin : g_deb
    logic [DW-1:0] cnt;
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        cnt       <= '0;
        stable[b] <= 1'b0;
      end else if (raw[b] == stable[b]) begin
        cnt <= '0;
      end else if (cnt == DW'(DEB)) begin
        stable[b] <= raw[b];
        cnt       <= '0;
      end else begin
        cnt <= cnt + 1'b1;
      end
    end
  end

  typedef enum logic [2:0] {S_IDLE, S_RD, S_RD_R, S_WR, S_WR_B} state_e;
  state_e      state;
  logic [7:0]  waddr;
  logic [31:0] wdata;
  logic        aw_done, w_done;

  always_comb begin
    m_axil_req_o          = '0;
    m_axil_req_o.aw.addr  = {24'h0, waddr};
    m_axil_req_o.aw_valid = state == S_WR && !aw_done;
    m_axil_req_o.w.data   = wdata;
    m_axil_req_o.w.strb   = '1;
    m_axil_req_o.w_valid  = state == S_WR && !w_done;
    m_axil_req_o.b_ready  = state == S_WR_B;
    m_axil_req_o.ar.addr  = {24'h0, REG_CTRL};
    m_axil_req_o.ar_valid = state == S_RD;
    m_axil_req_o.r_ready  = state == S_RD_R;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      stable_q <= '0;
      evt      <= '0;
      state    <= S_IDLE;
      waddr    <= '0;
      wdata    <= '0;
      aw_done  <= 1'b0;
      w_done   <= 1'b0;
    end else begin
      stable_q <= stable;
      evt      <= evt | (stable & ~stable_q);
      case (state)
        S_IDLE: begin
          aw_done <= 1'b0;
          w_done  <= 1'b0;
          if (evt[0]) begin
            evt[0] <= 1'b0;
            waddr  <= REG_FRAME_REPEAT;
            wdata  <= 32'd0;
            state  <= S_WR;
          end else if (evt[1]) begin
            evt[1] <= 1'b0;
            waddr  <= REG_FRAME_REPEAT;
            wdata  <= 32'(SLOW_REPEAT);
            state  <= S_WR;
          end else if (evt[2]) begin
            evt[2] <= 1'b0;
            state  <= S_RD;
          end
        end
        S_RD: if (m_axil_resp_i.ar_ready) state <= S_RD_R;
        S_RD_R: if (m_axil_resp_i.r_valid) begin
          waddr <= REG_CTRL;
          wdata <= (m_axil_resp_i.r.data ^ (32'(1) << CTRL_PAUSE)) & ~(32'(1) << CTRL_RESET_STATE);
          state <= S_WR;
        end
        S_WR: begin
          if (m_axil_resp_i.aw_ready) aw_done <= 1'b1;
          if (m_axil_resp_i.w_ready)  w_done  <= 1'b1;
          if ((aw_done || m_axil_resp_i.aw_ready) && (w_done || m_axil_resp_i.w_ready)) state <= S_WR_B;
        end
        default: if (m_axil_resp_i.b_valid) state <= S_IDLE;   // S_WR_B
      endcase
    end
  end
endmodule
