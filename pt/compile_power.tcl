# TC/TT time-based PrimeTime PX analysis using the self-checking gate VCD.
if {![info exists env(PT_ROOT)] || $env(PT_ROOT) eq ""} {
  error "Required environment variable PT_ROOT is not set"
}
source [file join $env(PT_ROOT) common_setup.tcl]

pt_require_env {POWER_VCD POWER_WINDOW_FILE POWER_FFT_INSTANCE}

proc pt_read_power_window {window_file} {
  if {![file exists $window_file] || [file size $window_file] == 0} {
    error "Power-window metadata is missing or empty: $window_file"
  }

  array set value {}
  set channel [open $window_file r]
  set line_number 0
  while {[gets $channel line] >= 0} {
    incr line_number
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} {
      continue
    }
    if {![regexp {^([A-Z_]+)[ \t]+([-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?)$} \
        $line unused key number]} {
      close $channel
      error "Malformed power-window line $line_number: $line"
    }
    if {[info exists value($key)]} {
      close $channel
      error "Duplicate power-window key on line $line_number: $key"
    }
    if {[lsearch -exact {POWER_START_NS POWER_END_NS POWER_DURATION_NS POWER_CYCLES} \
        $key] < 0} {
      close $channel
      error "Unknown power-window key on line $line_number: $key"
    }
    set value($key) $number
  }
  close $channel

  foreach key {POWER_START_NS POWER_END_NS POWER_DURATION_NS POWER_CYCLES} {
    if {![info exists value($key)]} {
      error "Missing power-window key: $key"
    }
  }
  if {![regexp {^[1-9][0-9]*$} $value(POWER_CYCLES)]} {
    error "POWER_CYCLES must be a positive integer: $value(POWER_CYCLES)"
  }

  set start_ns [expr {double($value(POWER_START_NS))}]
  set end_ns [expr {double($value(POWER_END_NS))}]
  set duration_ns [expr {double($value(POWER_DURATION_NS))}]
  set cycles [expr {int($value(POWER_CYCLES))}]
  if {$start_ns < 0.0 || $end_ns <= $start_ns || $duration_ns <= 0.0} {
    error "Invalid power window: start=$start_ns end=$end_ns duration=$duration_ns"
  }
  if {[expr {abs(($end_ns - $start_ns) - $duration_ns)}] > 0.001} {
    error "Power-window duration does not equal end-start"
  }
  return [list $start_ns $end_ns $duration_ns $cycles]
}

foreach {power_start_ns power_end_ns power_duration_ns power_cycles} \
    [pt_read_power_window $env(POWER_WINDOW_FILE)] break

set_app_var power_enable_analysis true
set_app_var power_enable_timing_analysis true
set_app_var power_analysis_mode time_based

pt_read_design_and_constraints tc
pt_read_parasitics $PT_SPEF_MAX power

# Restrict analysis explicitly to the interval written by the same simulation
# that produced the VCD.  This prevents PT from averaging over time zero,
# reset, program loading, or a stale hand-written interval.
set power_time_window [list $power_start_ns $power_end_ns]
read_vcd $env(POWER_VCD) -strip_path tb_soc/x_soc \
  -time $power_time_window
report_switching_activity -list_not_annotated \
  > list_not_annotated_power.rpt

check_power > check_power.rpt
update_power

report_units -nosplit > power_units.rpt
report_power -verbose -nosplit -significant_digits 10 > power_vcd.rpt
report_power -hierarchy -nosplit -significant_digits 10 \
  > power_vcd_hier.rpt

set fft_cells [get_cells -quiet $env(POWER_FFT_INSTANCE)]
if {[sizeof_collection $fft_cells] != 1} {
  error "POWER_FFT_INSTANCE must select exactly one cell: $env(POWER_FFT_INSTANCE)"
}
current_instance $env(POWER_FFT_INSTANCE)
report_power -verbose -nosplit -significant_digits 10 > power_fft8.rpt
current_instance

set used_channel [open power_window_used.rpt w]
puts $used_channel "POWER_START_NS $power_start_ns"
puts $used_channel "POWER_END_NS $power_end_ns"
puts $used_channel "POWER_DURATION_NS $power_duration_ns"
puts $used_channel "POWER_CYCLES $power_cycles"
puts $used_channel "POWER_CORNER tc"
puts $used_channel "POWER_SPEF $PT_SPEF_MAX"
puts $used_channel "POWER_FFT_INSTANCE $env(POWER_FFT_INSTANCE)"
close $used_channel

exit
