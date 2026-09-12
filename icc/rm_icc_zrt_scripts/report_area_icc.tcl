##########################################################################################
# Read-only module and circuit-type area audit of the final implementation.
##########################################################################################

source -echo [file join $::env(ICC_ROOT) rm_setup icc_setup.tcl]

open_mw_lib -readonly $MW_DESIGN_LIBRARY
open_mw_cel -readonly $ICC_METAL_FILL_CEL

set area_prefix "area_${ICC_METAL_FILL_CEL}"
set hierarchy_report "$REPORTS_DIR/${area_prefix}.hier.rpt"

# The provenance marker lets the post-processor reject a report accidentally
# copied from synthesis or from another ICC stage.
redirect -file $hierarchy_report {
  echo "ICC_AREA_SOURCE_CEL $ICC_METAL_FILL_CEL"
}
redirect -file $hierarchy_report -append {
  report_area -hierarchy -nosplit
}
redirect -tee -file $REPORTS_DIR/${area_prefix}.qor {
  report_qor
}
redirect -tee -file $REPORTS_DIR/${area_prefix}.qor -append {
  report_qor -summary
}
redirect -tee -file $REPORTS_DIR/${area_prefix}.sum {
  report_design_physical -all -verbose
}

rm_abort_on_errors "read-only area audit of $ICC_METAL_FILL_CEL"
close_mw_cel
exit
