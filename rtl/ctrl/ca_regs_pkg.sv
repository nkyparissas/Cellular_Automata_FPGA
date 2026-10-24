// AXI4-Lite register map (spec Section 10). host/ca_host/regs.py mirrors
// these constants; tests/host/test_regs_parity.py keeps them in step.
package ca_regs_pkg;
  localparam logic [7:0]  REG_ID             = 8'h00;
  localparam logic [7:0]  REG_CTRL           = 8'h04;
  localparam logic [7:0]  REG_STATUS         = 8'h08;
  localparam logic [7:0]  REG_FRAME_REQ      = 8'h0C;
  localparam logic [7:0]  REG_FRAME_REPEAT   = 8'h10;
  localparam logic [7:0]  REG_GENS_PER_FRAME = 8'h14;
  localparam logic [7:0]  REG_GEN_COUNT      = 8'h18;
  localparam logic [7:0]  REG_PASS_COUNT     = 8'h1C;
  localparam logic [7:0]  REG_BUF0_LO        = 8'h20;
  localparam logic [7:0]  REG_BUF0_HI        = 8'h24;
  localparam logic [7:0]  REG_BUF1_LO        = 8'h28;
  localparam logic [7:0]  REG_BUF1_HI        = 8'h2C;
  localparam logic [7:0]  REG_GRID_DIM       = 8'h30;
  localparam logic [7:0]  REG_CORE_CFG       = 8'h34;
  localparam logic [7:0]  REG_RULE_PARAM0    = 8'h40;
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
endpackage
