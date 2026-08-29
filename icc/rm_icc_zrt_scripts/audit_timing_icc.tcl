##########################################################################################
# Version: M-2016.12-SP4 (July 17, 2017)
# Copyright (C) 2010-2017 Synopsys, Inc. All rights reserved.
##########################################################################################

source -echo [file join $::env(ICC_ROOT) rm_setup icc_setup.tcl]

####################################################################
## Fresh-session timing audit; does not save or modify any MW CEL  ##
####################################################################

open_mw_lib $MW_DESIGN_LIBRARY

# Only the accepted main-flow candidate is audited.  Experimental focal CELs
# are intentionally excluded because a clean main-flow run does not create
# them and they must never be rebuilt as an audit side effect.
foreach audit_cel [list $ICC_METAL_FILL_CEL] {
  open_mw_cel $audit_cel

  source -echo common_optimization_settings_icc.tcl
  source -echo common_placement_settings_icc.tcl
  source -echo common_post_cts_timing_settings.tcl
  source -echo common_route_si_settings_zrt_icc.tcl

  if {$POWER_OPTIMIZATION && $ICC_IN_SAIF_FILE != "" && [file exists [which $ICC_IN_SAIF_FILE]]} {
    read_saif -input $ICC_IN_SAIF_FILE -instance_name $ICC_SAIF_INSTANCE_NAME
  }

  update_timing
  set audit_prefix "audit_${audit_cel}"

  redirect -tee -file $REPORTS_DIR/$audit_prefix.qor {report_qor}
  redirect -tee -file $REPORTS_DIR/$audit_prefix.qor -append {report_qor -summary}
  redirect -file $REPORTS_DIR/$audit_prefix.con {report_constraints}
  redirect -file $REPORTS_DIR/$audit_prefix.max.tim {report_timing -nosplit -crosstalk_delta -capacitance -transition_time -input_pins -nets -delay max -max_paths 10 -significant_digits 4}
  redirect -file $REPORTS_DIR/$audit_prefix.min.tim {report_timing -nosplit -crosstalk_delta -capacitance -transition_time -input_pins -nets -delay min -max_paths 10 -significant_digits 4}
  if {$ICC_REPORTING_EFFORT == "MED" && $POWER_OPTIMIZATION} {
    redirect -file $REPORTS_DIR/$audit_prefix.power {report_power -nosplit}
  }

  rm_abort_on_errors "fresh-session audit of $audit_cel"
  close_mw_cel
}

exit
