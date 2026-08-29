#!/usr/bin/env bash
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/dependencies.sh"

check_max=false
check_min=false
case "${1:-}" in
  "") ;;
  --max) check_max=true ;;
  --min) check_min=true ;;
  --timing) check_max=true; check_min=true ;;
  *)
    echo "Usage: $0 [--max|--min|--timing]" >&2
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

if [[ -x "${VCS_BIN}" ]]; then
  printf 'OK   %-20s %s\n' "vcs" "${VCS_BIN}"
else
  printf 'MISS %-20s %s\n' "vcs" "${VCS_BIN}" >&2
  errors=$((errors + 1))
fi

require_file "placed netlist" "${NETLIST}"
require_file "standard-cell model" "${STD_CELL_MODEL}"
require_file "SRAM model" "${SRAM_MODEL}"
require_file "program VMEM" "${VMEM}"
require_file "gate testbench" "${GATE_TB}"
if [[ "${check_max}" == true ]]; then
  require_file "WC maximum SDF" "${WC_SDF}"
fi
if [[ "${check_min}" == true ]]; then
  require_file "BC minimum SDF" "${BC_SDF}"
fi

if ((errors != 0)); then
  echo "Post-simulation dependency check failed: ${errors} missing item(s)." >&2
  exit 1
fi

echo "Post-simulation dependency check passed (no license was checked out)."
