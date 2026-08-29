# Tie-net mode connects constants directly to the PG nets.  In tie-cell mode,
# common_optimization_settings_icc.tcl preserves the explicit TIEH/TIEL cells
# already present in the synthesized DDC.
if {!$ICC_TIE_CELL_FLOW} {
    source [file join $ICC_ROOT myscript my_connect_tie.tcl]
}

# connect PG
source [file join $ICC_ROOT myscript my_connect_pg.tcl]
# dont route in Blockage
# TO DO: set your blockage here to avoid route in blockage
#create_route_guide -coordinate [list [list $BLOCK_X0 $BLOCK_Y0] [list [expr $IO2CORE + $CORE_WIDTH ] [expr $IO2CORE + $CORE_HEIGHT]]] -no_preroute_layers {M1 M2 M3 M4 M5 M6 M7} -name RG_NP_1

preroute_standard_cells -mode rail -connect horizontal -nets VDD_SOC -route_pins_on_layer M1 -do_not_route_over_macros
preroute_standard_cells -mode rail -connect horizontal -nets GND_SOC -route_pins_on_layer M1 -fill_empty_rows

if {[catch {remove_route_guide -name RG_NP_1}]} {
    echo "RM-Info: route guide RG_NP_1 does not exist; skipping removal"
}
