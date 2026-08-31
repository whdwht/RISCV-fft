#!/usr/bin/env bash
# PrimeTime/PrimeTime PX external dependencies. Every value may be overridden
# in the environment before this file is sourced.

_pt_dependency_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${PROJECT_ROOT:=$(cd "${_pt_dependency_dir}/.." && pwd)}"
: "${PT_ROOT:=${PROJECT_ROOT}/pt}"
: "${PT_SHELL_BIN:=/export/SoftWare/Synopsys/pts/O-2018.06-SP1/bin/pt_shell}"
: "${PT_DATA_DIR:=${PROJECT_ROOT}/icc/results}"
: "${PT_RUNS_DIR:=${PT_ROOT}/runs}"
: "${DESIGN_NAME:=soc_ahblite}"

: "${STD_CELL_WC_DB:=/home/master/project/2_dc/day2/library/tcbn65gplusbwp12twc.db}"
: "${STD_CELL_TC_DB:=/home/master/project/2_dc/day2/library/tcbn65gplusbwp12ttc.db}"
: "${STD_CELL_BC_DB:=/home/master/project/2_dc/day2/library/tcbn65gplusbwp12tbc.db}"

: "${SRAM_WC_DB:=/home/master/project/3_PR/sram_hde/gen_hde/RA1HD_4KB_ss_0p90v_0p90v_125c.db}"
: "${SRAM_TC_DB:=/home/master/project/3_PR/sram_hde/gen_hde/RA1HD_4KB_tt_1p00v_1p00v_25c.db}"
: "${SRAM_BC_DB:=/home/master/project/3_PR/sram_hde/gen_hde/RA1HD_4KB_ff_1p10v_1p10v_0c.db}"

: "${POWER_VCD:=${PROJECT_ROOT}/postsim/build/power/tb_soc.vcd}"
: "${POWER_WINDOW_FILE:=${PROJECT_ROOT}/postsim/build/power/power_window.rpt}"
: "${POWER_FFT_INSTANCE:=u_fft8_top}"

export PROJECT_ROOT PT_ROOT PT_SHELL_BIN PT_DATA_DIR PT_RUNS_DIR DESIGN_NAME
export STD_CELL_WC_DB STD_CELL_TC_DB STD_CELL_BC_DB
export SRAM_WC_DB SRAM_TC_DB SRAM_BC_DB
export POWER_VCD POWER_WINDOW_FILE POWER_FFT_INSTANCE

unset _pt_dependency_dir
