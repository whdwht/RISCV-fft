puts "RM-Info: Running script [info script]\n"

##########################################################################################
# Variables common to all reference methodology scripts
# Script: common_setup.tcl
# Version: M-2016.12-SP4 (July 17, 2017)
# Copyright (C) 2010-2017 Synopsys, Inc. All rights reserved.
##########################################################################################

set DESIGN_NAME                   "soc_ahblite"  ;#  The name of the top-level design

set DESIGN_REF_DATA_PATH          "/home/master/project1/day3/fft"  ;#  Absolute path prefix variable for library/design data.
                                       ;#  Use this variable to prefix the common absolute path  
                                       #  to the common variables defined below.  
                                       #  Absolute paths are mandatory for hierarchical 
                                       #  reference methodology flow.
                                       # NOTE: 若项目整体拷贝到 day3 目录, 请同步修改此路径;
                                       #       并将综合网表 soc_ahblite.mapped.{ddc,v,sdc}
                                       #       拷入 $DESIGN_REF_DATA_PATH/flow/syn/output/

##########################################################################################
# Hierarchical Flow Design Variables
##########################################################################################

set HIERARCHICAL_DESIGNS           "" ;# List of hierarchical block design names "DesignA DesignB" ...
set HIERARCHICAL_CELLS             "" ;# List of hierarchical block cell instance names "u_DesignA u_DesignB" ...

##########################################################################################
# Library Setup Variables
##########################################################################################

# For the following variables, use a blank space to separate multiple entries.
# Example: set TARGET_LIBRARY_FILES "lib1.db lib2.db lib3.db"
# Include vg/ddc/.v/sdc file , include icc_script, include db for stdcell/sram
set ADDITIONAL_SEARCH_PATH        "$DESIGN_REF_DATA_PATH/flow/syn/output $DESIGN_REF_DATA_PATH/flow/common_scr $DESIGN_REF_DATA_PATH/flow/ICC/myscript/floorplan $DESIGN_REF_DATA_PATH/flow/ICC/myscript /mnt/hgfs/share/sram_hde/gen_hde /home/master/project1/day3/home/wangzb/lib1/TSMC65/tcbn65gplusbwp12t_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplusbwp12t_200a"  ;#  Additional search path to be added to the default search path
set TARGET_LIB			  "/home/master/project1/day3/home/wangzb/lib1/TSMC65/tcbn65gplusbwp12t_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplusbwp12t_200a/tcbn65gplusbwp12twc.db"
set LINK_LIB  			  " * /mnt/hgfs/share/sram_hde/gen_hde/RA1HD_4KB_ss_0p90v_0p90v_125c.db /home/master/project1/day3/home/wangzb/lib1/TSMC65/tcbn65gplusbwp12t_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplusbwp12t_200a/tcbn65gplusbwp12twc.db"
set TARGET_LIBRARY_FILES          "tcbn65gplusbwp12twc.db RA1HD_4KB_ss_0p90v_0p90v_125c.db"  ;#  Target technology logical libraries
set ADDITIONAL_LINK_LIB_FILES     ""  ;#  Extra link logical libraries not included in TARGET_LIBRARY_FILES

set MIN_LIBRARY_FILES             ""  ;#  List of max min library pairs "max1 min1 max2 min2 max3 min3"...
# include sram / TSMC Stdcell Milkyway library
set MW_REFERENCE_LIB_DIRS         "/mnt/hgfs/share/sram_hde/sramlib_4k /home/master/project1/day3/home/wangzb/lib1/TSMC65/tcbn65gplusbwp12t_200a/TSMCHOME/digital/Back_End/milkyway/tcbn65gplusbwp12t_200a/cell_frame/tcbn65gplusbwp12t"  ;#  Milkyway reference libraries 

set MW_REFERENCE_CONTROL_FILE     ""  ;#  Reference Control file to define the Milkyway reference libs

set BACKEND_PATH                  "/home/master/project1/day3/home/wangzb/lib1/TSMC65/tcbn65gplusbwp12t_200a/TSMCHOME/digital/Back_End/milkyway/tcbn65gplusbwp12t_200a/cell_frame/tcbn65gplusbwp12t"

set TECH_FILE                     "/home/master/project1/day3/home/wangzb/lib1/TSMC65/techfiles/tsmcn65_9lmT2.tf"  ;#  Milkyway technology file
set MAP_FILE                      "/home/master/project1/day3/home/wangzb/lib1/TSMC65/techfiles/tluplus/tluplus.map"  ;#  Mapping file for TLUplus
set TLUPLUS_MAX_FILE              "/home/master/project1/day3/home/wangzb/lib1/TSMC65/techfiles/tluplus/cln65g+_1p09m+alrdl_cbest_top2.tluplus"  ;#  Max TLUplus file
set TLUPLUS_MIN_FILE              "/home/master/project1/day3/home/wangzb/lib1/TSMC65/techfiles/tluplus/cln65g+_1p09m+alrdl_cworst_top2.tluplus"  ;#  Min TLUplus file

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

puts "RM-Info: Completed script [info script]\n"
