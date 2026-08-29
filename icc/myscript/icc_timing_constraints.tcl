# ICC timing constraints applied after the DDC has been imported.
#
# The DDC remains the source of the functional clock period.  Only setup and
# hold uncertainty are overridden here so DC may use a tighter optimization
# guardband without changing the final ICC acceptance constraint.

set icc_clock_name $::env(ICC_CLOCK_NAME)
set icc_setup_uncertainty $::env(ICC_SETUP_UNCERTAINTY)
set icc_hold_uncertainty $::env(ICC_HOLD_UNCERTAINTY)

foreach {icc_label icc_value} [list \
    ICC_SETUP_UNCERTAINTY $icc_setup_uncertainty \
    ICC_HOLD_UNCERTAINTY $icc_hold_uncertainty] {
  if {![string is double -strict $icc_value] || $icc_value < 0.0} {
    puts stderr "RM-Error: $icc_label must be a non-negative number, got '$icc_value'"
    exit 2
  }
}

set icc_clocks [get_clocks -quiet $icc_clock_name]
if {[sizeof_collection $icc_clocks] != 1} {
  puts stderr "RM-Error: expected exactly one ICC clock named '$icc_clock_name', found [sizeof_collection $icc_clocks]"
  exit 2
}

set_clock_uncertainty -setup $icc_setup_uncertainty $icc_clocks
set_clock_uncertainty -hold $icc_hold_uncertainty $icc_clocks

echo "RM-Info: ICC clock '$icc_clock_name' inherits its period from the DDC"
echo "RM-Info: ICC setup uncertainty = $icc_setup_uncertainty ns"
echo "RM-Info: ICC hold uncertainty  = $icc_hold_uncertainty ns"

unset icc_clock_name icc_setup_uncertainty icc_hold_uncertainty
unset icc_label icc_value icc_clocks
