#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=dependencies.sh
source "${script_dir}/dependencies.sh"

errors=0

check_tool() {
    local name=$1
    local value=$2
    local resolved

    if [[ "${value}" == */* ]]; then
        resolved=${value}
    else
        resolved=$(command -v "${value}" 2>/dev/null || true)
    fi

    if [[ -n "${resolved}" && -x "${resolved}" ]]; then
        printf 'ok   %-24s %s\n' "${name}" "${resolved}"
    else
        printf 'MISS %-24s %s\n' "${name}" "${value}" >&2
        errors=$((errors + 1))
    fi
}

check_file() {
    local name=$1
    local value=$2
    if [[ -f "${value}" && -r "${value}" ]]; then
        printf 'ok   %-24s %s\n' "${name}" "${value}"
    else
        printf 'MISS %-24s %s\n' "${name}" "${value}" >&2
        errors=$((errors + 1))
    fi
}

check_dir() {
    local name=$1
    local value=$2
    if [[ -d "${value}" && -r "${value}" ]]; then
        printf 'ok   %-24s %s\n' "${name}" "${value}"
    else
        printf 'MISS %-24s %s\n' "${name}" "${value}" >&2
        errors=$((errors + 1))
    fi
}

check_nonnegative_number() {
    local name=$1
    local value=$2
    if [[ "${value}" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]]; then
        printf 'ok   %-24s %s\n' "${name}" "${value}"
    else
        printf 'BAD  %-24s %s (expected a non-negative number)\n' \
            "${name}" "${value}" >&2
        errors=$((errors + 1))
    fi
}

check_boolean() {
    local name=$1
    local value=$2
    case "${value}" in
        TRUE|FALSE)
            printf 'ok   %-24s %s\n' "${name}" "${value}"
            ;;
        *)
            printf 'BAD  %-24s %s (expected TRUE or FALSE)\n' \
                "${name}" "${value}" >&2
            errors=$((errors + 1))
            ;;
    esac
}

check_tool ICC_SHELL_BIN "${ICC_SHELL_BIN}"
check_tool MILKYWAY_BIN "${MILKYWAY_BIN}"

check_file INPUT_DDC "${PROJECT_ROOT}/syn_rtl/soc_ahblite.mapped.ddc"
check_file INPUT_VERILOG "${PROJECT_ROOT}/syn_rtl/soc_ahblite.mapped.v"
check_file INPUT_SDC "${PROJECT_ROOT}/sdc/soc_ahblite.mapped.sdc"
check_file STD_CELL_DB "${STD_CELL_DB}"
check_file STD_CELL_MIN_DB "${STD_CELL_MIN_DB}"
check_file SRAM_DB "${SRAM_DB}"
check_file SRAM_MIN_DB "${SRAM_MIN_DB}"
check_dir STD_CELL_MW_LIB "${STD_CELL_MW_LIB}"
check_dir SRAM_MW_LIB "${SRAM_MW_LIB}"
check_file TECH_FILE "${TECH_FILE}"
check_file TLUPLUS_MAP_FILE "${TLUPLUS_MAP_FILE}"
check_file TLUPLUS_MAX_FILE "${TLUPLUS_MAX_FILE}"
check_file TLUPLUS_MIN_FILE "${TLUPLUS_MIN_FILE}"
check_file ANTENNA_RULES_TCL "${ANTENNA_RULES_TCL}"
check_file SRAM_CLF "${SRAM_CLF}"
check_file STD_CELL_CLF "${STD_CELL_CLF}"
check_file GDS_LAYER_MAP "${GDS_LAYER_MAP}"

if [[ -n "${ICC_CLOCK_NAME}" ]]; then
    printf 'ok   %-24s %s\n' ICC_CLOCK_NAME "${ICC_CLOCK_NAME}"
else
    printf 'BAD  %-24s clock name is empty\n' ICC_CLOCK_NAME >&2
    errors=$((errors + 1))
fi
check_nonnegative_number ICC_SETUP_UNCERTAINTY "${ICC_SETUP_UNCERTAINTY}"
check_nonnegative_number ICC_HOLD_UNCERTAINTY "${ICC_HOLD_UNCERTAINTY}"
check_nonnegative_number ICC_RESET_RELEASE_MIN "${ICC_RESET_RELEASE_MIN}"
check_nonnegative_number ICC_RESET_RELEASE_MAX "${ICC_RESET_RELEASE_MAX}"
check_nonnegative_number ICC_OPT_RESET_RELEASE_MIN "${ICC_OPT_RESET_RELEASE_MIN}"
check_nonnegative_number ICC_MAX_FANOUT "${ICC_MAX_FANOUT}"
check_nonnegative_number ICC_MAX_TRANSITION "${ICC_MAX_TRANSITION}"
check_nonnegative_number ICC_MAX_CAPACITANCE "${ICC_MAX_CAPACITANCE}"
check_nonnegative_number ICC_OPT_MAX_TRANSITION "${ICC_OPT_MAX_TRANSITION}"
check_nonnegative_number ICC_OPT_MAX_CAPACITANCE "${ICC_OPT_MAX_CAPACITANCE}"
check_nonnegative_number ICC_OPT_SRAM_DATA_MAX_TRANSITION \
    "${ICC_OPT_SRAM_DATA_MAX_TRANSITION}"

number_pattern='^([0-9]+([.][0-9]*)?|[.][0-9]+)$'
if [[ "${ICC_RESET_RELEASE_MIN}" =~ ${number_pattern} && \
      "${ICC_RESET_RELEASE_MAX}" =~ ${number_pattern} ]] && \
    awk -v minimum="${ICC_RESET_RELEASE_MIN}" \
        -v maximum="${ICC_RESET_RELEASE_MAX}" \
        'BEGIN { exit !(minimum <= maximum) }'; then
    printf 'ok   %-24s %s <= %s\n' ICC_RESET_RELEASE_RANGE \
        "${ICC_RESET_RELEASE_MIN}" "${ICC_RESET_RELEASE_MAX}"
else
    printf 'BAD  %-24s min=%s max=%s (expected min <= max)\n' \
        ICC_RESET_RELEASE_RANGE \
        "${ICC_RESET_RELEASE_MIN}" "${ICC_RESET_RELEASE_MAX}" >&2
    errors=$((errors + 1))
fi
unset number_pattern

check_not_greater() {
    local implementation_name=$1
    local implementation_value=$2
    local signoff_name=$3
    local signoff_value=$4

    if [[ "${implementation_value}" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ && \
          "${signoff_value}" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] && \
        awk -v implementation="${implementation_value}" \
            -v signoff="${signoff_value}" \
            'BEGIN { exit !(implementation <= signoff) }'; then
        printf 'ok   %-24s %s <= %s (%s)\n' \
            "${implementation_name}" "${implementation_value}" \
            "${signoff_value}" "${signoff_name}"
    else
        printf 'BAD  %-24s %s must be <= %s=%s\n' \
            "${implementation_name}" "${implementation_value}" \
            "${signoff_name}" "${signoff_value}" >&2
        errors=$((errors + 1))
    fi
}

check_not_greater ICC_OPT_RESET_RELEASE_MIN \
    "${ICC_OPT_RESET_RELEASE_MIN}" ICC_RESET_RELEASE_MIN \
    "${ICC_RESET_RELEASE_MIN}"
check_not_greater ICC_OPT_MAX_TRANSITION \
    "${ICC_OPT_MAX_TRANSITION}" ICC_MAX_TRANSITION \
    "${ICC_MAX_TRANSITION}"
check_not_greater ICC_OPT_MAX_CAPACITANCE \
    "${ICC_OPT_MAX_CAPACITANCE}" ICC_MAX_CAPACITANCE \
    "${ICC_MAX_CAPACITANCE}"
check_not_greater ICC_OPT_SRAM_DATA_MAX_TRANSITION \
    "${ICC_OPT_SRAM_DATA_MAX_TRANSITION}" ICC_OPT_MAX_TRANSITION \
    "${ICC_OPT_MAX_TRANSITION}"
unset -f check_not_greater

check_boolean ICC_ROUTE_OPT_AREA_RECOVERY "${ICC_ROUTE_OPT_AREA_RECOVERY}"

case "${ICC_TOTAL_POWER_STRATEGY_EFFORT}" in
    none|medium|high)
        printf 'ok   %-24s %s\n' ICC_TOTAL_POWER_STRATEGY_EFFORT \
            "${ICC_TOTAL_POWER_STRATEGY_EFFORT}"
        ;;
    *)
        printf 'BAD  %-24s %s (expected none, medium, or high)\n' \
            ICC_TOTAL_POWER_STRATEGY_EFFORT \
            "${ICC_TOTAL_POWER_STRATEGY_EFFORT}" >&2
        errors=$((errors + 1))
        ;;
esac

if [[ -n "${ICC_SAIF_FILE}" ]]; then
    check_file ICC_SAIF_FILE "${ICC_SAIF_FILE}"
    if [[ -z "${ICC_SAIF_INSTANCE_NAME}" ]]; then
        printf 'BAD  %-24s instance name is empty\n' ICC_SAIF_INSTANCE_NAME >&2
        errors=$((errors + 1))
    else
        printf 'ok   %-24s %s\n' ICC_SAIF_INSTANCE_NAME \
            "${ICC_SAIF_INSTANCE_NAME}"
    fi
elif [[ "${ICC_TOTAL_POWER_STRATEGY_EFFORT}" != "none" ]]; then
    printf 'WARN %-24s total-power optimization will use vectorless activity\n' \
        ICC_SAIF_FILE >&2
else
    printf 'note %-24s not set; power reports use vectorless activity\n' \
        ICC_SAIF_FILE
fi

if (( errors != 0 )); then
    printf '\nDependency check failed: %d missing item(s).\n' "${errors}" >&2
    exit 1
fi

printf '\nAll ICC dependencies are available.\n'
