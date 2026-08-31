# Shared setup/report procedures for PrimeTime O-2018.06-SP1.

proc pt_require_env {names} {
  global env
  foreach name $names {
    if {![info exists env($name)] || $env($name) eq ""} {
      error "Required environment variable $name is not set"
    }
  }
}

proc pt_read_sdc_without_operating_conditions {source_sdc} {
  # ICC writes the operating condition into the handoff SDC.  It is the only
  # corner-specific constraint, so remove that logical Tcl command and apply
  # the requested PT corner explicitly after all other constraints are read.
  set input_file [open $source_sdc r]
  set filtered_sdc constraints_no_operating_conditions.sdc
  set output_file [open $filtered_sdc w]
  set command_buffer ""

  while {[gets $input_file line] >= 0} {
    append command_buffer $line "\n"
    if {[info complete $command_buffer]} {
      set trimmed_command [string trimleft $command_buffer]
      if {![string match "set_operating_conditions*" $trimmed_command]} {
        puts -nonewline $output_file $command_buffer
      }
      set command_buffer ""
    }
  }
  close $input_file
  close $output_file

  if {$command_buffer ne ""} {
    error "Incomplete Tcl command at end of $source_sdc"
  }
  read_sdc $filtered_sdc
}

pt_require_env {
  DESIGN_NAME PT_DATA_DIR
  STD_CELL_WC_DB STD_CELL_TC_DB STD_CELL_BC_DB
  SRAM_WC_DB SRAM_TC_DB SRAM_BC_DB
}

set DESIGN_NAME $env(DESIGN_NAME)
set PT_NETLIST   [file join $env(PT_DATA_DIR) "${DESIGN_NAME}.output.v"]
set PT_SDC       [file join $env(PT_DATA_DIR) "${DESIGN_NAME}.output.sdc"]
set PT_SPEF_MAX  [file join $env(PT_DATA_DIR) "${DESIGN_NAME}.output.spef.max"]
set PT_SPEF_MIN  [file join $env(PT_DATA_DIR) "${DESIGN_NAME}.output.spef.min"]

set_app_var sh_continue_on_error false
set library_search_path {}
foreach library_variable {
  STD_CELL_WC_DB STD_CELL_TC_DB STD_CELL_BC_DB
  SRAM_WC_DB SRAM_TC_DB SRAM_BC_DB
} {
  lappend library_search_path [file dirname $env($library_variable)]
}
set_app_var search_path \
  [concat [get_app_var search_path] $library_search_path]

# The provided standard-cell and SRAM databases use NLDM timing models. Keep
# PrimeTime's compatible default delay calculation and use graph-based reports;
# regular PBA is not supported in the independent single-corner sessions.
set_app_var read_parasitics_load_locations true

proc pt_read_design_and_constraints {corner_mode} {
  global env DESIGN_NAME PT_NETLIST PT_SDC

  switch -exact -- $corner_mode {
    wc {
      set standard_cell_db $env(STD_CELL_WC_DB)
      set sram_db $env(SRAM_WC_DB)
      set operating_condition WCCOM
    }
    tc {
      set standard_cell_db $env(STD_CELL_TC_DB)
      set sram_db $env(SRAM_TC_DB)
      set operating_condition NCCOM
    }
    bc {
      set standard_cell_db $env(STD_CELL_BC_DB)
      set sram_db $env(SRAM_BC_DB)
      set operating_condition BCCOM
    }
    default {
      error "Unsupported PrimeTime corner mode: $corner_mode"
    }
  }

  set_app_var target_library [list $standard_cell_db $sram_db]
  set_app_var link_library [list * $standard_cell_db $sram_db]

  read_verilog $PT_NETLIST
  current_design $DESIGN_NAME
  if {![link]} {
    error "Failed to link $DESIGN_NAME"
  }
  pt_read_sdc_without_operating_conditions $PT_SDC

  set standard_cell_library [file rootname [file tail $standard_cell_db]]
  set_operating_conditions -analysis_type single \
    -library $standard_cell_library $operating_condition
}

proc pt_read_parasitics {spef_file tag} {
  read_parasitics -format spef $spef_file
  report_annotated_parasitics -internal_nets -list_not_annotated \
    -max_nets 320 -constant_arcs > "annotated_parasitics_${tag}.rpt"
}

proc pt_write_timing_status {tag required_checks} {
  if {$required_checks ni {setup hold both}} {
    error "Unsupported required timing checks: $required_checks"
  }

  set worst_setup [get_timing_paths -delay_type max -max_paths 1]
  set worst_hold [get_timing_paths -delay_type min -max_paths 1]
  set setup_paths [get_timing_paths -delay_type max \
    -slack_lesser_than 0.0 -max_paths 1]
  set hold_paths [get_timing_paths -delay_type min \
    -slack_lesser_than 0.0 -max_paths 1]
  set setup_count [sizeof_collection $setup_paths]
  set hold_count [sizeof_collection $hold_paths]

  set status_file [open "timing_status_${tag}.rpt" w]
  puts $status_file "PT_REQUIRED_CHECKS $required_checks"
  if {[sizeof_collection $worst_setup] > 0} {
    puts $status_file "PT_SETUP_WNS [get_attribute $worst_setup slack]"
  }
  if {[sizeof_collection $worst_hold] > 0} {
    puts $status_file "PT_HOLD_WNS [get_attribute $worst_hold slack]"
  }
  puts $status_file "PT_SETUP_VIOLATING_PATHS $setup_count"
  puts $status_file "PT_HOLD_VIOLATING_PATHS $hold_count"

  set required_violation_count 0
  if {$required_checks in {setup both}} {
    incr required_violation_count $setup_count
  }
  if {$required_checks in {hold both}} {
    incr required_violation_count $hold_count
  }
  if {$required_violation_count == 0} {
    puts $status_file "PT_RESULT PASS"
  } else {
    puts $status_file "PT_RESULT FAIL"
  }
  close $status_file
}

proc pt_run_sta_reports {tag required_checks} {
  update_timing -full

  check_constraints -verbose > "check_constraints_${tag}.rpt"
  check_timing -verbose > "check_timing_${tag}.rpt"
  report_analysis_coverage > "analysis_coverage_${tag}.rpt"
  report_constraint -all_violators -verbose > "constraint_violators_${tag}.rpt"
  report_clock > "clock_${tag}.rpt"
  report_exceptions > "exceptions_${tag}.rpt"
  report_case_analysis > "case_analysis_${tag}.rpt"
  report_disable_timing > "disabled_timing_${tag}.rpt"
  report_global_timing > "global_timing_${tag}.rpt"

  report_timing -delay_type max -max_paths 50 -nworst 2 \
    -input_pins -nets -transition_time -capacitance \
    -significant_digits 4 > "setup_gba_${tag}.rpt"
  report_timing -delay_type min -max_paths 50 -nworst 2 \
    -input_pins -nets -transition_time -capacitance \
    -significant_digits 4 > "hold_gba_${tag}.rpt"
  report_timing -delay_type max -slack_lesser_than 0.0 \
    -max_paths 200 -significant_digits 4 > "setup_violations_${tag}.rpt"
  report_timing -delay_type min -slack_lesser_than 0.0 \
    -max_paths 200 -significant_digits 4 > "hold_violations_${tag}.rpt"

  pt_write_timing_status $tag $required_checks
}
