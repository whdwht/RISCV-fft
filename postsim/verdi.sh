#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/dependencies.sh"

mode="${1:-func}"
case "${mode}" in
  func|max|min) ;;
  *)
    echo "Usage: $0 func|max|min" >&2
    exit 2
    ;;
esac

run_dir="${POSTSIM_BUILD_DIR}/${mode}"
fsdb_file="${POSTSIM_FSDB:-${run_dir}/tb_soc.fsdb}"
db_dir="${run_dir}/simv.daidir"

if [[ ! -x "${VERDI_BIN}" ]]; then
  echo "Verdi executable is missing or not executable: ${VERDI_BIN}" >&2
  exit 2
fi
if [[ ! -d "${db_dir}" ]]; then
  echo "VCS KDB is missing: ${db_dir}" >&2
  echo "Run 'make -C ${POSTSIM_ROOT} wave MODE=${mode}' first." >&2
  exit 2
fi
if [[ ! -s "${fsdb_file}" ]]; then
  echo "FSDB waveform is missing: ${fsdb_file}" >&2
  echo "Run 'make -C ${POSTSIM_ROOT} wave MODE=${mode}' first." >&2
  exit 2
fi

cd "${run_dir}"
"${VERDI_BIN}" -sx -dbdir "${db_dir}" -ssf "${fsdb_file}" \
  >"${run_dir}/verdi.log" 2>&1 &

echo "Verdi started for ${mode}: ${fsdb_file}"
echo "Verdi log: ${run_dir}/verdi.log"
