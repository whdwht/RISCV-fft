##########################################################################################
# Version: M-2016.12-SP4 (July 17, 2017)
# Copyright (C) 2010-2017 Synopsys, Inc. All rights reserved.
##########################################################################################

source -echo [file join $::env(ICC_ROOT) rm_setup icc_setup.tcl]

#######################################
####Outputs Script
#######################################
# Wenxun: solve conflict
set target_library $TARGET_LIB
set link_library   $LINK_LIB
##Open Design
open_mw_cel $ICC_METAL_FILL_CEL -lib $MW_DESIGN_LIBRARY

# Replace implementation guardbands with the project signoff constraints
# before saving the output CEL and writing the SDC consumed by PrimeTime.
source -echo [file join $::env(ICC_ROOT) myscript icc_signoff_constraints.tcl]

# Wenxun: Add pin names to pins, Calibre in Virtuoso only recognize those text labels
# Here we do not need pad, since it is not chip-level
# source add_pad_text.tcl

##Change Names
change_names -rules verilog -hierarchy
save_mw_cel -as $ICC_OUTPUTS_CEL 
close_mw_cel
open_mw_cel $ICC_OUTPUTS_CEL


##Verilog
if {$ICC_WRITE_FULL_CHIP_VERILOG} {
write_verilog -diode_ports -no_physical_only_cells $RESULTS_DIR/$DESIGN_NAME.output.v -macro_definition

## For comparison with a Design Compiler netlist,the option -diode_ports is removed
write_verilog -no_physical_only_cells $RESULTS_DIR/$DESIGN_NAME.output.dc.v -macro_definition

## For LVS use,the option -no_physical_only_cells is removed
write_verilog -diode_ports -pg $RESULTS_DIR/$DESIGN_NAME.output.pg.lvs.v -macro_definition 

} else {
write_verilog -diode_ports -no_physical_only_cells $RESULTS_DIR/$DESIGN_NAME.output.v

## For comparison with a Design Compiler netlist,the option -diode_ports is removed
write_verilog -no_physical_only_cells $RESULTS_DIR/$DESIGN_NAME.output.dc.v
}

## For LVS use,the option -no_physical_only_cells is removed
# Wenxun: We used different options
# write_verilog -diode_ports -pg $RESULTS_DIR/$DESIGN_NAME.output.pg.lvs.v
write_verilog -pg -diode_ports -no_tap_cells -no_pad_filler_cells -no_core_filler_cells -output_net_name_for_tie -wire_declaration -force_no_output_references {TAPCELLBWP12T} $RESULTS_DIR/$DESIGN_NAME.output.pg.lvs.v
## Add -output_net_name_for_tie option to write_verilog command
#  if the verilog file is to be used by "eco_netlist -by_verilog_file" command in eco_icc task

## For Prime Time use,to include DCAP cells for leakage power analysis, add the option -force_output_references
#  if {$ICC_WRITE_FULL_CHIP_VERILOG} {
#  write_verilog -diode_ports -no_physical_only_cells -force_output_references [list of your DCAP cells] $RESULTS_DIR/$DESIGN_NAME.output.pt.v -macro_definition
#  } else {
#  write_verilog -diode_ports -no_physical_only_cells -force_output_references [list of your DCAP cells] $RESULTS_DIR/$DESIGN_NAME.output.pt.v
#  }

##SDC
set_app_var write_sdc_output_lumped_net_capacitance false
set_app_var write_sdc_output_net_resistance false

# Wenxun: We use different sdc version 
  write_sdc $RESULTS_DIR/$DESIGN_NAME.output.sdc
write_sdf $RESULTS_DIR/$DESIGN_NAME.output.sdf
#  write_sdc $RESULTS_DIR/$DESIGN_NAME.output.sdc -version 1.7
extract_rc -coupling_cap
write_parasitics  -format SPEF -output $RESULTS_DIR/$DESIGN_NAME.output.spef
#write_parasitics  -format SBPF -output $RESULTS_DIR/$DESIGN_NAME.output.sbpf

##DEF
write_def -output  $RESULTS_DIR/$DESIGN_NAME.output.def


###GDSII
##Set options - usually also include a mapping file (-map_layer)
# Wenxun: Output Stream file for cadence flow
  set_write_stream_options \
  -map_layer $MAP_LAYER_FILE \
  -child_depth 99 \
       -output_filling fill \
       -output_outdated_fill \
       -output_pin geometry 
#       -keep_data_type
   write_stream -lib_name $MW_DESIGN_LIBRARY -format gds $RESULTS_DIR/$DESIGN_NAME.gds

if {$ICC_CREATE_MODEL } {
  save_mw_cel -as $DESIGN_NAME
  close_mw_cel
  open_mw_cel $DESIGN_NAME

  source -echo common_optimization_settings_icc.tcl
  source -echo common_placement_settings_icc.tcl
  source -echo common_post_cts_timing_settings.tcl
  source -echo common_route_si_settings_zrt_icc.tcl

# Wenxun: figure out whether we need to set the FRAM view extraction manully
  create_macro_fram 

  if {$ICC_FIX_ANTENNA} {
  ##create Antenna Info
    extract_zrt_hier_antenna_property -cell_name $DESIGN_NAME
  }

  create_block_abstraction
  save_mw_cel
  close_mw_cel 
}
rm_abort_on_errors "outputs_icc"
exit
