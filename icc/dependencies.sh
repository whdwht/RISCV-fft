#!/usr/bin/env bash

# Centralized, overridable external dependencies for the ICC flow.
# Source this file before invoking ICC/Milkyway, or let the Makefile do it.

_icc_dependencies_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

export ICC_ROOT="${ICC_ROOT:-${_icc_dependencies_dir}}"
export PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${ICC_ROOT}/.." && pwd -P)}"

export ICC_SHELL_BIN="${ICC_SHELL_BIN:-/export/SoftWare/Synopsys/icc/O-2018.06-SP1/bin/icc_shell}"
export MILKYWAY_BIN="${MILKYWAY_BIN:-/export/SoftWare/Synopsys/mw/O-2018.06-SP5-1/bin/Milkyway}"

# Timing constraints applied after a DDC import and before floorplan creation.
# The clock period itself remains the functional period carried by the DDC.
export ICC_CLOCK_NAME="${ICC_CLOCK_NAME:-clk1}"
export ICC_SETUP_UNCERTAINTY="${ICC_SETUP_UNCERTAINTY:-0.20}"
export ICC_HOLD_UNCERTAINTY="${ICC_HOLD_UNCERTAINTY:-0.05}"

# Preserve timing margin during the initial post-route optimization.  Set this
# to TRUE only for an explicit area-recovery/PPA comparison after timing closes.
export ICC_ROUTE_OPT_AREA_RECOVERY="${ICC_ROUTE_OPT_AREA_RECOVERY:-FALSE}"

# Optional activity data for power-aware optimization.  Keep the SAIF path
# empty by default so a stale or unrelated activity file is never consumed
# silently.  Use an absolute path when overriding ICC_SAIF_FILE.
export ICC_SAIF_FILE="${ICC_SAIF_FILE:-}"
export ICC_SAIF_INSTANCE_NAME="${ICC_SAIF_INSTANCE_NAME:-soc_ahblite}"
export ICC_TOTAL_POWER_STRATEGY_EFFORT="${ICC_TOTAL_POWER_STRATEGY_EFFORT:-none}"

_tsmc65_root=/home/master/project/3_PR/home/wangzb/lib1/TSMC65
_stdcell_root=${_tsmc65_root}/tcbn65gplusbwp12t_200a/TSMCHOME
_stdcell_nldm=${_stdcell_root}/digital/Front_End/timing_power_noise/NLDM/tcbn65gplusbwp12t_200a
_stdcell_mw=${_stdcell_root}/digital/Back_End/milkyway/tcbn65gplusbwp12t_200a
_dc_stdcell_nldm=/home/master/project/2_dc/day2/library
_sram_root=/home/master/project/3_PR/sram_hde

# Keep the logical standard-cell library path identical to the one embedded in
# the synthesis DDC. ICC treats the same logical library loaded from two paths
# as a conflict even when the DB files are byte-for-byte identical.
export STD_CELL_DB="${STD_CELL_DB:-${_dc_stdcell_nldm}/tcbn65gplusbwp12twc.db}"
export STD_CELL_MIN_DB="${STD_CELL_MIN_DB:-${_dc_stdcell_nldm}/tcbn65gplusbwp12tbc.db}"
export SRAM_DB="${SRAM_DB:-${_sram_root}/gen_hde/RA1HD_4KB_ss_0p90v_0p90v_125c.db}"
export SRAM_MIN_DB="${SRAM_MIN_DB:-${_sram_root}/gen_hde/RA1HD_4KB_ff_1p10v_1p10v_0c.db}"

export STD_CELL_MW_LIB="${STD_CELL_MW_LIB:-${_stdcell_mw}/cell_frame/tcbn65gplusbwp12t}"
export SRAM_MW_LIB="${SRAM_MW_LIB:-${_sram_root}/sramlib_4k}"

export TECH_FILE="${TECH_FILE:-${_tsmc65_root}/techfiles/tsmcn65_9lmT2.tf}"
export TLUPLUS_MAP_FILE="${TLUPLUS_MAP_FILE:-${_tsmc65_root}/techfiles/tluplus/tluplus.map}"
export TLUPLUS_MAX_FILE="${TLUPLUS_MAX_FILE:-${_tsmc65_root}/techfiles/tluplus/cln65g+_1p09m+alrdl_cworst_top2.tluplus}"
export TLUPLUS_MIN_FILE="${TLUPLUS_MIN_FILE:-${_tsmc65_root}/techfiles/tluplus/cln65g+_1p09m+alrdl_cbest_top2.tluplus}"

export ANTENNA_RULES_TCL="${ANTENNA_RULES_TCL:-${_tsmc65_root}/clf/antennaRule_n65_9lm.tcl}"
export SRAM_CLF="${SRAM_CLF:-${_sram_root}/gen_hde/RA1HD_4KB_ant.clf}"
export STD_CELL_CLF="${STD_CELL_CLF:-${_stdcell_mw}/clf/antenna_tcbn65gplusbwp12t.clf}"
export GDS_LAYER_MAP="${GDS_LAYER_MAP:-${_stdcell_mw}/gdsout_6X2Z.map}"

unset _icc_dependencies_dir _tsmc65_root _stdcell_root _stdcell_nldm _stdcell_mw _dc_stdcell_nldm _sram_root
