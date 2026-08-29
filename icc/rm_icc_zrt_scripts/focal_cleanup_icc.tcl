##########################################################################################
# Version: M-2016.12-SP4 (July 17, 2017)
# Copyright (C) 2010-2017 Synopsys, Inc. All rights reserved.
##########################################################################################

source -echo [file join $::env(ICC_ROOT) rm_setup icc_setup.tcl]

###################################################
## Final setup-only cleanup after focal_opt -power
###################################################

open_mw_lib $MW_DESIGN_LIBRARY
redirect /dev/null "remove_mw_cel -version_kept 0 ${ICC_FOCAL_CLEANUP_CEL}"
copy_mw_cel -from $ICC_FOCAL_CLEANUP_STARTING_CEL -to $ICC_FOCAL_CLEANUP_CEL
open_mw_cel $ICC_FOCAL_CLEANUP_CEL

source -echo common_optimization_settings_icc.tcl
source -echo common_placement_settings_icc.tcl
source -echo common_post_cts_timing_settings.tcl
source -echo common_route_si_settings_zrt_icc.tcl

set_optimization_strategy -tns_effort $ICC_TNS_EFFORT_POSTROUTE

# A standalone cleanup must not depend on activity annotations having been
# saved in its starting CEL.  SAIF remains optional for vectorless runs.
if {$POWER_OPTIMIZATION && $ICC_IN_SAIF_FILE != "" && [file exists [which $ICC_IN_SAIF_FILE]]} {
  read_saif -input $ICC_IN_SAIF_FILE -instance_name $ICC_SAIF_INSTANCE_NAME
}

# Only the remaining setup endpoints are touched.  Hold and broad DRC focal
# passes are deliberately omitted because they previously increased PPA and
# hold is already clean.
focal_opt -setup_endpoints all

save_mw_cel -as $ICC_FOCAL_CLEANUP_CEL

if {$ICC_REPORTING_EFFORT == "MED"} {
  redirect -tee -file $REPORTS_DIR_FOCAL_OPT/$ICC_FOCAL_CLEANUP_CEL.qor {report_qor}
  redirect -tee -file $REPORTS_DIR_FOCAL_OPT/$ICC_FOCAL_CLEANUP_CEL.qor -append {report_qor -summary}
  redirect -file $REPORTS_DIR_FOCAL_OPT/$ICC_FOCAL_CLEANUP_CEL.con {report_constraints}
}
if {$ICC_REPORTING_EFFORT == "MED" && $POWER_OPTIMIZATION} {
  redirect -file $REPORTS_DIR_FOCAL_OPT/$ICC_FOCAL_CLEANUP_CEL.power {report_power -nosplit}
}
if {$ICC_REPORTING_EFFORT != "OFF"} {
  redirect -tee -file $REPORTS_DIR_FOCAL_OPT/$ICC_FOCAL_CLEANUP_CEL.clock_tree {report_clock_tree -nosplit -summary}
  redirect -file $REPORTS_DIR_FOCAL_OPT/$ICC_FOCAL_CLEANUP_CEL.clock_timing {report_clock_timing -nosplit -type skew}
  redirect -file $REPORTS_DIR_FOCAL_OPT/$ICC_FOCAL_CLEANUP_CEL.max.tim {report_timing -nosplit -crosstalk_delta -capacitance -transition_time -input_pins -nets -delay max -max_paths 10 -significant_digits 4}
  redirect -file $REPORTS_DIR_FOCAL_OPT/$ICC_FOCAL_CLEANUP_CEL.min.tim {report_timing -nosplit -crosstalk_delta -capacitance -transition_time -input_pins -nets -delay min -max_paths 10 -significant_digits 4}
  redirect -tee -file $REPORTS_DIR_FOCAL_OPT/$ICC_FOCAL_CLEANUP_CEL.sum {report_design_physical -all -verbose}
  create_qor_snapshot -name $ICC_FOCAL_CLEANUP_CEL
  redirect -file $REPORTS_DIR_FOCAL_OPT/$ICC_FOCAL_CLEANUP_CEL.qor_snapshot.rpt {report_qor_snapshot -no_display}
}

rm_abort_on_errors "focal_cleanup_icc"
exit
