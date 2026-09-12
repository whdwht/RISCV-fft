#!/usr/bin/env bash
set -euo pipefail

usage="Usage: $0 PT_POWER_RUN_DIR POWER_WINDOW_FILE [FFT_INSTANCE]"
run_dir="${1:?${usage}}"
window_file="${2:?${usage}}"
fft_instance="${3:-u_fft8_top}"
soc_report="${run_dir}/power_vcd.rpt"
fft_report="${run_dir}/power_fft8.rpt"
hierarchy_report="${run_dir}/power_vcd_hier.rpt"
summary_file="${run_dir}/power_summary.rpt"
pt_log="${run_dir}/pt.log"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
bash "${project_root}/postsim/verify_power_window.sh" "${window_file}" >/dev/null

for report in "${soc_report}" "${fft_report}" "${hierarchy_report}"; do
  if [[ ! -s "${report}" ]]; then
    echo "Power report is missing or empty: ${report}" >&2
    exit 1
  fi
done

if [[ ! -s "${pt_log}" ]]; then
  echo "PrimeTime power log is missing or empty: ${pt_log}" >&2
  exit 1
fi
if grep -Eq '(^|[[:space:]])(Error|Fatal):' "${pt_log}"; then
  echo "PrimeTime errors were found in ${pt_log}" >&2
  exit 1
fi

window_value() {
  local key="$1"
  awk -v key="${key}" '$1 == key { print $2; found = 1; exit }
    END { if (!found) exit 1 }' "${window_file}"
}

