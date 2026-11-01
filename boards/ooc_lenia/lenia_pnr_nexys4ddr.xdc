# Pins of lenia_pnr_top on the Nexys 4 DDR (as in boards/nexys4ddr/nexys4ddr.xdc).
# The clock frequency is set on the nextpnr-xilinx command line (--freq).
set_property PACKAGE_PIN E3 [get_ports clk_i]
set_property IOSTANDARD LVCMOS33 [get_ports clk_i]
set_property PACKAGE_PIN C12 [get_ports rst_ni]
set_property IOSTANDARD LVCMOS33 [get_ports rst_ni]
set_property PACKAGE_PIN H17 [get_ports led_o]
set_property IOSTANDARD LVCMOS33 [get_ports led_o]
