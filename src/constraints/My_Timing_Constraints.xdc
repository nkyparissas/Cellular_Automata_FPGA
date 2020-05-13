# the paths below result in false alarms
# all clock domain crossings hazards have been resolved by design
# these timing constraints should be used only during the implementation phase - disable them during synthesis (unless hierarchy flattening is disabled instead). 

set_max_delay -from [get_clocks -of_objects [get_pins CLOCKING_WIZARD_GRAPHICS/inst/mmcm_adv_inst/CLKOUT0]] -to [get_clocks -of_objects [get_pins MIG_CONTROLLER/u_mig_7series_0_mig/u_ddr2_infrastructure/gen_mmcm.mmcm_i/CLKFBOUT]] 6.5
set_max_delay -from [get_pins {GRAPHICS_CONTROLLER/FHD_SYNC_CONTROLLER/HCOUNTER_reg*/C}] -to [get_pins {MEMORY_ACCESS_ARBITRATOR/GRAPHICS_REQ_SIGNAL_reg*/D}] 12.0
set_max_delay -from [get_pins {GRID_LINES_BUFFER.GRID_LINES_BUFFER/TOTAL_NUM_OF_FILLED_LINES_reg*/C}] -to [get_pins {GRID_LINES_BUFFER.GRID_LINES_BUFFER/SYNCHRONIZER/DATA_OUT_1_reg*/D}] 12.0
set_max_delay -from [get_pins {GRID_LINES_BUFFER.GRID_LINES_BUFFER/LINE_BEING_FILLED_reg*/C}] -to [get_pins {GRID_LINES_BUFFER.GRID_LINES_BUFFER/SYNCHRONIZER/DATA_OUT_2_reg*/D}] 12.0
set_max_delay -from [get_pins {GRID_LINES_BUFFER.GRID_LINES_BUFFER/SYNC_CONTROL_reg/C}] -to [get_pins {GRID_LINES_BUFFER.GRID_LINES_BUFFER/SYNCHRONIZER/CONTROL_SIGNAL_reg[0]/D}] 12.0