# Hierarchical report values use the dynamic-power unit declared in the
# matching verbose SoC report.  Only immediate SoC children are selected so
# the resulting categories are mutually exclusive.
hierarchy_power_value_mw() {
  local instance="$1"
  local raw_value
  local unit_factor
  raw_value="$(awk -v target="${instance}" '
    $1 == target {
      value = $(NF - 1)
      if (value !~ /^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$/)
        next
      count++
      result = value
    }
    END {
      if (count != 1) {
        printf "Expected one hierarchy row for %s, found %d\n", target, count > "/dev/stderr"
        exit 1
      }
      print result
    }
  ' "${hierarchy_report}")"
  unit_factor="$(awk '
    function factor(unit) {
      if (unit == "W")  return 1000.0
      if (unit == "mW") return 1.0
      if (unit == "uW") return 0.001
      if (unit == "nW") return 0.000001
      if (unit == "pW") return 0.000000001
      return -1.0
    }
    /Dynamic Power Units[[:space:]]*=/ {
      text = $0
      sub(/^.*=[[:space:]]*/, "", text)
      sub(/[[:space:]]*\(.*/, "", text)
      gsub(/[[:space:]]/, "", text)
      if      (text ~ /mW$/) unit = "mW"
      else if (text ~ /uW$/) unit = "uW"
      else if (text ~ /nW$/) unit = "nW"
      else if (text ~ /pW$/) unit = "pW"
      else if (text ~ /W$/)  unit = "W"
      scale = text
      sub(/(mW|uW|nW|pW|W)$/, "", scale)
      result = (scale + 0.0) * factor(unit)
      found = 1
    }
    END {
      if (!found || result <= 0.0) exit 1
      print result
    }
  ' "${soc_report}")"
  awk -v value="${raw_value}" -v factor="${unit_factor}" \
    'BEGIN { printf "%.12g\n", value * factor }'
}

# PrimeTime verbose reports state the dynamic and leakage units separately.
# Scalar lines sometimes omit a suffix, so use the matching header unit in
# that case.  Convert every result to mW before calculating energy.
power_value_mw() {
  local report="$1"
  local label="$2"
  local kind="$3"
  awk -v target="${label}" -v kind="${kind}" '
    function trim(text) {
      sub(/^[[:space:]]+/, "", text)
      sub(/[[:space:]]+$/, "", text)
      return text
    }
    function unit_factor_mw(unit) {
      if (unit == "W")  return 1000.0
      if (unit == "mW") return 1.0
      if (unit == "uW") return 0.001
      if (unit == "nW") return 0.000001
      if (unit == "pW") return 0.000000001
      return -1.0
    }
    function header_factor(line, compact, unit, scale, factor) {
      sub(/^.*=[[:space:]]*/, "", line)
      sub(/[[:space:]]*\(.*/, "", line)
      gsub(/[[:space:]]/, "", line)
      compact = line
      if      (compact ~ /mW$/) unit = "mW"
      else if (compact ~ /uW$/) unit = "uW"
      else if (compact ~ /nW$/) unit = "nW"
      else if (compact ~ /pW$/) unit = "pW"
      else if (compact ~ /W$/)  unit = "W"
      else return -1.0
      scale = compact
      sub(/(mW|uW|nW|pW|W)$/, "", scale)
      if (scale !~ /^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$/)
        return -1.0
      factor = unit_factor_mw(unit)
      return (scale + 0.0) * factor
    }
    /Dynamic Power Units[[:space:]]*=/ {
      dynamic_factor = header_factor($0)
    }
    /Leakage Power Units[[:space:]]*=/ {
      leakage_factor = header_factor($0)
    }
    index($0, "=") {
      equals = index($0, "=")
      left = trim(substr($0, 1, equals - 1))
      if (left != target) next
      right = trim(substr($0, equals + 1))
      count = split(right, field, /[[:space:]]+/)
      number = field[1]
      if (number !~ /^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$/)
        next
      explicit_factor = (count >= 2) ? unit_factor_mw(field[2]) : -1.0
      raw_value = number + 0.0
      found = 1
      next
    }
    END {
      if (!found) {
        printf "Cannot find power value %s in report\n", target > "/dev/stderr"
        exit 1
      }
      if (explicit_factor >= 0.0) {
        factor = explicit_factor
      } else if (kind == "leakage") {
        factor = leakage_factor
      } else {
        factor = dynamic_factor
      }
      if (factor <= 0.0) {
        printf "Cannot determine %s unit for %s\n", kind, target > "/dev/stderr"
        exit 1
      }
      printf "%.12g\n", raw_value * factor
    }
  ' "${report}"
}

start_ns="$(window_value POWER_START_NS)"
end_ns="$(window_value POWER_END_NS)"
duration_ns="$(window_value POWER_DURATION_NS)"
cycles="$(window_value POWER_CYCLES)"

soc_internal_mw="$(power_value_mw "${soc_report}" "Cell Internal Power" dynamic)"
soc_switching_mw="$(power_value_mw "${soc_report}" "Net Switching Power" dynamic)"
soc_leakage_mw="$(power_value_mw "${soc_report}" "Cell Leakage Power" leakage)"
soc_total_mw="$(power_value_mw "${soc_report}" "Total Power" dynamic)"

fft_internal_mw="$(power_value_mw "${fft_report}" "Cell Internal Power" dynamic)"
fft_switching_mw="$(power_value_mw "${fft_report}" "Net Switching Power" dynamic)"
fft_leakage_mw="$(power_value_mw "${fft_report}" "Cell Leakage Power" leakage)"
fft_total_mw="$(power_value_mw "${fft_report}" "Total Power" dynamic)"

cpu_subsystem_mw="$(hierarchy_power_value_mw x_sub_system)"
instruction_sram_mw="$(hierarchy_power_value_mw x_isram_ahbl)"
data_sram_mw="$(hierarchy_power_value_mw x_data_sram)"
rom_mw="$(hierarchy_power_value_mw x_rom_ahbl)"
data_fabric_mw="$(hierarchy_power_value_mw x_data_fabric)"

awk \
  -v start_ns="${start_ns}" -v end_ns="${end_ns}" \
  -v duration_ns="${duration_ns}" -v cycles="${cycles}" \
  -v fft_instance="${fft_instance}" \
  -v soc_internal="${soc_internal_mw}" -v soc_switching="${soc_switching_mw}" \
  -v soc_leakage="${soc_leakage_mw}" -v soc_total="${soc_total_mw}" \
  -v fft_internal="${fft_internal_mw}" -v fft_switching="${fft_switching_mw}" \
  -v fft_leakage="${fft_leakage_mw}" -v fft_total="${fft_total_mw}" \
  -v cpu_subsystem="${cpu_subsystem_mw}" \
  -v instruction_sram="${instruction_sram_mw}" \
  -v data_sram="${data_sram_mw}" -v rom="${rom_mw}" \
  -v data_fabric="${data_fabric_mw}" '
  BEGIN {
    soc_dynamic = soc_internal + soc_switching
    fft_dynamic = fft_internal + fft_switching
    soc_energy_nj = soc_total * duration_ns / 1000.0
    fft_energy_nj = fft_total * duration_ns / 1000.0
    soc_energy_per_cycle_pj = soc_total * duration_ns / cycles
    fft_energy_per_cycle_pj = fft_total * duration_ns / cycles
    fft_share = (soc_total > 0.0) ? 100.0 * fft_total / soc_total : 0.0
    type_total = soc_internal + soc_switching + soc_leakage
    if (type_total <= 0.0 || soc_total <= 0.0) {
      print "Invalid non-positive SoC power breakdown" > "/dev/stderr"
      exit 1
    }
    # PT prints component powers with fewer significant digits than the total.
    # Preserve their relative weights while closing allocated energy exactly to
    # the authoritative total-window energy.
    type_scale = soc_total / type_total
    internal_energy_nj = soc_internal * type_scale * duration_ns / 1000.0
    switching_energy_nj = soc_switching * type_scale * duration_ns / 1000.0
    leakage_energy_nj = soc_leakage * type_scale * duration_ns / 1000.0

    known_hierarchy = cpu_subsystem + fft_total + instruction_sram + \
                      data_sram + rom + data_fabric
    other = soc_total - known_hierarchy
    if (other < -0.005 * soc_total) {
      printf "Hierarchy powers exceed SoC total by %.9g mW\n", -other > "/dev/stderr"
      exit 1
    }
    if (other < 0.0) other = 0.0

    print "POWER_RESULT PASS"
    printf "POWER_WINDOW_START_NS %.6f\n", start_ns
    printf "POWER_WINDOW_END_NS %.6f\n", end_ns
    printf "POWER_WINDOW_DURATION_NS %.6f\n", duration_ns
    printf "POWER_WINDOW_CYCLES %d\n", cycles
    printf "FFT_INSTANCE %s\n", fft_instance
    printf "SOC_INTERNAL_POWER_MW %.9g\n", soc_internal
    printf "SOC_SWITCHING_POWER_MW %.9g\n", soc_switching
    printf "SOC_DYNAMIC_POWER_MW %.9g\n", soc_dynamic
    printf "SOC_LEAKAGE_POWER_MW %.9g\n", soc_leakage
    printf "SOC_TOTAL_POWER_MW %.9g\n", soc_total
    printf "SOC_WINDOW_ENERGY_NJ %.9g\n", soc_energy_nj
    printf "SOC_ENERGY_PER_CYCLE_PJ %.9g\n", soc_energy_per_cycle_pj
    printf "SOC_INTERNAL_ENERGY_NJ %.9g\n", internal_energy_nj
    printf "SOC_INTERNAL_ENERGY_PERCENT %.9g\n", 100.0 * soc_internal / type_total
    printf "SOC_SWITCHING_ENERGY_NJ %.9g\n", switching_energy_nj
    printf "SOC_SWITCHING_ENERGY_PERCENT %.9g\n", 100.0 * soc_switching / type_total
    printf "SOC_LEAKAGE_ENERGY_NJ %.9g\n", leakage_energy_nj
    printf "SOC_LEAKAGE_ENERGY_PERCENT %.9g\n", 100.0 * soc_leakage / type_total
    printf "SOC_CPU_SUBSYSTEM_POWER_MW %.9g\n", cpu_subsystem
    printf "SOC_CPU_SUBSYSTEM_ENERGY_NJ %.9g\n", cpu_subsystem * duration_ns / 1000.0
    printf "SOC_CPU_SUBSYSTEM_ENERGY_PERCENT %.9g\n", 100.0 * cpu_subsystem / soc_total
    printf "SOC_INSTRUCTION_SRAM_POWER_MW %.9g\n", instruction_sram
    printf "SOC_INSTRUCTION_SRAM_ENERGY_NJ %.9g\n", instruction_sram * duration_ns / 1000.0
    printf "SOC_INSTRUCTION_SRAM_ENERGY_PERCENT %.9g\n", 100.0 * instruction_sram / soc_total
    printf "SOC_DATA_SRAM_POWER_MW %.9g\n", data_sram
    printf "SOC_DATA_SRAM_ENERGY_NJ %.9g\n", data_sram * duration_ns / 1000.0
    printf "SOC_DATA_SRAM_ENERGY_PERCENT %.9g\n", 100.0 * data_sram / soc_total
    printf "SOC_ROM_POWER_MW %.9g\n", rom
    printf "SOC_ROM_ENERGY_NJ %.9g\n", rom * duration_ns / 1000.0
    printf "SOC_ROM_ENERGY_PERCENT %.9g\n", 100.0 * rom / soc_total
    printf "SOC_DATA_FABRIC_POWER_MW %.9g\n", data_fabric
    printf "SOC_DATA_FABRIC_ENERGY_NJ %.9g\n", data_fabric * duration_ns / 1000.0
    printf "SOC_DATA_FABRIC_ENERGY_PERCENT %.9g\n", 100.0 * data_fabric / soc_total
    printf "SOC_OTHER_POWER_MW %.9g\n", other
    printf "SOC_OTHER_ENERGY_NJ %.9g\n", other * duration_ns / 1000.0
    printf "SOC_OTHER_ENERGY_PERCENT %.9g\n", 100.0 * other / soc_total
    printf "FFT_INTERNAL_POWER_MW %.9g\n", fft_internal
    printf "FFT_SWITCHING_POWER_MW %.9g\n", fft_switching
    printf "FFT_DYNAMIC_POWER_MW %.9g\n", fft_dynamic
    printf "FFT_LEAKAGE_POWER_MW %.9g\n", fft_leakage
    printf "FFT_TOTAL_POWER_MW %.9g\n", fft_total
    printf "FFT_SOC_POWER_PERCENT %.6f\n", fft_share
    printf "FFT_WINDOW_ENERGY_NJ %.9g\n", fft_energy_nj
    printf "FFT_ENERGY_PER_CYCLE_PJ %.9g\n", fft_energy_per_cycle_pj
  }
' | tee "${summary_file}"

echo "Power summary generated: ${summary_file}"
