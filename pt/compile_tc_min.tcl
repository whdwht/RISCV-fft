# TC/TT minimum-RC diagnostic STA and TC SDF.
if {![info exists env(PT_ROOT)] || $env(PT_ROOT) eq ""} {
  error "Required environment variable PT_ROOT is not set"
}
source [file join $env(PT_ROOT) common_setup.tcl]

pt_read_design_and_constraints tc
pt_read_parasitics $PT_SPEF_MIN tc_min
pt_run_sta_reports tc_min both
write_sdf -version 2.1 -context verilog my_tc_min.sdf

exit
