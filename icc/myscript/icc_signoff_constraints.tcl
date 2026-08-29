# Restore project-level signoff constraints after physical optimization.

set icc_signoff_clocks [get_clocks -quiet $::env(ICC_CLOCK_NAME)]
if {[sizeof_collection $icc_signoff_clocks] != 1} {
  puts stderr "RM-Error: expected exactly one signoff clock named '$::env(ICC_CLOCK_NAME)', found [sizeof_collection $icc_signoff_clocks]"
  exit 2
}

set icc_signoff_reset_ports [get_ports -quiet rstn]
if {[sizeof_collection $icc_signoff_reset_ports] != 1} {
  puts stderr "RM-Error: expected exactly one signoff reset port named 'rstn', found [sizeof_collection $icc_signoff_reset_ports]"
  exit 2
}

set icc_signoff_data_sram_d_pins \
  [get_pins -quiet {x_data_sram/i_sram_block/D*}]
if {[sizeof_collection $icc_signoff_data_sram_d_pins] != 32} {
  puts stderr "RM-Error: expected 32 signoff data SRAM D pins, found [sizeof_collection $icc_signoff_data_sram_d_pins]"
  exit 2
}

remove_input_delay $icc_signoff_reset_ports
set_input_delay -clock $icc_signoff_clocks -rise -min \
  $::env(ICC_RESET_RELEASE_MIN) $icc_signoff_reset_ports
set_input_delay -clock $icc_signoff_clocks -rise -max \
  $::env(ICC_RESET_RELEASE_MAX) $icc_signoff_reset_ports

# Remove the stricter design-level implementation attributes first; otherwise
# some Synopsys releases retain the tighter value when a looser value is set.
# Library pin limits are separate attributes and remain active.
remove_max_fanout [current_design]
remove_max_transition [current_design]
remove_max_transition $icc_signoff_data_sram_d_pins
remove_max_capacitance [current_design]
set_max_fanout $::env(ICC_MAX_FANOUT) [current_design]
set_max_transition $::env(ICC_MAX_TRANSITION) [current_design]
set_max_capacitance $::env(ICC_MAX_CAPACITANCE) [current_design]

echo "RM-Info: restored signoff reset release tCO = $::env(ICC_RESET_RELEASE_MIN) / $::env(ICC_RESET_RELEASE_MAX) ns (min/max)"
echo "RM-Info: restored signoff max fanout         = $::env(ICC_MAX_FANOUT)"
echo "RM-Info: restored signoff max transition     = $::env(ICC_MAX_TRANSITION) ns"
echo "RM-Info: restored signoff max capacitance    = $::env(ICC_MAX_CAPACITANCE) pF"

unset icc_signoff_clocks icc_signoff_reset_ports
unset icc_signoff_data_sram_d_pins
