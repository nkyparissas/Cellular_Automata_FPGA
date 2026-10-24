// Line-buffer testbench: a behavioural reader feeds the virtual-row sequence
// (+grid_hex) with random gaps, a behavioural writer pops output rows with
// random delays, and every valid window is written to +out_file for the
// Python checker.
`timescale 1ns/1ps
module tb_line_buffer #(
  parameter int unsigned GRID_X = 32,
  parameter int unsigned GRID_Y = 12,
  parameter int unsigned CELL_W = 8,
  parameter int unsigned NBH    = 5,
  parameter int unsigned DATA_W = 32,
  parameter int unsigned BND_ID = 0,
  parameter int unsigned PASSES = 2
);
  import ca_pkg::*;
  localparam boundary_e   BND   = boundary_e'(BND_ID);
  localparam int unsigned SLOTS = NBH + 1;
  localparam int unsigned SLW   = $clog2(SLOTS);
  localparam int unsigned BPR   = GRID_X * CELL_W / DATA_W;
  localparam int unsigned BW    = BPR > 1 ? $clog2(BPR) : 1;
  localparam int unsigned V     = virt_rows(GRID_Y, NBH, BND);
  localparam int unsigned O     = out_rows(GRID_Y, NBH, BND);
  localparam int unsigned PW    = $clog2(NBH + 1) + 2;

  logic aclk = 0, eclk = 0, arst_n = 0, erst_n = 0;
  int unsigned aclk_ps, eclk_ps, gap;
  initial begin
    if (!$value$plusargs("aclk_ps=%d", aclk_ps)) aclk_ps = 5000;
    if (!$value$plusargs("eclk_ps=%d", eclk_ps)) eclk_ps = 5000;
    if (!$value$plusargs("gap=%d", gap)) gap = 30;
  end
  always #(aclk_ps * 1ps / 2) aclk = ~aclk;
  always #(eclk_ps * 1ps / 2) eclk = ~eclk;

  logic                         alloc_valid = 0, alloc_ready, wr_en = 0, row_done = 0;
  logic [SLW-1:0]               alloc_slot, wr_slot;
  logic [BW-1:0]                wr_addr;
  logic [DATA_W-1:0]            wr_data;
  logic [PW-1:0]                popped = 0;
  logic [NBH-1:0][CELL_W-1:0]   col;
  logic                         vld;

  ca_line_buffer #(.GRID_X(GRID_X), .GRID_Y(GRID_Y), .CELL_W(CELL_W), .NBH(NBH),
                   .DATA_W(DATA_W), .BND(BND), .FIFO_ROWS(2)) dut (
    .aclk_i(aclk), .arst_ni(arst_n), .alloc_valid_i(alloc_valid), .alloc_ready_o(alloc_ready),
    .alloc_slot_o(alloc_slot), .wr_en_i(wr_en), .wr_slot_i(wr_slot), .wr_addr_i(wr_addr),
    .wr_data_i(wr_data), .row_done_i(row_done), .popped_i(popped),
    .eclk_i(eclk), .erst_ni(erst_n), .col_o(col), .vld_o(vld));

  logic [DATA_W-1:0] rows [PASSES * V * BPR];
  string grid_hex, out_file;
  int fd;
  int unsigned windows = 0;
  int unsigned popped_total = 0;

  initial begin
    if (!$value$plusargs("grid_hex=%s", grid_hex)) $fatal(1, "+grid_hex missing");
    if (!$value$plusargs("out_file=%s", out_file)) $fatal(1, "+out_file missing");
    $readmemh(grid_hex, rows);
    fd = $fopen(out_file, "w");
    repeat (4) @(posedge aclk);
    arst_n = 1;
    erst_n = 1;
  end

  // Reader stand-in. Drives on negedges and samples DUT outputs there, so the
  // values seen are the ones the DUT samples at the next posedge.
  initial begin
    wait (arst_n);
    for (int unsigned v = 0; v < PASSES * V; v++) begin
      @(negedge aclk);
      while ($urandom_range(99) < gap) @(negedge aclk);
      alloc_valid = 1;
      while (!alloc_ready) @(negedge aclk);
      wr_slot = alloc_slot;          // handshake completes at the next posedge
      @(negedge aclk);
      alloc_valid = 0;
      for (int unsigned b = 0; b < BPR; b++) begin
        while ($urandom_range(99) < gap) begin
          wr_en = 0;
          @(negedge aclk);
        end
        wr_en   = 1;
        wr_addr = BW'(b);
        wr_data = rows[v * BPR + b];
        @(negedge aclk);
      end
      wr_en    = 0;
      row_done = 1;
      @(negedge aclk);
      row_done = 0;
    end
  end

  // Writer stand-in: pops output rows some time after they were produced.
  initial begin
    wait (arst_n);
    forever begin
      @(negedge aclk);
      if (windows / GRID_X > popped_total && $urandom_range(99) >= gap) begin
        popped_total++;
        popped = PW'(popped_total);
      end
    end
  end

  // Checker: reconstruct the engine's window exactly as ca_window would.
  logic [NBH-1:0][NBH-1:0][CELL_W-1:0] win;
  always @(negedge eclk) begin
    automatic logic [NBH-1:0][NBH-1:0][CELL_W-1:0] nw;
    for (int i = 0; i < NBH; i++) begin
      for (int j = 0; j + 1 < NBH; j++) nw[i][j] = win[i][j+1];
      nw[i][NBH-1] = col[i];
    end
    win = nw;
    if (vld && erst_n) begin
      for (int i = 0; i < NBH; i++)
        for (int j = 0; j < NBH; j++) $fwrite(fd, "%0h ", nw[i][j]);
      $fwrite(fd, "\n");
      windows++;
      if (windows == PASSES * O * GRID_X) begin
        $fclose(fd);
        $display("TB_PASS windows=%0d", windows);
        $finish;
      end
    end
  end

  initial begin
    repeat (PASSES * V * GRID_X * 40) @(posedge eclk);
    $fatal(1, "timeout: %0d windows of %0d", windows, PASSES * O * GRID_X);
  end
endmodule
