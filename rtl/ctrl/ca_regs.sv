// AXI4-Lite register file (spec Section 10). Only the low 8 address bits are
// decoded; unmapped reads return 0 and every access responds OKAY.
module ca_regs
  import ca_regs_pkg::*;
#(
  parameter int unsigned        GRID_X               = 64,
  parameter int unsigned        GRID_Y               = 24,
  parameter int unsigned        CELL_W               = 8,
  parameter int unsigned        NBH                  = 5,
  parameter ca_pkg::boundary_e  BND                  = ca_pkg::BND_TOROIDAL,
  parameter ca_pkg::rule_e      RULE                 = ca_pkg::RULE_HODGEPODGE,
  parameter int unsigned        DATA_W               = 128,
  parameter int unsigned        ADDR_W               = 32,
  parameter logic [63:0]        BUF0_DEFAULT         = 64'h0,
  parameter logic [63:0]        BUF1_DEFAULT         = 64'h0100_0000,
  parameter int unsigned        FRAME_REPEAT_DEFAULT = 0,
  parameter ca_pkg::rule_params_t PARAM_DEFAULTS     = '0,
  parameter type                axil_req_t           = logic,
  parameter type                axil_resp_t          = logic
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  input  axil_req_t            axil_req_i,
  output axil_resp_t           axil_resp_o,
  output logic                 run_o,
  output logic                 pause_o,
  output logic                 auto_o,
  output logic                 reset_state_o,
  output logic                 frame_req_o,
  output logic [15:0]          frame_repeat_o,
  output logic [15:0]          gens_per_frame_o,
  output logic [ADDR_W-1:0]    buf0_addr_o,
  output logic [ADDR_W-1:0]    buf1_addr_o,
  output ca_pkg::rule_params_t rule_params_o,
  input  logic                 busy_i,
  input  logic                 front_i,
  input  logic                 pending_i,
  input  logic [31:0]          gen_count_i,
  input  logic [31:0]          pass_count_i
);
  logic [63:0] buf0_q, buf1_q;
  logic        wr_go, rd_go;
  logic [7:0]  waddr, raddr;
  logic [31:0] wdata, rdata;
  logic [3:0]  wstrb;

  assign buf0_addr_o = ADDR_W'(buf0_q);
  assign buf1_addr_o = ADDR_W'(buf1_q);

  // A write is taken when address and data are both present and no response
  // is pending; AW and W are acknowledged together.
  assign wr_go = axil_req_i.aw_valid && axil_req_i.w_valid && !axil_resp_o.b_valid;
  assign rd_go = axil_req_i.ar_valid && !axil_resp_o.r_valid;
  assign waddr = axil_req_i.aw.addr[7:0];
  assign raddr = axil_req_i.ar.addr[7:0];
  assign wdata = axil_req_i.w.data;
  assign wstrb = axil_req_i.w.strb;

  // Byte-enable mask from WSTRB; a register update is (old & ~wmask) | (wdata & wmask).
  logic [31:0] wmask;
  assign wmask = {{8{wstrb[3]}}, {8{wstrb[2]}}, {8{wstrb[1]}}, {8{wstrb[0]}}};

  always_comb begin
    rdata = '0;
    unique case (raddr)
      REG_ID:             rdata = CA_ID;
      REG_CTRL:           rdata = 32'({auto_o, pause_o, run_o});
      REG_STATUS:         rdata = 32'({pending_i, front_i, busy_i});
      REG_FRAME_REPEAT:   rdata = 32'(frame_repeat_o);
      REG_GENS_PER_FRAME: rdata = 32'(gens_per_frame_o);
      REG_GEN_COUNT:      rdata = gen_count_i;
      REG_PASS_COUNT:     rdata = pass_count_i;
      REG_BUF0_LO:        rdata = buf0_q[31:0];
      REG_BUF0_HI:        rdata = buf0_q[63:32];
      REG_BUF1_LO:        rdata = buf1_q[31:0];
      REG_BUF1_HI:        rdata = buf1_q[63:32];
      REG_GRID_DIM:       rdata = {16'(GRID_Y), 16'(GRID_X)};
      REG_CORE_CFG:       rdata = {8'(DATA_W / 8), 4'(RULE), 2'b0, 2'(BND), 8'(NBH), 8'(CELL_W)};
      default: begin
        if (raddr >= REG_RULE_PARAM0 && raddr < REG_RULE_PARAM0 + 8'(4 * ca_pkg::NUM_RULE_PARAMS))
          rdata = rule_params_o[3'((raddr - REG_RULE_PARAM0) >> 2)];
      end
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      axil_resp_o      <= '0;
      run_o            <= 1'b0;
      pause_o          <= 1'b0;
      auto_o           <= 1'b0;
      reset_state_o    <= 1'b0;
      frame_req_o      <= 1'b0;
      frame_repeat_o   <= 16'(FRAME_REPEAT_DEFAULT);
      gens_per_frame_o <= 16'd1;
      buf0_q           <= BUF0_DEFAULT;
      buf1_q           <= BUF1_DEFAULT;
      rule_params_o    <= PARAM_DEFAULTS;
    end else begin
      reset_state_o        <= 1'b0;
      frame_req_o          <= 1'b0;
      axil_resp_o.aw_ready <= 1'b0;
      axil_resp_o.w_ready  <= 1'b0;
      axil_resp_o.ar_ready <= 1'b0;
      // Write channel: acknowledge AW/W in the cycle after both are seen.
      if (wr_go && !axil_resp_o.aw_ready) begin
        axil_resp_o.aw_ready <= 1'b1;
        axil_resp_o.w_ready  <= 1'b1;
        axil_resp_o.b_valid  <= 1'b1;
        axil_resp_o.b.resp   <= '0;
        unique case (waddr)
          REG_CTRL: begin
            if (wstrb[0]) begin
              run_o         <= wdata[CTRL_RUN];
              pause_o       <= wdata[CTRL_PAUSE];
              auto_o        <= wdata[CTRL_AUTO];
              reset_state_o <= wdata[CTRL_RESET_STATE];
            end
          end
          REG_FRAME_REQ:      frame_req_o      <= 1'b1;
          REG_FRAME_REPEAT:   frame_repeat_o   <= 16'(((32'(frame_repeat_o)) & ~wmask) | (wdata & wmask));
          REG_GENS_PER_FRAME: gens_per_frame_o <= 16'(((32'(gens_per_frame_o)) & ~wmask) | (wdata & wmask));
          REG_BUF0_LO:        buf0_q[31:0]     <= ((buf0_q[31:0]) & ~wmask) | (wdata & wmask);
          REG_BUF0_HI:        buf0_q[63:32]    <= ((buf0_q[63:32]) & ~wmask) | (wdata & wmask);
          REG_BUF1_LO:        buf1_q[31:0]     <= ((buf1_q[31:0]) & ~wmask) | (wdata & wmask);
          REG_BUF1_HI:        buf1_q[63:32]    <= ((buf1_q[63:32]) & ~wmask) | (wdata & wmask);
          default: begin
            if (waddr >= REG_RULE_PARAM0 && waddr < REG_RULE_PARAM0 + 8'(4 * ca_pkg::NUM_RULE_PARAMS))
              rule_params_o[3'((waddr - REG_RULE_PARAM0) >> 2)] <=
                ((rule_params_o[3'((waddr - REG_RULE_PARAM0) >> 2)]) & ~wmask) | (wdata & wmask);
          end
        endcase
      end
      if (axil_resp_o.b_valid && axil_req_i.b_ready) axil_resp_o.b_valid <= 1'b0;
      // Read channel.
      if (rd_go && !axil_resp_o.ar_ready) begin
        axil_resp_o.ar_ready <= 1'b1;
        axil_resp_o.r_valid  <= 1'b1;
        axil_resp_o.r.data   <= rdata;
        axil_resp_o.r.resp   <= '0;
      end
      if (axil_resp_o.r_valid && axil_req_i.r_ready) axil_resp_o.r_valid <= 1'b0;
    end
  end
endmodule
