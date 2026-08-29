##########################################################################################
# Version: M-2016.12-SP4 (July 17, 2017)
# Copyright (C) 2010-2017 Synopsys, Inc. All rights reserved.
##########################################################################################

source -echo [file join $::env(ICC_ROOT) rm_setup icc_setup.tcl]
# Wenxun: solve conflict
set target_library $TARGET_LIB
set link_library   $LINK_LIB
open_mw_cel $ICC_METAL_FILL_CEL -lib $MW_DESIGN_LIBRARY

  ########################
  #     SIGNOFF DRC      #
  ########################
# Wenxun: Currently SIGNOFF_DRC_RUNSET == empty
if {[file exists [which $SIGNOFF_DRC_RUNSET]] } {

  set_physical_signoff_options -exec_cmd icv -drc_runset $SIGNOFF_DRC_RUNSET

  if {$SIGNOFF_MAPFILE != ""} {
    set_physical_signoff_options -mapfile [which $SIGNOFF_MAPFILE]
  }
  
  report_physical_signoff_options
  signoff_drc

}
      ## Auto DRC Repair (ADR)
      #  When routing DRC is within a reasonable range, you can perform ADR to resolve remaining DRC
      #  Please refer to SolvNet #031882 for more information and how to generate config file for signoff_autofix_drc command

      #  signoff_drc -run_dir {./signoff_drc_run} -ignore_child_cell_errors -read_cel_view 
      #  signoff_autofix_drc -incremental_level high -config_file $config_file -init_drc_error_db signoff_drc_run 
      #  save_mw_cel 
      #  signoff_drc -run_dir {./signoff_drc_run_after} -ignore_child_cell_errors -read_cel_view

rm_abort_on_errors "signoff_drc_icc"
exit
