#****SAIF-******************************************************************
# Set the design paths
#**********************************************************************
# set design_name
set DESIGN_NAME "soc_ahblite"
set HIER_DESIGNS ""

set REQUIRED_ENV_VARS {
    PROJECT_ROOT
    SOC_ROOT
    STD_CELL_DB
    STD_CELL_MIN_DB
    SRAM_DB
    SRAM_MIN_DB
    DW_FOUNDATION_DB
    SETUP_ENV_TCL
    SETUP_COMPILE_TCL
}
foreach env_var ${REQUIRED_ENV_VARS} {
    if {![info exists env(${env_var})] || $env(${env_var}) eq ""} {
        error "Required environment variable ${env_var} is not set; run dc/compile.sh"
    }
}

set SCRIPT_DIR [file dirname [file normalize [info script]]]
source -echo -verbose [file join ${SCRIPT_DIR} rtl_source_files.tcl]

set netList_path [file join $env(PROJECT_ROOT) syn_rtl]
set sdc_path [file join $env(PROJECT_ROOT) sdc]
set log_path [file join $env(PROJECT_ROOT) report]

lappend search_path $RTL_SEARCH_PATHS
###############################################################################
# environment setup
###############################################################################
source -echo -verbose $env(SETUP_ENV_TCL)

################################################################################
# library setup
################################################################################
# Add the configured library directories so that any transitive library lookup
# performed by DC resolves from the same centralized dependency configuration.
lappend search_path [file dirname $env(STD_CELL_DB)]
lappend search_path [file dirname $env(STD_CELL_MIN_DB)]
lappend search_path [file dirname $env(SRAM_DB)]
lappend search_path [file dirname $env(SRAM_MIN_DB)]
lappend search_path [file dirname $env(DW_FOUNDATION_DB)]

set STD_CELL_MAX_FILE [file tail $env(STD_CELL_DB)]
set STD_CELL_MIN_FILE [file tail $env(STD_CELL_MIN_DB)]
set SRAM_MAX_FILE [file tail $env(SRAM_DB)]
set SRAM_MIN_FILE [file tail $env(SRAM_MIN_DB)]

set STD_CELL_MAX_LIB [file rootname $STD_CELL_MAX_FILE]
set STD_CELL_MIN_LIB [file rootname $STD_CELL_MIN_FILE]

# set target library for standard cells
set_app_var target_library [list $env(STD_CELL_DB)]
# set synthetic library for IPs
set_app_var synthetic_library [list $env(DW_FOUNDATION_DB)]
# set link library for netlist analysis
# NOTE: 追加 RA1HD_4KB 硬核 .db (黑盒, dont_touch); 其 .v 不参与 analyze
set_app_var link_library [list * $env(STD_CELL_DB) $env(SRAM_DB) $env(DW_FOUNDATION_DB)]

# Pair every maximum-delay library with its minimum-delay counterpart.  The
# minimum libraries must be discoverable through search_path, but must not be
# placed in target_library or link_library.
set_min_library $STD_CELL_MAX_FILE -min_version $STD_CELL_MIN_FILE
set_min_library $SRAM_MAX_FILE -min_version $SRAM_MIN_FILE

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
if {![analyze -format sverilog ${RTL_SOURCE_FILES}]} {
    echo "FATAL: RTL analysis failed; synthesis has been stopped."
    exit 1
}

if {![elaborate ${DESIGN_NAME}]} {
    echo "FATAL: Failed to elaborate ${DESIGN_NAME}; synthesis has been stopped."
    exit 1
}

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
if {![link]} {
    echo "FATAL: Failed to link ${DESIGN_NAME}; synthesis has been stopped."
    exit 1
}

# One mapped design is optimized and timed at both extremes: maximum paths use
# the WC operating condition, while minimum paths use the BC condition.
set_operating_conditions \
    -analysis_type bc_wc \
    -max WCCOM -max_library $STD_CELL_MAX_LIB \
    -min BCCOM -min_library $STD_CELL_MIN_LIB

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

source -echo -verbose $env(SETUP_COMPILE_TCL)

# disable register merging
set_app_var compile_enable_register_merging false
print_variable_group compile

################################################################################
# compile
################################################################################

# compile
compile_ultra -no_autoungroup -no_seq_output_inversion

# Preserve a baseline so that the effect of the dedicated hold pass is visible.
update_timing
set pre_hold_prefix [file join ${log_path} "${DESIGN_NAME}.pre_hold_fix"]
report_qor > "${pre_hold_prefix}.qor.rpt"

echo "Setup timing before hold fixing" > "${pre_hold_prefix}.timing_setup.rpt"
report_timing -path end -delay max -max_path 10 -significant_digits 4 \
    >> "${pre_hold_prefix}.timing_setup.rpt"
echo "" >> "${pre_hold_prefix}.timing_setup.rpt"
report_timing -path full_clock -input_pins -nets -delay max -max_path 10 \
    -significant_digits 4 \
    >> "${pre_hold_prefix}.timing_setup.rpt"

echo "Hold timing before hold fixing" > "${pre_hold_prefix}.timing_hold.rpt"
report_timing -path end -delay min -max_path 10 -significant_digits 4 \
    >> "${pre_hold_prefix}.timing_hold.rpt"
echo "" >> "${pre_hold_prefix}.timing_hold.rpt"
report_timing -path full_clock -input_pins -nets -delay min -max_path 10 \
    -significant_digits 4 \
    >> "${pre_hold_prefix}.timing_hold.rpt"

if {$ENABLE_FIX_HOLD} {
    echo "INFO: Starting dedicated hold-only optimization."
    compile -only_hold_time
    update_timing
    report_qor > [file join ${log_path} "${DESIGN_NAME}.post_hold_fix.qor.rpt"]
    echo "INFO: Dedicated hold-only optimization completed."
} else {
    echo "INFO: Dedicated hold-only optimization skipped."
}

# The hold-only pass intentionally ignores other design rules and can leave
# transition, capacitance, and fanout violations.  Run a normal incremental
# mapping pass so setup, hold, and design-rule costs are optimized together.
if {$ENABLE_FIX_HOLD && $ENABLE_POST_HOLD_RECOVERY} {
    echo "INFO: Starting post-hold joint incremental optimization."
    compile -incremental_mapping
    update_timing
    echo "INFO: Post-hold joint incremental optimization completed."
} else {
    echo "INFO: Post-hold joint incremental optimization skipped."
}

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
source -echo -verbose [file join ${SCRIPT_DIR} report.tcl]

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
