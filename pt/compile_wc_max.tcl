# WC/SS maximum-RC signoff STA and maximum-delay SDF.
if {![info exists env(PT_ROOT)] || $env(PT_ROOT) eq ""} {
  error "Required environment variable PT_ROOT is not set"
}
source [file join $env(PT_ROOT) common_setup.tcl]

pt_read_design_and_constraints wc
pt_read_parasitics $PT_SPEF_MAX wc_max
pt_run_sta_reports wc_max setup
write_sdf -version 2.1 -context verilog my_wc_max.sdf

exit
