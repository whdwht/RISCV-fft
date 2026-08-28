#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
export PROJECT_ROOT

# shellcheck source=dependencies.sh
source "${SCRIPT_DIR}/dependencies.sh"

require_directory() {
  local variable_name=$1
  local dependency_path=${!variable_name:-}

  if [[ -z "${dependency_path}" ]]; then
    printf 'Error: dependency %s is not configured in %s\n' \
      "${variable_name}" "${SCRIPT_DIR}/dependencies.sh" >&2
    return 1
  fi
  if [[ ! -d "${dependency_path}" ]]; then
    printf 'Error: directory configured by %s does not exist: %s\n' \
      "${variable_name}" "${dependency_path}" >&2
    return 1
  fi
}

require_file() {
  local variable_name=$1
  local dependency_path=${!variable_name:-}

  if [[ -z "${dependency_path}" ]]; then
    printf 'Error: dependency %s is not configured in %s\n' \
      "${variable_name}" "${SCRIPT_DIR}/dependencies.sh" >&2
    return 1
  fi
  if [[ ! -f "${dependency_path}" ]]; then
    printf 'Error: file configured by %s does not exist: %s\n' \
      "${variable_name}" "${dependency_path}" >&2
    return 1
  fi
}

require_directory SOC_ROOT
require_file STD_CELL_DB
require_file STD_CELL_MIN_DB
require_file SRAM_DB
require_file SRAM_MIN_DB
require_file DW_FOUNDATION_DB
require_file SETUP_ENV_TCL
require_file SETUP_COMPILE_TCL

if ! command -v "${DC_SHELL_BIN}" >/dev/null 2>&1; then
  printf 'Error: Design Compiler executable is not available: %s\n' \
    "${DC_SHELL_BIN}" >&2
  exit 1
fi

mkdir -p \
  "${PROJECT_ROOT}/syn_rtl" \
  "${PROJECT_ROOT}/sdc" \
  "${PROJECT_ROOT}/report"

cd "${SCRIPT_DIR}"
"${DC_SHELL_BIN}" -f compile.tcl 2>&1 | tee "${PROJECT_ROOT}/report/dc_compile.log"
