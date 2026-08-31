#!/usr/bin/env bash
set -u

mode="${1:?simulation mode is required}"
run_dir="${2:?run directory is required}"
compile_log="${run_dir}/compile.log"
run_log="${run_dir}/run.log"
errors=0

for required in "${compile_log}" "${run_log}"; do
  if [[ ! -f "${required}" ]]; then
    echo "MISS ${required}" >&2
    errors=$((errors + 1))
  fi
done

if [[ -f "${run_log}" ]]; then
  if ! grep -q 'CPU+FFT16 TEST PASS' "${run_log}"; then
    echo "FAIL ${mode}: self-checking testbench did not report PASS" >&2
    errors=$((errors + 1))
  fi
  if grep -Eq 'CPU\+FFT16 TEST FAIL|(^|[[:space:]])(Error|Fatal):' "${run_log}"; then
    echo "FAIL ${mode}: simulation errors were found" >&2
    errors=$((errors + 1))
  fi
fi

if [[ "${mode}" != "func" && -f "${compile_log}" && -f "${run_log}" ]]; then
  if ! grep -Eqi 'SDF|back.annotat' "${compile_log}" "${run_log}"; then
    echo "FAIL ${mode}: no SDF annotation message was found" >&2
    errors=$((errors + 1))
  fi
  if grep -Eqi 'SDF[^[:alnum:]]*(Error|Fatal)|SDFCOM_(NL|[EF])|(No\.|Number of)[[:space:]]+errors[^0-9]*[1-9]' \
      "${compile_log}" "${run_log}"; then
    echo "FAIL ${mode}: SDF annotation errors were found" >&2
    errors=$((errors + 1))
  fi
  if grep -Eqi 'timing (check )?violation|\*\*.*(setup|hold).*violat|Warning:.*(setup|hold).*violat' \
      "${run_log}"; then
    echo "FAIL ${mode}: timing-check violations were found" >&2
    errors=$((errors + 1))
  fi
fi

if [[ "${mode}" == "power" ]]; then
  if [[ ! -s "${run_dir}/tb_soc.vcd" ]]; then
    echo "FAIL power: measured-window VCD was not generated" >&2
    errors=$((errors + 1))
  fi
  if ! bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify_power_window.sh" \
      "${run_dir}/power_window.rpt"; then
    echo "FAIL power: invalid or missing measured-window metadata" >&2
    errors=$((errors + 1))
  fi
fi

if ((errors != 0)); then
  echo "Post-simulation verification failed: ${errors} issue(s)." >&2
  exit 1
fi

echo "Post-simulation ${mode} verification passed."
