#****SAIF-******************************************************************
# Set the design paths
#**********************************************************************
# set design_name
set DESIGN_NAME "soc_ahblite"
set HIER_DESIGNS ""
source -echo -verbose rtl_source_files.tcl

set netList_path "../syn_rtl"
set sdc_path "../sdc"
set log_path "../report"

lappend search_path $RTL_SEARCH_PATHS
###############################################################################
# environment setup
###############################################################################
source setup_env.tcl

################################################################################
# library setup
################################################################################
# set the path of standard cells
# NOTE: Remember to change the library path accordingly!
set stdCell_path "/home/master/project1/day2/library"

lappend search_path $stdCell_path

# set target library for standard cells
set_app_var target_library "tcbn65gplusbwp12twc.db"
# set synthetic library for IPs
set_app_var synthetic_library "dw_foundation.sldb"
# set link library for netlist analysis
# NOTE: 追加 RA1HD_4KB 硬核 .db (黑盒, dont_touch); 其 .v 不参与 analyze
set_app_var link_library "* $target_library RA1HD_4KB_ss_0p90v_0p90v_125c.db $synthetic_library"

# Designware
lappend synlib_wait_for_design_license "DesignWare-Foundation"

# Wire Load models
# lappend link_library ""

# TODO: Cells dont use
# source -echo -verbose cell_dont_use1.tcl
# source -echo -verbose cell_dont_use2.tcl

################################################################################
# read RTL
################################################################################
set_app_var hdlin_enable_hier_map true

# read RTL
analyze -format sverilog ${RTL_SOURCE_FILES}

elaborate ${DESIGN_NAME}

foreach design ${HIER_DESIGNS} {
    if {[filter [get_designs -quiet *] "@hdl_template == $design"] != ""} {
        remove_design -hierarchy [filter [get_designs -quiet *] "@hdl_template == $design"]
    }
}

write -f verilog -hier -output "${netList_path}/${DESIGN_NAME}_interm.sv"

set_verification_top

set_app_var link_portname_allow_period_to_match_underscore true
set_app_var link_portname_allow_square_bracket_to_match_underscore true

# set the name of the report file
set rpt_file "${DESIGN_NAME}.rpt"

################################################################################
# Link designs
################################################################################
current_design ${DESIGN_NAME}
link

list_design -show_file

################################################################################
# Don't optimize ${HIER_DESIGNS}
################################################################################
if {${HIER_DESIGNS} != ""} {
 set_dont_touch [get_designs ${HER_DESIGNS}]

 set_boundary_optimization ${HIER_DESIGNS} false
 set_app_var compilel_preserve_subdesign_interfaces true
 set_app_var compile_enable_constant_propagation_with_no_boundary_opt false
}

################################################################################
# Timing and physical constraints
################################################################################
source -echo -verbose ${DESIGN_NAME}.constraints.tcl

# set_perserver_clock_gate [get_cells -hierarchical -filter "@ref_name =~ POSTING*"]

set_fix_multiple_port_nets -all -buffer_constants

check_design

uniquify

################################################################################
# compile setup
################################################################################

source setup_compile.tcl

# disable register merging
set_app_var compile_enable_register_merging false
print_variable_group compile

################################################################################
# compile
################################################################################

# compile
compile_ultra -no_autoungroup -no_seq_output_inversion

set_app_var uniquify_naming_style "${DESIGN_NAME}_%s_%d"
uniquify -force

change_names -rules verilog -hier

################################################################################
# generate constraints file
################################################################################

# write_sdc "${sdc_path}/${DESIGN_NAME}.sdc" -version 1.7
write_sdc -nosplit ${sdc_path}/${DESIGN_NAME}.mapped.sdc

update_timing

################################################################################
# generate reports
################################################################################
source report.tcl

################################################################################
# generate output netlist
################################################################################

# Hongyang: do not remove design for the initial DC run
# remove_design -hierarchy [get_designs -quiet ${HIER_DESIGNS}]

# generate netlist
write -f verilog -hier -output "${netList_path}/${DESIGN_NAME}.mapped.v"
write -f ddc -hier -output "${netList_path}/${DESIGN_NAME}.mapped.ddc"

report_timing_requirements

# Hongyang: Create block abstraction for future synthesis 
# create_block_abstraction
# write -f ddc -hier -output "${netList_path}/${DESIGN_NAME}.abstract.ddc"

exit
