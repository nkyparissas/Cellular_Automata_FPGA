// AXI4-Lite register map (spec Section 10; Lenia design spec Section 6.4).
// host/ca_host/regs.py mirrors these constants; tests/host/test_regs_parity.py
// keeps them in step. 16 address bits are decoded (the map repeats every 64 KB).
package ca_regs_pkg;
  localparam logic [15:0] REG_ID             = 16'h0000;
  localparam logic [15:0] REG_CTRL           = 16'h0004;
  localparam logic [15:0] REG_STATUS         = 16'h0008;
  localparam logic [15:0] REG_FRAME_REQ      = 16'h000C;
  localparam logic [15:0] REG_FRAME_REPEAT   = 16'h0010;
  localparam logic [15:0] REG_GENS_PER_FRAME = 16'h0014;
  localparam logic [15:0] REG_GEN_COUNT      = 16'h0018;
  localparam logic [15:0] REG_PASS_COUNT     = 16'h001C;
  localparam logic [15:0] REG_BUF0_LO        = 16'h0020;
  localparam logic [15:0] REG_BUF0_HI        = 16'h0024;
  localparam logic [15:0] REG_BUF1_LO        = 16'h0028;
  localparam logic [15:0] REG_BUF1_HI        = 16'h002C;
  localparam logic [15:0] REG_GRID_DIM       = 16'h0030;
  localparam logic [15:0] REG_CORE_CFG       = 16'h0034;
  localparam logic [15:0] REG_RULE_PARAM0    = 16'h0040;
  // Lenia cores only (other rules read 0 and ignore writes).
  localparam logic [15:0] REG_LENIA_CFG      = 16'h0060;
  localparam logic [15:0] REG_KERNEL_DATA    = 16'h0064;
  localparam logic [15:0] REG_GROWTH_SHIFT   = 16'h0068;
  localparam logic [15:0] REG_GROWTH_COMMIT  = 16'h006C;
  localparam logic [15:0] REG_GROWTH_GEN     = 16'h0070;
  localparam logic [15:0] REG_GROWTH_TABLE   = 16'h8000;   // + 4 * index
  localparam logic [31:0] CA_ID              = 32'hCA5E_0001;
  // CTRL bits
  localparam int unsigned CTRL_RUN           = 0;
  localparam int unsigned CTRL_PAUSE         = 1;
  localparam int unsigned CTRL_AUTO          = 2;
  localparam int unsigned CTRL_RESET_STATE   = 3;
  // STATUS bits
  localparam int unsigned ST_BUSY            = 0;
  localparam int unsigned ST_FRONT           = 1;
  localparam int unsigned ST_PENDING         = 2;
  localparam int unsigned ST_KERNEL_PENDING  = 3;
  localparam int unsigned ST_GROWTH_PENDING  = 4;
  localparam int unsigned ST_GROWTH_BANK     = 5;
endpackage
