// Behavioural AXI4 slave memory for simulation.
//   +mem_stall=<0..95>  percentage of cycles a ready/valid is withheld
//   +mem_lat=<n>        maximum extra cycles before the first R beat or a B
//   +mem_seed=<n>       random seed
// Checks: INCR bursts, full-width size, aligned addresses, no 4 KB crossing,
// WLAST on the last beat, AW/W/AR payload stable while valid and not ready,
// addresses inside the memory.
module axi_mem_model #(
  parameter int unsigned DATA_W    = 128,
  parameter int unsigned ADDR_W    = 32,
  parameter int unsigned ID_W      = 1,
  parameter longint unsigned MEM_BYTES = 64'd33554432,
  parameter type         axi_req_t  = logic,
  parameter type         axi_resp_t = logic
) (
  input  logic      clk_i,
  input  logic      rst_ni,
  input  axi_req_t  req_i,
  output axi_resp_t resp_o
);
  localparam int unsigned     BYTES = DATA_W / 8;
  localparam int unsigned     SIZE  = $clog2(BYTES);
  localparam longint unsigned WORDS = MEM_BYTES / BYTES;

  logic [DATA_W-1:0] mem [WORDS];

  typedef struct {
    logic [ADDR_W-1:0] addr;
    int unsigned       len;
    logic [ID_W-1:0]   id;
    longint unsigned   due;
  } burst_t;

  burst_t aw_q[$], ar_q[$], b_q[$];
  int unsigned stall = 0, lat = 0, w_beat = 0, r_beat = 0;
  longint unsigned now = 0;
  int unsigned seed;
  int unsigned writes = 0, reads = 0;

  initial begin
    void'($value$plusargs("mem_stall=%d", stall));
    void'($value$plusargs("mem_lat=%d", lat));
    if ($value$plusargs("mem_seed=%d", seed)) void'($urandom(seed));
  end

  function automatic bit roll();
    return $urandom_range(99) >= stall;
  endfunction

  task automatic check_burst(string ch, logic [ADDR_W-1:0] addr, int unsigned len,
                             logic [1:0] burst, logic [2:0] size);
    if (burst != 2'b01) $fatal(1, "axi_mem_model: %s burst type %0d is not INCR", ch, burst);
    if (size != 3'(SIZE)) $fatal(1, "axi_mem_model: %s size %0d is not full width", ch, size);
    if (addr % BYTES != 0) $fatal(1, "axi_mem_model: %s address 0x%0h unaligned", ch, addr);
    if ((addr % 4096) + (len + 1) * BYTES > 4096)
      $fatal(1, "axi_mem_model: %s burst at 0x%0h, %0d beats crosses a 4KB boundary", ch, addr, len + 1);
    if (longint'(addr) + (len + 1) * BYTES > MEM_BYTES)
      $fatal(1, "axi_mem_model: %s burst at 0x%0h outside memory", ch, addr);
  endtask

  // Payload stability checks.
  logic     aw_pend, w_pend, ar_pend;
  axi_req_t prev;
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (aw_pend && (!req_i.aw_valid || req_i.aw != prev.aw)) $fatal(1, "axi_mem_model: AW changed while stalled");
      if (w_pend  && (!req_i.w_valid  || req_i.w  != prev.w))  $fatal(1, "axi_mem_model: W changed while stalled");
      if (ar_pend && (!req_i.ar_valid || req_i.ar != prev.ar)) $fatal(1, "axi_mem_model: AR changed while stalled");
    end
    aw_pend <= rst_ni && req_i.aw_valid && !resp_o.aw_ready;
    w_pend  <= rst_ni && req_i.w_valid  && !resp_o.w_ready;
    ar_pend <= rst_ni && req_i.ar_valid && !resp_o.ar_ready;
    prev    <= req_i;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      resp_o <= '0;
      aw_q.delete();
      ar_q.delete();
      b_q.delete();
      w_beat <= 0;
      r_beat <= 0;
    end else begin
      now <= now + 1;
      // AW
      if (req_i.aw_valid && resp_o.aw_ready) begin
        check_burst("AW", req_i.aw.addr, req_i.aw.len, req_i.aw.burst, req_i.aw.size);
        aw_q.push_back('{req_i.aw.addr, req_i.aw.len, req_i.aw.id, 0});
      end
      resp_o.aw_ready <= roll();
      // W (accepted only once its AW is known)
      if (req_i.w_valid && resp_o.w_ready) begin
        automatic burst_t b = aw_q[0];
        automatic longint unsigned word = (longint'(b.addr) / BYTES) + w_beat;
        for (int unsigned i = 0; i < BYTES; i++)
          if (req_i.w.strb[i]) mem[word][8*i +: 8] <= req_i.w.data[8*i +: 8];
        if (req_i.w.last != (w_beat == b.len))
          $fatal(1, "axi_mem_model: WLAST %0d on beat %0d of %0d", req_i.w.last, w_beat, b.len + 1);
        if (w_beat == b.len) begin
          b.due = now + $urandom_range(lat);
          b_q.push_back(b);
          void'(aw_q.pop_front());
          w_beat <= 0;
          writes++;
        end else begin
          w_beat <= w_beat + 1;
        end
      end
      resp_o.w_ready <= (aw_q.size() > 0 || (req_i.aw_valid && resp_o.aw_ready)) && roll();
      // B
      if (resp_o.b_valid && req_i.b_ready) begin
        void'(b_q.pop_front());
        resp_o.b_valid <= 1'b0;
      end else if (!resp_o.b_valid && b_q.size() > 0 && b_q[0].due <= now && roll()) begin
        resp_o.b_valid <= 1'b1;
        resp_o.b.id    <= b_q[0].id;
        resp_o.b.resp  <= '0;
      end
      // AR
      if (req_i.ar_valid && resp_o.ar_ready) begin
        check_burst("AR", req_i.ar.addr, req_i.ar.len, req_i.ar.burst, req_i.ar.size);
        ar_q.push_back('{req_i.ar.addr, req_i.ar.len, req_i.ar.id, now + $urandom_range(lat)});
      end
      resp_o.ar_ready <= roll();
      // R
      if (resp_o.r_valid && req_i.r_ready) begin
        resp_o.r_valid <= 1'b0;
        if (resp_o.r.last) begin
          void'(ar_q.pop_front());
          r_beat <= 0;
          reads++;
        end else begin
          r_beat <= r_beat + 1;
        end
      end else if (!resp_o.r_valid && ar_q.size() > 0 && ar_q[0].due <= now && roll()) begin
        resp_o.r_valid <= 1'b1;
        resp_o.r.id    <= ar_q[0].id;
        resp_o.r.data  <= mem[(longint'(ar_q[0].addr) / BYTES) + r_beat];
        resp_o.r.resp  <= '0;
        resp_o.r.last  <= r_beat == ar_q[0].len;
      end
    end
  end

  // Back-door access for testbenches.
  task automatic load_hex(string file, longint unsigned addr);
    $readmemh(file, mem, addr / BYTES);
  endtask

  task automatic dump_hex(string file, longint unsigned addr, longint unsigned bytes);
    $writememh(file, mem, addr / BYTES, (addr + bytes) / BYTES - 1);
  endtask

  task automatic fill(longint unsigned addr, longint unsigned bytes, logic [DATA_W-1:0] value);
    for (longint unsigned w = addr / BYTES; w < (addr + bytes) / BYTES; w++) mem[w] = value;
  endtask
endmodule
