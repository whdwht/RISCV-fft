#!/usr/bin/env bash
set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/dependencies.sh"

errors=0
for corner in wc_max tc_min bc_min; do
  run_dir="${PT_RUNS_DIR}/${corner}"
  status_file="${run_dir}/timing_status_${corner}.rpt"
  constraint_file="${run_dir}/constraint_violators_${corner}.rpt"
  constraint_check_file="${run_dir}/check_constraints_${corner}.rpt"
  log_file="${run_dir}/pt.log"

  for required in \
    "${status_file}" \
    "${constraint_file}" \
    "${constraint_check_file}" \
    "${log_file}"; do
    if [[ ! -f "${required}" ]]; then
      echo "MISS ${required}" >&2
      errors=$((errors + 1))
    fi
  done
  if [[ ! -f "${status_file}" || ! -f "${log_file}" ]]; then
    continue
  fi

  if ! grep -q '^PT_RESULT PASS$' "${status_file}"; then
    setup_violations="$(awk '$1 == "PT_SETUP_VIOLATING_PATHS" {print $2}' "${status_file}")"
    hold_violations="$(awk '$1 == "PT_HOLD_VIOLATING_PATHS" {print $2}' "${status_file}")"
    failed_checks=()
    if [[ "${setup_violations:-0}" != 0 ]]; then
      failed_checks+=(setup)
    fi
    if [[ "${hold_violations:-0}" != 0 ]]; then
      failed_checks+=(hold/removal)
    fi
    if ((${#failed_checks[@]} == 0)); then
      failed_checks+=(required)
    fi
    if ((${#failed_checks[@]} == 2)); then
      failed_check_text="${failed_checks[0]} and ${failed_checks[1]}"
    else
      failed_check_text="${failed_checks[0]}"
    fi
    echo "FAIL ${corner}: negative ${failed_check_text} timing slack exists" >&2
    errors=$((errors + 1))
  fi
  if grep -Eq '(^|[[:space:]])(Error:|Fatal:)' "${log_file}"; then
    echo "FAIL ${corner}: PrimeTime errors were found in pt.log" >&2
    errors=$((errors + 1))
  fi
  report_error_files="$(
    grep -El '(^|[[:space:]])(Error:|Fatal:)' "${run_dir}"/*.rpt \
      2>/dev/null || true
  )"
  if [[ -n "${report_error_files}" ]]; then
    echo "FAIL ${corner}: errors were found in generated reports" >&2
    printf '%s\n' "${report_error_files}" >&2
    errors=$((errors + 1))
  fi
  if [[ -f "${constraint_file}" ]] && \
      grep -Eq '^[[:space:]]*(max_transition|max_capacitance|max_fanout)[[:space:]]' \
        "${constraint_file}"; then
    echo "FAIL ${corner}: design-rule constraint violations exist" >&2
    errors=$((errors + 1))
  fi
done

if ((errors != 0)); then
  echo "PrimeTime result verification failed: ${errors} issue(s)." >&2
  exit 1
fi

echo "PrimeTime result verification passed for WC/TC/BC."
