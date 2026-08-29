# This script creates focused reports instead of one large mixed report.

set maxpaths 10
set report_prefix [file join ${log_path} ${DESIGN_NAME}]

set summary_report       [file join ${log_path} ${rpt_file}]
set check_design_report  "${report_prefix}.check_design.rpt"
set check_timing_report  "${report_prefix}.check_timing.rpt"
set area_report          "${report_prefix}.area.rpt"
set setup_timing_report  "${report_prefix}.timing_setup.rpt"
set hold_timing_report   "${report_prefix}.timing_hold.rpt"
set constraints_report   "${report_prefix}.constraints.rpt"
set clocks_report        "${report_prefix}.clocks.rpt"
set design_report        "${report_prefix}.design.rpt"
set objects_report       "${report_prefix}.objects.rpt"

################################################################################
# Summary and report index
################################################################################
report_qor > "${summary_report}"
echo "" >> "${summary_report}"
echo "Detailed reports:" >> "${summary_report}"
foreach detail_report [list \
    ${check_design_report} \
    ${check_timing_report} \
    ${area_report} \
    ${setup_timing_report} \
    ${hold_timing_report} \
    ${constraints_report} \
    ${clocks_report} \
    ${design_report} \
    ${objects_report}] {
    echo "  [file tail ${detail_report}]" >> "${summary_report}"
}

################################################################################
# Design checks: all warnings are intentionally preserved here.
################################################################################
check_design > "${check_design_report}"
check_timing > "${check_timing_report}"

################################################################################
# Area
################################################################################
report_area -hierarchy > "${area_report}"

################################################################################
# Setup (maximum-delay) timing
################################################################################
echo "Setup timing endpoint summary" > "${setup_timing_report}"
report_timing -path end -delay max -max_path $maxpaths -significant_digits 4 \
    >> "${setup_timing_report}"
echo "" >> "${setup_timing_report}"
echo "Setup timing full-clock paths" >> "${setup_timing_report}"
report_timing -path full_clock -input_pins -nets -max_path $maxpaths -delay max \
    -significant_digits 4 >> "${setup_timing_report}"

################################################################################
# Hold (minimum-delay) timing
################################################################################
echo "Hold timing endpoint summary" > "${hold_timing_report}"
report_timing -path end -delay min -max_path $maxpaths -significant_digits 4 \
    >> "${hold_timing_report}"
echo "" >> "${hold_timing_report}"
echo "Hold timing full-clock paths" >> "${hold_timing_report}"
report_timing -path full_clock -input_pins -nets -max_path $maxpaths -delay min \
    -significant_digits 4 >> "${hold_timing_report}"

################################################################################
# Constraints and timing requirements
################################################################################
report_constraint -all_violators -verbose > "${constraints_report}"
report_timing_requirements >> "${constraints_report}"

################################################################################
# Clocks
################################################################################
report_clock > "${clocks_report}"

################################################################################
# Design and compile configuration
################################################################################
report_design > "${design_report}"
report_compile_options >> "${design_report}"

################################################################################
# Detailed design objects
################################################################################
report_cell > "${objects_report}"
report_reference >> "${objects_report}"
report_port -verbose >> "${objects_report}"
report_isolate_ports >> "${objects_report}"
report_net >> "${objects_report}"
