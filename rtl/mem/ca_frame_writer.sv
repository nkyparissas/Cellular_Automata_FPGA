// AXI4 frame writer (spec Sections 4, 5 and 9). Consumes the packed output
// rows of one pass from the output FIFO. When committing it writes output row
// o to memory row out_row_first + o in bursts of at most MAX_BURST beats that
// never cross 4 KB; otherwise it pops and discards the rows. popped_o counts
// fully consumed rows (it feeds the line buffer's FIFO credit); done_o pulses
// once all rows are consumed and every write response has returned.
// Only the AW, W and B fields of axi_req_o are driven.
module ca_frame_writer #(
  parameter int unsigned       GRID_X    = 64,
  parameter int unsigned       GRID_Y    = 24,
  parameter int unsigned       CELL_W    = 8,
  parameter int unsigned       NBH       = 5,
  parameter int unsigned       DATA_W    = 128,
  parameter int unsigned       ADDR_W    = 32,
  parameter ca_pkg::boundary_e BND       = ca_pkg::BND_TOROIDAL,
  parameter int unsigned       MAX_BURST = 64,
  parameter int unsigned       PW        = $clog2(NBH + 1) + 2,
  parameter type               axi_req_t  = logic,
  parameter type               axi_resp_t = logic
) (
  input  logic              clk_i,
  input  logic              rst_ni,
  input  logic              start_i,
  input  logic              commit_i,
  input  logic [ADDR_W-1:0] base_addr_i,
  output logic              done_o,
  input  logic [DATA_W-1:0] s_tdata_i,
  input  logic              s_tvalid_i,
  output logic              s_tready_o,
  output logic [PW-1:0]     popped_o,
  output axi_req_t          axi_req_o,
  // Write-only master: the read-channel and B id/resp fields are unused.
  /* verilator lint_off UNUSEDSIGNAL */
  input  axi_resp_t         axi_resp_i
  /* verilator lint_on UNUSEDSIGNAL */
);
  localparam int unsigned O         = ca_pkg::out_rows(GRID_Y, NBH, BND);
  localparam int unsigned FIRST     = ca_pkg::out_row_first(NBH, BND);
  localparam int unsigned OW        = $clog2(O + 1);
  localparam int unsigned BPR       = GRID_X * CELL_W / DATA_W;
  localparam int unsigned CW        = $clog2(BPR + 1);
  localparam int unsigned BYTES     = DATA_W / 8;
  localparam int unsigned SIZE      = $clog2(BYTES);
  localparam int unsigned ROW_BYTES = GRID_X * CELL_W / 8;

  typedef enum logic [2:0] {S_IDLE, S_ROW, S_AW, S_W, S_DISCARD, S_WAIT_B} state_e;
  state_e            state;
  logic [ADDR_W-1:0] base_q, addr;
  logic [OW-1:0]     row;
  logic [CW-1:0]     rem, blen, beat;
  logic [15:0]       b_out;      // bursts awaiting a write response
  logic              aw_hs, w_hs, b_hs;

  // Burst length: remaining beats, MAX_BURST and the distance to 4 KB.
  logic [12:0] to_4k;
  always_comb begin
    to_4k = 13'(13'd4096 - 13'(addr[11:0])) >> SIZE;
    blen  = rem;
    if (32'(blen) > 32'(MAX_BURST)) blen = CW'(MAX_BURST);
    if (32'(blen) > 32'(to_4k))     blen = CW'(to_4k);
  end

  always_comb begin
    axi_req_o          = '0;
    axi_req_o.aw.addr  = addr;
    axi_req_o.aw.len   = 8'(blen - 1'b1);
    axi_req_o.aw.size  = 3'(SIZE);
    axi_req_o.aw.burst = 2'b01;
    axi_req_o.aw.cache = 4'b0011;
    axi_req_o.aw_valid = state == S_AW;
    axi_req_o.w.data   = s_tdata_i;
    axi_req_o.w.strb   = '1;
    axi_req_o.w.last   = beat == blen - 1'b1;
    axi_req_o.w_valid  = state == S_W && s_tvalid_i;
    axi_req_o.b_ready  = 1'b1;
  end

  assign s_tready_o = (state == S_W && axi_resp_i.w_ready) || state == S_DISCARD;
  assign aw_hs      = axi_req_o.aw_valid && axi_resp_i.aw_ready;
  assign w_hs       = axi_req_o.w_valid && axi_resp_i.w_ready;
  assign b_hs       = axi_resp_i.b_valid;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state    <= S_IDLE;
      base_q   <= '0;
      addr     <= '0;
      row      <= '0;
      rem      <= '0;
      beat     <= '0;
      b_out    <= '0;
      popped_o <= '0;
      done_o   <= 1'b0;
    end else begin
      done_o <= 1'b0;
      b_out  <= b_out + 16'(aw_hs) - 16'(b_hs);
      case (state)
        S_IDLE: if (start_i) begin
          base_q <= base_addr_i;
          row    <= '0;
          beat   <= '0;
          state  <= commit_i ? S_ROW : S_DISCARD;
        end
        S_ROW: begin
          addr  <= base_q + ADDR_W'(FIRST + row) * ADDR_W'(ROW_BYTES);
          rem   <= CW'(BPR);
          state <= S_AW;
        end
        S_AW: if (aw_hs) begin
          beat  <= '0;
          state <= S_W;
        end
        S_W: if (w_hs) begin
          if (beat == blen - 1'b1) begin
            addr <= addr + ADDR_W'(blen) * ADDR_W'(BYTES);
            rem  <= rem - blen;
            if (rem == blen) begin
              popped_o <= popped_o + 1'b1;
              row      <= row + 1'b1;
              state    <= (row == OW'(O - 1)) ? S_WAIT_B : S_ROW;
            end else begin
              state <= S_AW;
            end
          end else begin
            beat <= beat + 1'b1;
          end
        end
        S_DISCARD: if (s_tvalid_i) begin
          if (beat == CW'(BPR - 1)) begin
            beat     <= '0;
            popped_o <= popped_o + 1'b1;
            row      <= row + 1'b1;
            if (row == OW'(O - 1)) begin
              done_o <= 1'b1;
              state  <= S_IDLE;
            end
          end else begin
            beat <= beat + 1'b1;
          end
        end
        default: if (b_out == '0 || (b_out == 16'd1 && b_hs)) begin  // S_WAIT_B
          done_o <= 1'b1;
          state  <= S_IDLE;
        end
      endcase
    end
  end
endmodule
