# BC/FF minimum-RC signoff STA and minimum-delay SDF.
if {![info exists env(PT_ROOT)] || $env(PT_ROOT) eq ""} {
  error "Required environment variable PT_ROOT is not set"
}
source [file join $env(PT_ROOT) common_setup.tcl]

pt_read_design_and_constraints bc
pt_read_parasitics $PT_SPEF_MIN bc_min
pt_run_sta_reports bc_min hold
write_sdf -version 2.1 -context verilog my_bc_min.sdf

exit
