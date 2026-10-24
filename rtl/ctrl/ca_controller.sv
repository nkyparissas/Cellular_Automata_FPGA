// Pass controller (spec Section 9): the single owner of the commit and
// buffer-swap decision. All settings are sampled at pass start.
module ca_controller (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        run_i,
  input  logic        pause_i,
  input  logic        auto_i,
  input  logic        reset_state_i,
  input  logic        req_i,            // doorbell or consumer frame request
  input  logic [15:0] frame_repeat_i,
  input  logic [15:0] gens_per_frame_i,
  output logic        pass_start_o,     // starts reader and writer, samples settings
  output logic        rd_fwd_en_o,      // valid from pass_start_o until the pass ends
  output logic        wr_commit_o,
  input  logic        rd_done_i,
  input  logic        wr_done_i,
  output logic        front_o,
  output logic        busy_o,           // a pass is running or fast-forward passes remain
  output logic        pending_o,
  output logic [31:0] gen_count_o,
  output logic [31:0] pass_count_o,
  output logic        pass_done_o
);
  logic [15:0] repeat_cnt, ff_left;
  logic        active, rd_seen, wr_seen, start_req, start_ff;

  assign busy_o = active || (ff_left != '0 && run_i && !pause_i);

  // Fast-forward passes run before new requests; both need RUN and no PAUSE
  // (a requested pass under PAUSE still runs, it just does not commit).
  assign start_ff  = !active && run_i && !pause_i && ff_left != '0;
  assign start_req = !active && run_i && !start_ff && (pending_o || auto_i);

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      pass_start_o <= 1'b0;
      rd_fwd_en_o  <= 1'b0;
      wr_commit_o  <= 1'b0;
      front_o      <= 1'b0;
      active       <= 1'b0;
      pending_o    <= 1'b0;
      gen_count_o  <= '0;
      pass_count_o <= '0;
      pass_done_o  <= 1'b0;
      repeat_cnt   <= '0;
      ff_left      <= '0;
      rd_seen      <= 1'b0;
      wr_seen      <= 1'b0;
    end else begin
      pass_start_o <= 1'b0;
      pass_done_o  <= 1'b0;

      if (start_ff) begin
        pass_start_o <= 1'b1;
        active       <= 1'b1;
        rd_fwd_en_o  <= 1'b0;
        wr_commit_o  <= 1'b1;
        ff_left      <= ff_left - 1'b1;
      end else if (start_req) begin
        automatic logic commit = !pause_i && repeat_cnt >= frame_repeat_i;
        pass_start_o <= 1'b1;
        active       <= 1'b1;
        rd_fwd_en_o  <= 1'b1;
        wr_commit_o  <= commit;
        if (commit) begin
          repeat_cnt <= '0;
          ff_left    <= (gens_per_frame_i == '0) ? '0 : gens_per_frame_i - 1'b1;
        end else if (!pause_i && repeat_cnt != '1) begin
          repeat_cnt <= repeat_cnt + 1'b1;
        end
      end else if (!active && (pause_i || !run_i)) begin
        ff_left <= '0;   // PAUSE or RUN cleared abandons fast-forward
      end

      // Requests arriving while a requested pass starts belong to the next one.
      if (req_i)          pending_o <= 1'b1;
      else if (start_req) pending_o <= 1'b0;

      if (active) begin
        automatic logic rd = rd_seen || rd_done_i;
        automatic logic wr = wr_seen || wr_done_i;
        rd_seen <= rd;
        wr_seen <= wr;
        if (rd && wr) begin
          active       <= 1'b0;
          rd_seen      <= 1'b0;
          wr_seen      <= 1'b0;
          pass_done_o  <= 1'b1;
          pass_count_o <= pass_count_o + 1'b1;
          if (wr_commit_o) begin
            front_o     <= !front_o;
            gen_count_o <= gen_count_o + 1'b1;
          end
        end
      end

      if (reset_state_i && !active) begin
        front_o      <= 1'b0;
        gen_count_o  <= '0;
        pass_count_o <= '0;
        repeat_cnt   <= '0;
        ff_left      <= '0;
        pending_o    <= 1'b0;
        pass_start_o <= 1'b0;
        active       <= 1'b0;
      end
    end
  end
endmodule
