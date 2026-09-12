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
  metric_count="$(grep -Ec '^FFT16_METRIC cycles=[0-9]+ trigger1=-?[0-9]+ done1=-?[0-9]+ trigger2=-?[0-9]+ done2=-?[0-9]+ first_result=-?[0-9]+ final_result=-?[0-9]+$' "${run_log}" || true)"
  if [[ "${metric_count}" != "1" ]]; then
    echo "FAIL ${mode}: expected exactly one machine-readable FFT16_METRIC line" >&2
    errors=$((errors + 1))
  fi
  phase_metric_count="$(grep -Ec '^FFT16_PHASE_METRIC first_even_input=[0-9]+ first_odd_input=[0-9]+ bin0_done=[0-9]+ bin1_done=[0-9]+ bin2_done=[0-9]+ bin3_done=[0-9]+ bin4_done=[0-9]+ bin5_done=[0-9]+ bin6_done=[0-9]+ bin7_done=[0-9]+$' "${run_log}" || true)"
  if [[ "${phase_metric_count}" != "1" ]]; then
    echo "FAIL ${mode}: expected exactly one machine-readable FFT16_PHASE_METRIC line" >&2
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
  if [[ -s "${run_log}" && -s "${run_dir}/power_window.rpt" ]]; then
    metric_cycles="$(sed -n 's/^FFT16_METRIC cycles=\([0-9][0-9]*\) .*/\1/p' "${run_log}" | head -n 1)"
    window_cycles="$(awk '$1 == "POWER_CYCLES" {print $2; exit}' "${run_dir}/power_window.rpt")"
    if [[ -z "${metric_cycles}" || "${metric_cycles}" != "${window_cycles}" ]]; then
      echo "FAIL power: metric/window cycle mismatch (${metric_cycles:-missing}/${window_cycles:-missing})" >&2
      errors=$((errors + 1))
    fi
  fi
fi

if ((errors != 0)); then
  echo "Post-simulation verification failed: ${errors} issue(s)." >&2
  exit 1
fi

echo "Post-simulation ${mode} verification passed."
