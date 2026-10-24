// Register file + controller testbench. Reader/writer stand-ins finish each
// pass after random delays; named cases are selected with +case=<name>.
`timescale 1ns/1ps
`include "axi/typedef.svh"
module tb_ctrl;
  import ca_regs_pkg::*;
  typedef logic [31:0] addr_t;
  typedef logic [31:0] data_t;
  typedef logic [3:0]  strb_t;
  `AXI_LITE_TYPEDEF_ALL(axil, addr_t, data_t, strb_t)

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  axil_req_t  lreq;
  axil_resp_t lresp;
  axil_bfm #(.axil_req_t(axil_req_t), .axil_resp_t(axil_resp_t)) bfm (.clk_i(clk), .req_o(lreq), .resp_i(lresp));

  logic        run, pause, auto_, reset_state, frame_req, busy, front, pending, pass_start, fwd, commit;
  logic        rd_done = 0, wr_done = 0, pass_done;
  logic [15:0] frame_repeat, gpf;
  logic [31:0] buf0, buf1, gen_count, pass_count;
  ca_pkg::rule_params_t params;

  ca_regs #(.GRID_X(1920), .GRID_Y(1080), .CELL_W(8), .NBH(29), .BND(ca_pkg::BND_CYLINDRICAL),
            .RULE(ca_pkg::RULE_GHM), .DATA_W(128), .ADDR_W(32), .BUF0_DEFAULT(64'h1000),
            .BUF1_DEFAULT(64'h0020_0000), .FRAME_REPEAT_DEFAULT(59),
            .axil_req_t(axil_req_t), .axil_resp_t(axil_resp_t)) i_regs (
    .clk_i(clk), .rst_ni(rst_n), .axil_req_i(lreq), .axil_resp_o(lresp), .run_o(run), .pause_o(pause),
    .auto_o(auto_), .reset_state_o(reset_state), .frame_req_o(frame_req), .frame_repeat_o(frame_repeat),
    .gens_per_frame_o(gpf), .buf0_addr_o(buf0), .buf1_addr_o(buf1), .rule_params_o(params),
    .busy_i(busy), .front_i(front), .pending_i(pending), .gen_count_i(gen_count), .pass_count_i(pass_count));

  ca_controller i_ctrl (
    .clk_i(clk), .rst_ni(rst_n), .run_i(run), .pause_i(pause), .auto_i(auto_), .reset_state_i(reset_state),
    .req_i(frame_req), .frame_repeat_i(frame_repeat), .gens_per_frame_i(gpf), .pass_start_o(pass_start),
    .rd_fwd_en_o(fwd), .wr_commit_o(commit), .rd_done_i(rd_done), .wr_done_i(wr_done), .front_o(front),
    .busy_o(busy), .pending_o(pending), .gen_count_o(gen_count), .pass_count_o(pass_count),
    .pass_done_o(pass_done));

  // Reader/writer stand-ins and a log of every pass.
  int unsigned rd_t = 0, wr_t = 0, passes = 0;
  bit          log_fwd[$], log_commit[$];
  always_ff @(posedge clk) begin
    rd_done <= 1'b0;
    wr_done <= 1'b0;
    if (rst_n && pass_start) begin
      rd_t <= $urandom_range(20, 120);
      wr_t <= $urandom_range(20, 160);
    end else begin
      if (rd_t == 1) rd_done <= 1'b1;
      if (wr_t == 1) wr_done <= 1'b1;
      if (rd_t != 0) rd_t <= rd_t - 1;
      if (wr_t != 0) wr_t <= wr_t - 1;
    end
    if (rst_n && pass_done) begin
      passes++;
      log_fwd.push_back(fwd);
      log_commit.push_back(commit);
    end
  end

  task automatic rd(input logic [7:0] a, output logic [31:0] d);
    bfm.read({24'h0, a}, d);
  endtask
  task automatic wr(input logic [7:0] a, input logic [31:0] d);
    bfm.write({24'h0, a}, d);
  endtask
  task automatic expect_reg(input logic [7:0] a, input logic [31:0] e, input string what);
    logic [31:0] d;
    rd(a, d);
    if (d !== e) $fatal(1, "%s: reg 0x%0h = 0x%0h, expected 0x%0h", what, a, d, e);
  endtask
  task automatic wait_idle();
    logic [31:0] st;
    do rd(REG_STATUS, st); while (st[ST_BUSY] || st[ST_PENDING]);
  endtask
  task automatic wait_cycles(int n);
    repeat (n) @(negedge clk);
  endtask

  string tc;
  initial begin
    logic [31:0] d;
    if (!$value$plusargs("case=%s", tc)) $fatal(1, "+case missing");
    repeat (3) @(posedge clk);
    rst_n = 1;
    case (tc)
      "regs_rw": begin
        expect_reg(REG_ID, CA_ID, "id");
        expect_reg(REG_FRAME_REPEAT, 59, "frame repeat reset value");
        expect_reg(REG_GENS_PER_FRAME, 1, "gpf reset value");
        expect_reg(REG_BUF0_LO, 32'h1000, "buf0 reset");
        expect_reg(REG_BUF1_LO, 32'h0020_0000, "buf1 reset");
        expect_reg(REG_GRID_DIM, {16'd1080, 16'd1920}, "grid dim");
        expect_reg(REG_CORE_CFG, {8'd16, 4'd1, 2'b0, 2'd1, 8'd29, 8'd8}, "core cfg");
        wr(REG_CTRL, 32'h6);            expect_reg(REG_CTRL, 32'h6, "ctrl");
        wr(REG_CTRL, 32'h0);
        wr(REG_FRAME_REPEAT, 32'h1234); expect_reg(REG_FRAME_REPEAT, 32'h1234, "frame repeat");
        wr(REG_GENS_PER_FRAME, 7);      expect_reg(REG_GENS_PER_FRAME, 7, "gpf");
        wr(REG_BUF0_LO, 32'hDEAD_BEE0); expect_reg(REG_BUF0_LO, 32'hDEAD_BEE0, "buf0 lo");
        wr(REG_BUF0_HI, 32'h0000_0012); expect_reg(REG_BUF0_HI, 32'h12, "buf0 hi");
        wr(REG_BUF1_LO, 32'h0040_0000); expect_reg(REG_BUF1_LO, 32'h0040_0000, "buf1 lo");
        for (int k = 0; k < 8; k++) wr(REG_RULE_PARAM0 + 8'(4 * k), 32'h100 + k);
        for (int k = 0; k < 8; k++) expect_reg(REG_RULE_PARAM0 + 8'(4 * k), 32'h100 + k, "rule param");
        if (params[3] != 32'h103) $fatal(1, "rule_params_o not updated");
        if (buf0 != 32'hDEAD_BEE0) $fatal(1, "buf0_addr_o not updated");
        wr(REG_GEN_COUNT, 32'h55);      expect_reg(REG_GEN_COUNT, 0, "gen count is read-only");
        wr(REG_ID, 0);                  expect_reg(REG_ID, CA_ID, "id is read-only");
        expect_reg(8'h3C, 0, "unmapped");
        expect_reg(8'hFC, 0, "unmapped");
      end
      "repeat_cadence": begin
        wr(REG_FRAME_REPEAT, 2);
        wr(REG_CTRL, 32'h1);
        for (int p = 1; p <= 9; p++) begin
          wr(REG_FRAME_REQ, 1);
          wait_idle();
          expect_reg(REG_GEN_COUNT, p / 3, "generation count");
        end
        foreach (log_commit[k]) if (log_commit[k] != ((k % 3) == 2)) $fatal(1, "pass %0d commit=%0d", k + 1, log_commit[k]);
        expect_reg(REG_STATUS, 32'(1) << ST_FRONT, "front after 3 commits");
      end
      "gens_per_frame": begin
        wr(REG_FRAME_REPEAT, 0);
        wr(REG_GENS_PER_FRAME, 3);
        wr(REG_CTRL, 32'h1);
        wr(REG_FRAME_REQ, 1);
        wait_cycles(5);
        wait_idle();
        wait_cycles(50);
        if (passes != 3) $fatal(1, "%0d passes, expected 3", passes);
        if (!(log_fwd[0] && !log_fwd[1] && !log_fwd[2])) $fatal(1, "fwd pattern wrong");
        if (!(log_commit[0] && log_commit[1] && log_commit[2])) $fatal(1, "commit pattern wrong");
        expect_reg(REG_GEN_COUNT, 3, "generations");
      end
      "pause": begin
        wr(REG_FRAME_REPEAT, 0);
        wr(REG_CTRL, 32'h3);           // RUN | PAUSE
        repeat (4) begin
          wr(REG_FRAME_REQ, 1);
          wait_idle();
        end
        if (passes != 4) $fatal(1, "%0d passes under pause", passes);
        expect_reg(REG_GEN_COUNT, 0, "no commits under pause");
        expect_reg(REG_PASS_COUNT, 4, "passes counted");
      end
      "req_merge": begin
        wr(REG_FRAME_REPEAT, 0);
        wr(REG_CTRL, 32'h1);
        wr(REG_FRAME_REQ, 1);
        while (!busy) @(negedge clk);
        repeat (10) wr(REG_FRAME_REQ, 1);
        wait_idle();
        wait_cycles(300);
        if (passes != 2) $fatal(1, "%0d passes, expected 2", passes);
      end
      "auto": begin
        wr(REG_FRAME_REPEAT, 0);
        wr(REG_CTRL, 32'h5);           // RUN | AUTO
        while (passes < 5) @(negedge clk);
        wr(REG_CTRL, 32'h0);
        begin
          int unsigned at_stop = passes;
          wait_cycles(1000);
          if (passes > at_stop + 1) $fatal(1, "passes continued after RUN cleared");
        end
        expect_reg(REG_GEN_COUNT, passes, "every auto pass commits");
      end
      "run_clear_midpass": begin
        wr(REG_FRAME_REPEAT, 0);
        wr(REG_CTRL, 32'h1);
        wr(REG_FRAME_REQ, 1);
        while (!busy) @(negedge clk);
        wr(REG_CTRL, 32'h0);
        wr(REG_FRAME_REQ, 1);          // stays pending, must not start a pass
        wait_cycles(1000);
        if (passes != 1) $fatal(1, "%0d passes", passes);
        expect_reg(REG_STATUS, (32'(1) << ST_FRONT) | (32'(1) << ST_PENDING), "pending kept, front swapped");
      end
      "midpass_changes": begin
        wr(REG_FRAME_REPEAT, 0);
        wr(REG_CTRL, 32'h1);
        wr(REG_FRAME_REQ, 1);
        while (!busy) @(negedge clk);
        wr(REG_FRAME_REPEAT, 5);
        wr(REG_CTRL, 32'h3);           // PAUSE during the pass
        wr(REG_RULE_PARAM0, 32'h77);
        wait_idle();
        if (passes != 1 || !log_commit[0]) $fatal(1, "commit decision changed mid-pass");
        expect_reg(REG_GEN_COUNT, 1, "mid-pass changes apply to the next pass");
      end
      "reset_state": begin
        wr(REG_FRAME_REPEAT, 0);
        wr(REG_CTRL, 32'h1);
        repeat (3) begin
          wr(REG_FRAME_REQ, 1);
          wait_idle();
        end
        expect_reg(REG_GEN_COUNT, 3, "three commits");
        wr(REG_CTRL, 32'h9);           // RUN | RESET_STATE
        expect_reg(REG_GEN_COUNT, 0, "gen count cleared");
        expect_reg(REG_PASS_COUNT, 0, "pass count cleared");
        expect_reg(REG_STATUS, 0, "front cleared");
        expect_reg(REG_CTRL, 32'h1, "reset bit self-clears");
      end
      default: $fatal(1, "unknown case %s", tc);
    endcase
    $display("TB_PASS case=%s passes=%0d", tc, passes);
    $finish;
  end

  initial begin
    repeat (200000) @(posedge clk);
    $fatal(1, "timeout in case %s", tc);
  end
endmodule
