insert_stdcell_filler -cell_with_metal $FILLER_CELL -connect_to_power VDD_SOC -connect_to_ground GND_SOC

# make vdd/vss connections
source preroute_stdcells.tcl
