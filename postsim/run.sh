#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/dependencies.sh"

usage="Usage: $0 func|max|min|power [--fsdb]"
mode="${1:?${usage}}"
if (($# > 2)); then
  echo "${usage}" >&2
  exit 2
fi

dump_fsdb=0
case "${2:-}" in
  "") ;;
  --fsdb) dump_fsdb=1 ;;
  *)
    echo "${usage}" >&2
    exit 2
    ;;
esac

case "${mode}" in
  func)
    check_arg=""
    clk_half_ns="5.0"
    compile_mode_args=(+notimingcheck +nospecify)
    run_mode_args=()
    ;;
  max)
    check_arg="--max"
    clk_half_ns="1.5"
    compile_mode_args=(+define+NTC+RECREM \
      +sdfverbose +neg_tchk -negdelay -sdfretain \
      -sdf "max:tb_soc.x_soc:${WC_SDF}")
    run_mode_args=()
    ;;
  min)
    check_arg="--min"
    clk_half_ns="1.5"
    compile_mode_args=(+define+NTC+RECREM \
      +sdfverbose +neg_tchk -negdelay -sdfretain \
      -sdf "min:tb_soc.x_soc:${BC_SDF}")
    run_mode_args=()
    ;;
  power)
    check_arg="--min"
    clk_half_ns="1.5"
    compile_mode_args=(+define+NTC+RECREM \
      +sdfverbose +neg_tchk -negdelay -sdfretain \
      -sdf "min:tb_soc.x_soc:${BC_SDF}")
    run_mode_args=(
      +DUMP_VCD
      "+VCD=${POSTSIM_BUILD_DIR}/power/tb_soc.vcd"
      "+POWER_WINDOW=${POSTSIM_BUILD_DIR}/power/power_window.rpt"
    )
    ;;
  *)
    echo "Unknown post-simulation mode: ${mode}" >&2
    exit 2
    ;;
esac

if [[ -n "${check_arg}" ]]; then
  bash "${script_dir}/check_dependencies.sh" "${check_arg}"
else
  bash "${script_dir}/check_dependencies.sh"
fi

run_dir="${POSTSIM_BUILD_DIR}/${mode}"
mkdir -p "${run_dir}"

# A failed power simulation must not leave a prior run looking current.
if [[ "${mode}" == "power" ]]; then
  rm -f -- "${run_dir}/tb_soc.vcd" "${run_dir}/power_window.rpt"
fi

cd "${run_dir}"

fsdb_file="${run_dir}/tb_soc.fsdb"
if ((dump_fsdb)); then
  run_mode_args+=(+DUMP_FSDB "+FSDB=${fsdb_file}")
fi

compile_cmd=(
  "${VCS_BIN}"
  -full64 -sverilog +v2k -timescale=1ns/1ps
  -debug_access+all -debug_region+cell -kdb -Mupdate
  -notice +noportcoerce
)
compile_cmd+=("${compile_mode_args[@]}")
compile_cmd+=(
  "${STD_CELL_MODEL}"
  "${SRAM_MODEL}"
  "${NETLIST}"
  "${GATE_TB}"
  -top tb_soc
  -o simv
  -l compile.log
)

"${compile_cmd[@]}"

run_cmd=(./simv "+VMEM=${VMEM}" "+CLK_HALF_NS=${clk_half_ns}")
# Bash 4.2 treats an empty-array expansion as unbound under `set -u`, even
# after `run_mode_args=()` has been assigned. Expand it only when nonempty.
if ((${#run_mode_args[@]})); then
  run_cmd+=("${run_mode_args[@]}")
fi
run_cmd+=(-l run.log)
"${run_cmd[@]}"

bash "${script_dir}/verify_run.sh" "${mode}" "${run_dir}"

if ((dump_fsdb)); then
  if [[ ! -s "${fsdb_file}" ]]; then
    echo "FSDB waveform was not generated: ${fsdb_file}" >&2
    exit 1
  fi
  echo "FSDB waveform generated: ${fsdb_file}"
fi
