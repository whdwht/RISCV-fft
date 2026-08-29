puts "RM-Info: Running script [info script]\n"

##########################################################################################
# Variables common to all reference methodology scripts
# Script: common_setup.tcl
# Version: M-2016.12-SP4 (July 17, 2017)
# Copyright (C) 2010-2017 Synopsys, Inc. All rights reserved.
##########################################################################################

set DESIGN_NAME                   "soc_ahblite"  ;#  The name of the top-level design

set REQUIRED_ENV_VARS {
  PROJECT_ROOT ICC_ROOT
  STD_CELL_DB STD_CELL_MIN_DB SRAM_DB SRAM_MIN_DB
  STD_CELL_MW_LIB SRAM_MW_LIB TECH_FILE TLUPLUS_MAP_FILE
  TLUPLUS_MAX_FILE TLUPLUS_MIN_FILE ANTENNA_RULES_TCL GDS_LAYER_MAP
  ICC_CLOCK_NAME ICC_SETUP_UNCERTAINTY ICC_HOLD_UNCERTAINTY
  ICC_ROUTE_OPT_AREA_RECOVERY
}
foreach env_var $REQUIRED_ENV_VARS {
  if {![info exists ::env($env_var)] || $::env($env_var) == ""} {
    puts stderr "RM-Error: environment variable $env_var is not set. Source icc/dependencies.sh first."
    exit 2
  }
}

set PROJECT_ROOT                  [file normalize $::env(PROJECT_ROOT)]
set ICC_ROOT                      [file normalize $::env(ICC_ROOT)]
set DESIGN_REF_DATA_PATH          $PROJECT_ROOT

##########################################################################################
# Hierarchical Flow Design Variables
##########################################################################################

set HIERARCHICAL_DESIGNS           "" ;# List of hierarchical block design names "DesignA DesignB" ...
set HIERARCHICAL_CELLS             "" ;# List of hierarchical block cell instance names "u_DesignA u_DesignB" ...

##########################################################################################
# Library Setup Variables
##########################################################################################

# Keep the WC standard-cell library as the optimization target.  SRAM is a
# linked macro, with explicit WC/BC and SS/FF min-library relationships.
set ADDITIONAL_SEARCH_PATH        [list \
  "$PROJECT_ROOT/syn_rtl" \
  "$PROJECT_ROOT/sdc" \
  "$ICC_ROOT/rm_icc_scripts" \
  "$ICC_ROOT/rm_icc_zrt_scripts" \
  "$ICC_ROOT/myscript" \
  "$ICC_ROOT/myscript/floorplan" \
  [file dirname $::env(STD_CELL_DB)] \
  [file dirname $::env(SRAM_DB)]]
set TARGET_LIB                    $::env(STD_CELL_DB)
set LINK_LIB                      [list * $::env(STD_CELL_DB) $::env(SRAM_DB)]
set TARGET_LIBRARY_FILES          [list $::env(STD_CELL_DB)]
set ADDITIONAL_LINK_LIB_FILES     [list $::env(SRAM_DB)]

set MIN_LIBRARY_FILES             [list \
  $::env(STD_CELL_DB) $::env(STD_CELL_MIN_DB) \
  $::env(SRAM_DB) $::env(SRAM_MIN_DB)]
set MW_REFERENCE_LIB_DIRS         [list $::env(STD_CELL_MW_LIB) $::env(SRAM_MW_LIB)]

set MW_REFERENCE_CONTROL_FILE     ""  ;#  Reference Control file to define the Milkyway reference libs

set BACKEND_PATH                  $::env(STD_CELL_MW_LIB)

set TECH_FILE                     $::env(TECH_FILE)
set MAP_FILE                      $::env(TLUPLUS_MAP_FILE)
set TLUPLUS_MAX_FILE              $::env(TLUPLUS_MAX_FILE)
set TLUPLUS_MIN_FILE              $::env(TLUPLUS_MIN_FILE)

set MIN_ROUTING_LAYER            ""   ;# Min routing layer
set MAX_ROUTING_LAYER            "M9"   ;# Max routing layer

set LIBRARY_DONT_USE_FILE        ""   ;# Tcl file with library modifications for dont_use

##########################################################################################
# Multivoltage Common Variables
#
# Define the following multivoltage common variables for the reference methodology scripts 
# for multivoltage flows. 
# Use as few or as many of the following definitions as needed by your design.
##########################################################################################

set PD1                          ""           ;# Name of power domain/voltage area  1
set VA1_COORDINATES              {}           ;# Coordinates for voltage area 1
set MW_POWER_NET1                "VDD1"       ;# Power net for voltage area 1

set PD2                          ""           ;# Name of power domain/voltage area  2
set VA2_COORDINATES              {}           ;# Coordinates for voltage area 2
set MW_POWER_NET2                "VDD2"       ;# Power net for voltage area 2

set PD3                          ""           ;# Name of power domain/voltage area  3
set VA3_COORDINATES              {}           ;# Coordinates for voltage area 3
set MW_POWER_NET3                "VDD3"       ;# Power net for voltage area 3

set PD4                          ""           ;# Name of power domain/voltage area  4
set VA4_COORDINATES              {}           ;# Coordinates for voltage area 4
set MW_POWER_NET4                "VDD4"       ;# Power net for voltage area 4

# The synthesized netlist and every customized PG script use these names.
set MW_POWER_NET                 "VDD_SOC"
set MW_POWER_PORT                "VDD_SOC"
set MW_GROUND_NET                "GND_SOC"
set MW_GROUND_PORT               "GND_SOC"

puts "RM-Info: Completed script [info script]\n"
