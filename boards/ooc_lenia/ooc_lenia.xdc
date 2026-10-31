# Out-of-context clocks for ooc_lenia_top: the 200 MHz engine clock and the
# register clock of the growth-table write port (asynchronous to each other).
create_clock -name eclk -period 5.000 [get_ports clk_i]
create_clock -name aclk -period 10.000 [get_ports gt_clk_i]
set_clock_groups -asynchronous -group [get_clocks eclk] -group [get_clocks aclk]
