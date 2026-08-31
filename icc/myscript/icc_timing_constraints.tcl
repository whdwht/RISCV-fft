# ICC timing constraints applied after the DDC has been imported.
#
# The DDC remains the source of the functional clock period. Timing margins,
# reset removal guardband, and electrical implementation limits are applied
# here; outputs_icc restores the project signoff values before handoff.

set icc_clock_name $::env(ICC_CLOCK_NAME)
set icc_setup_uncertainty $::env(ICC_SETUP_UNCERTAINTY)
set icc_hold_uncertainty $::env(ICC_HOLD_UNCERTAINTY)
set icc_reset_release_min $::env(ICC_RESET_RELEASE_MIN)
set icc_reset_release_max $::env(ICC_RESET_RELEASE_MAX)
set icc_opt_reset_release_min $::env(ICC_OPT_RESET_RELEASE_MIN)
set icc_max_fanout $::env(ICC_MAX_FANOUT)
set icc_max_transition $::env(ICC_MAX_TRANSITION)
set icc_max_capacitance $::env(ICC_MAX_CAPACITANCE)
set icc_opt_max_transition $::env(ICC_OPT_MAX_TRANSITION)
set icc_opt_max_capacitance $::env(ICC_OPT_MAX_CAPACITANCE)
set icc_opt_sram_data_max_transition \
  $::env(ICC_OPT_SRAM_DATA_MAX_TRANSITION)

foreach {icc_label icc_value} [list \
    ICC_SETUP_UNCERTAINTY $icc_setup_uncertainty \
    ICC_HOLD_UNCERTAINTY $icc_hold_uncertainty \
    ICC_RESET_RELEASE_MIN $icc_reset_release_min \
    ICC_RESET_RELEASE_MAX $icc_reset_release_max \
    ICC_OPT_RESET_RELEASE_MIN $icc_opt_reset_release_min \
    ICC_MAX_FANOUT $icc_max_fanout \
    ICC_MAX_TRANSITION $icc_max_transition \
    ICC_MAX_CAPACITANCE $icc_max_capacitance \
    ICC_OPT_MAX_TRANSITION $icc_opt_max_transition \
    ICC_OPT_MAX_CAPACITANCE $icc_opt_max_capacitance \
    ICC_OPT_SRAM_DATA_MAX_TRANSITION \
      $icc_opt_sram_data_max_transition] {
  if {![string is double -strict $icc_value] || $icc_value < 0.0} {
    puts stderr "RM-Error: $icc_label must be a non-negative number, got '$icc_value'"
    exit 2
  }
}
if {$icc_reset_release_min > $icc_reset_release_max} {
  puts stderr "RM-Error: ICC_RESET_RELEASE_MIN must not exceed ICC_RESET_RELEASE_MAX"
  exit 2
}
if {$icc_opt_reset_release_min > $icc_reset_release_min} {
  puts stderr "RM-Error: ICC_OPT_RESET_RELEASE_MIN must not exceed ICC_RESET_RELEASE_MIN"
  exit 2
}
if {$icc_opt_max_transition > $icc_max_transition} {
  puts stderr "RM-Error: ICC_OPT_MAX_TRANSITION must not exceed ICC_MAX_TRANSITION"
  exit 2
}
if {$icc_opt_max_capacitance > $icc_max_capacitance} {
  puts stderr "RM-Error: ICC_OPT_MAX_CAPACITANCE must not exceed ICC_MAX_CAPACITANCE"
  exit 2
}
if {$icc_opt_sram_data_max_transition > $icc_opt_max_transition} {
  puts stderr "RM-Error: ICC_OPT_SRAM_DATA_MAX_TRANSITION must not exceed ICC_OPT_MAX_TRANSITION"
  exit 2
}

set icc_clocks [get_clocks -quiet $icc_clock_name]
if {[sizeof_collection $icc_clocks] != 1} {
  puts stderr "RM-Error: expected exactly one ICC clock named '$icc_clock_name', found [sizeof_collection $icc_clocks]"
  exit 2
}

set_clock_uncertainty -setup $icc_setup_uncertainty $icc_clocks
set_clock_uncertainty -hold $icc_hold_uncertainty $icc_clocks

set icc_reset_ports [get_ports -quiet rstn]
if {[sizeof_collection $icc_reset_ports] != 1} {
  puts stderr "RM-Error: expected exactly one ICC reset port named 'rstn', found [sizeof_collection $icc_reset_ports]"
  exit 2
}

# Replace the DDC-carried input delay. The earlier implementation value creates
# removal margin in the physical reset tree; outputs_icc restores the signoff
# value before writing SDC. Assertion remains asynchronous through the
# falling-edge false path carried by the DDC.
remove_input_delay $icc_reset_ports
set_input_delay -clock $icc_clocks -rise -min \
  $icc_opt_reset_release_min $icc_reset_ports
set_input_delay -clock $icc_clocks -rise -max \
  $icc_reset_release_max $icc_reset_ports

set_max_fanout $icc_max_fanout [current_design]
set_max_transition $icc_opt_max_transition [current_design]
set_max_capacitance $icc_opt_max_capacitance [current_design]

# PrimeTime/SPEF reported a larger slew specifically at the data SRAM write
# interface than ICC's in-design extraction. Tighten all 32 macro D pins so
# route_opt sees and repairs that correlation margin locally.
set icc_data_sram_d_pins \
  [get_pins -quiet {x_data_sram/i_sram_block/D*}]
if {[sizeof_collection $icc_data_sram_d_pins] != 32} {
  puts stderr "RM-Error: expected 32 data SRAM D pins, found [sizeof_collection $icc_data_sram_d_pins]"
  exit 2
}
set_max_transition $icc_opt_sram_data_max_transition \
  $icc_data_sram_d_pins

echo "RM-Info: ICC clock '$icc_clock_name' inherits its period from the DDC"
echo "RM-Info: ICC setup uncertainty = $icc_setup_uncertainty ns"
echo "RM-Info: ICC hold uncertainty  = $icc_hold_uncertainty ns"
echo "RM-Info: ICC reset release tCO = $icc_opt_reset_release_min / $icc_reset_release_max ns (implementation min/max)"
echo "RM-Info: ICC reset signoff min  = $icc_reset_release_min ns"
echo "RM-Info: ICC max fanout         = $icc_max_fanout"
echo "RM-Info: ICC max transition     = $icc_opt_max_transition ns (implementation), $icc_max_transition ns (signoff)"
echo "RM-Info: ICC max capacitance    = $icc_opt_max_capacitance pF (implementation), $icc_max_capacitance pF (signoff)"
echo "RM-Info: ICC data SRAM D slew   = $icc_opt_sram_data_max_transition ns (implementation)"

unset icc_clock_name icc_setup_uncertainty icc_hold_uncertainty
unset icc_reset_release_min icc_reset_release_max icc_opt_reset_release_min
unset icc_max_fanout icc_max_transition icc_max_capacitance
unset icc_opt_max_transition icc_opt_max_capacitance
unset icc_opt_sram_data_max_transition
unset icc_label icc_value icc_clocks icc_reset_ports icc_data_sram_d_pins
