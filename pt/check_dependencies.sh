#!/usr/bin/env bash
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/dependencies.sh"

check_power_vcd=false
case "${1:-}" in
  "") ;;
  --power) check_power_vcd=true ;;
  *)
    echo "Usage: $0 [--power]" >&2
    exit 2
    ;;
esac

errors=0

require_file() {
  local label="$1"
  local path="$2"
  if [[ -f "${path}" ]]; then
    printf 'OK   %-20s %s\n' "${label}" "${path}"
  else
    printf 'MISS %-20s %s\n' "${label}" "${path}" >&2
    errors=$((errors + 1))
  fi
}

if [[ -x "${PT_SHELL_BIN}" ]]; then
  printf 'OK   %-20s %s\n' "pt_shell" "${PT_SHELL_BIN}"
else
  printf 'MISS %-20s %s\n' "pt_shell" "${PT_SHELL_BIN}" >&2
  errors=$((errors + 1))
fi

require_file "WC standard DB" "${STD_CELL_WC_DB}"
require_file "TC standard DB" "${STD_CELL_TC_DB}"
require_file "BC standard DB" "${STD_CELL_BC_DB}"
require_file "WC SRAM DB" "${SRAM_WC_DB}"
require_file "TC SRAM DB" "${SRAM_TC_DB}"
require_file "BC SRAM DB" "${SRAM_BC_DB}"
require_file "placed netlist" "${PT_DATA_DIR}/${DESIGN_NAME}.output.v"
require_file "signoff SDC" "${PT_DATA_DIR}/${DESIGN_NAME}.output.sdc"
require_file "maximum SPEF" "${PT_DATA_DIR}/${DESIGN_NAME}.output.spef.max"
require_file "minimum SPEF" "${PT_DATA_DIR}/${DESIGN_NAME}.output.spef.min"

if [[ "${check_power_vcd}" == true ]]; then
  require_file "power VCD" "${POWER_VCD}"
  require_file "power window" "${POWER_WINDOW_FILE}"
  require_file "window validator" "${PROJECT_ROOT}/postsim/verify_power_window.sh"
  require_file "power summarizer" "${PT_ROOT}/summarize_power.sh"
  if [[ -f "${POWER_WINDOW_FILE}" ]] &&
      ! bash "${PROJECT_ROOT}/postsim/verify_power_window.sh" "${POWER_WINDOW_FILE}"; then
    echo "FAIL power window metadata is invalid" >&2
    errors=$((errors + 1))
  fi
fi

if ((errors != 0)); then
  echo "PrimeTime dependency check failed: ${errors} issue(s)." >&2
  exit 1
fi

echo "PrimeTime dependency check passed (no license was checked out)."
