# Wenxun: Source antenna rules for tsmc65
source $IP_ANTENNA_RULES_TCL
# Wenxun: Source ICC routing options
source $IP_ICC_ROUTE_OPTIONS_TCL

# pad constraints
set_fp_pin_constraints -use_physical_constraints on
# Wenxun: Add this pinpad constraints file when needed
read_pin_pad_physical_constraints "$DESIGN_REF_DATA_PATH/flow/ICC/myscript/floorplan/pinpad_const.tcl"

# create a floorplan
create_floorplan -control_type width_and_height -core_width $CORE_WIDTH -core_height $CORE_HEIGHT -left_io2core $IO2CORE -right_io2core $IO2CORE -bottom_io2core $IO2CORE -top_io2core $IO2CORE

# create power/gnd rings and straps
source -echo -verbose vdd_vss_rings_straps.tcl

# preplace sram
source -echo -verbose preplace_sram.tcl
# set blockages, this might be need when you have macro cells and some dead corner that causing clog
source -echo -verbose blockage.tcl
# preplace tie down cell
source -echo -verbose preplace_filltie.tcl
# route guide, these guides could be release after some step. The reasson to use these guides is to temporarily perhibit routing in some special layers, such as layerss reserved for later use
# Wenxun: Temporaily preventing using of 2 thick metal layers and 1 top metal (for bounding only) at this time. Might want to release this rule if the are utilization is super high
create_route_guide -coordinate [list [list 0 0] [list $CORE_WIDTH $CORE_HEIGHT]] -no_signal_layers {M8 M9 AP} -no_preroute_layers {M8 M9 AP} -name RG_N_2Z1A

# set size only
foreach cg_sz_i [get_object_name [get_cells -hierarchical -filter "@ref_name =~ prim_clock_gating"]] {set_size_only -all_instances [filter_collection [get_cells -hierarchical -filter "@full_name =~ $cg_sz_i*"] {reg_name =~ "CKLNQD"}] true}

 
