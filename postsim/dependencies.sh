#!/usr/bin/env bash
# Gate-level simulation dependencies. Values can be overridden by exporting
# the same variable names before invoking make.

_postsim_dependency_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${PROJECT_ROOT:=$(cd "${_postsim_dependency_dir}/.." && pwd)}"
: "${POSTSIM_ROOT:=${PROJECT_ROOT}/postsim}"
: "${POSTSIM_BUILD_DIR:=${POSTSIM_ROOT}/build}"
: "${VCS_BIN:=/export/SoftWare/Synopsys/vcs/O-2018.09-SP2/linux64/bin/vcs}"
: "${VERDI_BIN:=/export/SoftWare/Synopsys/verdi/Verdi_O-2018.09-SP2/bin/verdi}"
: "${NETLIST:=${PROJECT_ROOT}/icc/results/soc_ahblite.output.v}"
: "${STD_CELL_MODEL:=/home/master/project/IC_class/library/tcbn65gplusbwp12t.v}"
: "${SRAM_MODEL:=/home/master/project/3_PR/sram_hde/gen_hde/RA1HD_4KB.v}"
: "${VMEM:=${PROJECT_ROOT}/sim_16/sw/gcc.vmem}"
: "${GATE_TB:=${POSTSIM_ROOT}/tb/tb_soc.sv}"
: "${WC_SDF:=${PROJECT_ROOT}/pt/runs/wc_max/my_wc_max.sdf}"
: "${BC_SDF:=${PROJECT_ROOT}/pt/runs/bc_min/my_bc_min.sdf}"

export PROJECT_ROOT POSTSIM_ROOT POSTSIM_BUILD_DIR VCS_BIN VERDI_BIN NETLIST
export STD_CELL_MODEL SRAM_MODEL VMEM GATE_TB WC_SDF BC_SDF

unset _postsim_dependency_dir
