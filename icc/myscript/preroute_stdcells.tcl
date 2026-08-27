#connect tie
source my_connect_tie.tcl

# Wenxun: $TIEHICELL and $TIELOCELL are the tie-high and tie-low cell from IP defined in icc_setup.tcl
connect_tie_cells -objects [get_cells -within [list 0 0 $CORE_WIDTH $CORE_HEIGHT]] -obj_type cell_inst -tie_high_lib_cell $TIEHICELL -tie_low_lib_cell $TIELOCELL -incremental true

# connect PG
source my_connect_pg.tcl
# dont route in Blockage
# TO DO: set your blockage here to avoid route in blockage
#create_route_guide -coordinate [list [list $BLOCK_X0 $BLOCK_Y0] [list [expr $IO2CORE + $CORE_WIDTH ] [expr $IO2CORE + $CORE_HEIGHT]]] -no_preroute_layers {M1 M2 M3 M4 M5 M6 M7} -name RG_NP_1

preroute_standard_cells -mode rail -connect horizontal -nets VDD_SOC -route_pins_on_layer M1 -do_not_route_over_macros
preroute_standard_cells -mode rail -connect horizontal -nets GND_SOC -route_pins_on_layer M1 -fill_empty_rows

remove_route_guide -name RG_NP_1
