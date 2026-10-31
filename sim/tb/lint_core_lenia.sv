// Lint-only top: ca_core built for the Lenia rule (NBH 7, 16-bit cells, the
// default 1920x1080 grid) with concrete AXI4 / AXI4-Lite types.
`include "axi/typedef.svh"
// The types live in a package so that the ports can use them; it shares this file.
/* verilator lint_off DECLFILENAME */
package lint_core_lenia_pkg;
  typedef logic [31:0]  addr_t;
  typedef logic [0:0]   id_t;
  typedef logic [127:0] data_t;
  typedef logic [15:0]  strb_t;
  typedef logic [0:0]   user_t;
  typedef logic [31:0]  ldata_t;
  typedef logic [3:0]   lstrb_t;
  `AXI_TYPEDEF_ALL(axi, addr_t, id_t, data_t, strb_t, user_t)
  `AXI_LITE_TYPEDEF_ALL(axil, addr_t, ldata_t, lstrb_t)
endpackage
/* verilator lint_on DECLFILENAME */

module lint_core_lenia
  import lint_core_lenia_pkg::*;
(
  input  logic         aclk_i,
  input  logic         arst_ni,
  input  logic         eclk_i,
  input  logic         erst_ni,
  input  axil_req_t    s_axil_req_i,
  output axil_resp_t   s_axil_resp_o,
  output axi_req_t     m_axi_req_o,
  input  axi_resp_t    m_axi_resp_i,
  output logic [127:0] m_axis_tdata_o,
  output logic         m_axis_tvalid_o,
  input  logic         m_axis_tready_i,
  output logic         m_axis_tlast_o,
  output logic         m_axis_tuser_o,
  input  logic         frame_req_i,
  output logic         pass_done_o
);
  ca_core #(.CELL_W(16), .NBH(7), .RULE(ca_pkg::RULE_LENIA), .DATA_W(128), .axi_req_t(axi_req_t),
            .axi_resp_t(axi_resp_t), .axil_req_t(axil_req_t), .axil_resp_t(axil_resp_t)) i_core (.*);
endmodule
