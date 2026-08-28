#!/usr/bin/env bash
# External dependencies used by the Design Compiler flow.
#
# Edit this file when the SoC source tree, technology libraries, Synopsys
# installation, or project-specific setup scripts move.  Every value may also
# be overridden by exporting the corresponding variable before compile.sh is
# invoked.

export SOC_ROOT="${SOC_ROOT:-/home/master/project/IC_class/RISC_V}"

# Maximum-delay libraries used for setup optimization and linking.
export STD_CELL_DB="${STD_CELL_DB:-/home/master/project/2_dc/day2/library/tcbn65gplusbwp12twc.db}"
export SRAM_DB="${SRAM_DB:-/home/master/project/3_PR/sram_hde/gen_hde/RA1HD_4KB_ss_0p90v_0p90v_125c.db}"

# Minimum-delay counterparts used for hold analysis and hold fixing.
export STD_CELL_MIN_DB="${STD_CELL_MIN_DB:-/home/master/project/2_dc/day2/library/tcbn65gplusbwp12tbc.db}"
export SRAM_MIN_DB="${SRAM_MIN_DB:-/home/master/project/3_PR/sram_hde/gen_hde/RA1HD_4KB_ff_1p10v_1p10v_m40c.db}"

export DW_FOUNDATION_DB="${DW_FOUNDATION_DB:-/export/SoftWare/Synopsys/syn/O-2018.06-SP1/libraries/syn/dw_foundation.sldb}"

# Keep these paths configurable even when the setup files live in the project.
export SETUP_ENV_TCL="${SETUP_ENV_TCL:-${PROJECT_ROOT:-/home/master/project/RISCV-fft}/dc/setup_env.tcl}"
export SETUP_COMPILE_TCL="${SETUP_COMPILE_TCL:-${PROJECT_ROOT:-/home/master/project/RISCV-fft}/dc/setup_compile.tcl}"

export DC_SHELL_BIN="${DC_SHELL_BIN:-/export/SoftWare/Synopsys/syn/O-2018.06-SP1/bin/dc_shell-xg-t}"
