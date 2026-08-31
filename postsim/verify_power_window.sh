#!/usr/bin/env bash
set -u

window_file="${1:?Usage: $0 POWER_WINDOW_FILE}"

if [[ ! -s "${window_file}" ]]; then
  echo "Power-window metadata is missing or empty: ${window_file}" >&2
  exit 1
fi

awk '
  BEGIN {
    expected["POWER_START_NS"] = 1
    expected["POWER_END_NS"] = 1
    expected["POWER_DURATION_NS"] = 1
    expected["POWER_CYCLES"] = 1
    number = "^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$"
  }

  NF == 0 || $1 ~ /^#/ { next }

  NF != 2 {
    printf "Malformed power-window line %d: %s\n", NR, $0 > "/dev/stderr"
    errors++
    next
  }

  !($1 in expected) {
    printf "Unknown power-window key on line %d: %s\n", NR, $1 > "/dev/stderr"
    errors++
    next
  }

  $1 in seen {
    printf "Duplicate power-window key on line %d: %s\n", NR, $1 > "/dev/stderr"
    errors++
    next
  }

  {
    seen[$1] = 1
    value[$1] = $2
  }

  END {
    for (key in expected) {
      if (!(key in seen)) {
        printf "Missing power-window key: %s\n", key > "/dev/stderr"
        errors++
      } else if (key != "POWER_CYCLES" && value[key] !~ number) {
        printf "Non-numeric power-window value: %s=%s\n", key, value[key] > "/dev/stderr"
        errors++
      }
    }

    if (("POWER_CYCLES" in seen) && value["POWER_CYCLES"] !~ /^[1-9][0-9]*$/) {
      printf "POWER_CYCLES must be a positive integer: %s\n", value["POWER_CYCLES"] > "/dev/stderr"
      errors++
    }

    if (errors == 0) {
      start = value["POWER_START_NS"] + 0
      finish = value["POWER_END_NS"] + 0
      duration = value["POWER_DURATION_NS"] + 0
      difference = finish - start
      mismatch = difference - duration
      if (mismatch < 0) mismatch = -mismatch

      if (start < 0) {
        print "POWER_START_NS must not be negative" > "/dev/stderr"
        errors++
      }
      if (finish <= start) {
        print "POWER_END_NS must be greater than POWER_START_NS" > "/dev/stderr"
        errors++
      }
      if (duration <= 0) {
        print "POWER_DURATION_NS must be positive" > "/dev/stderr"
        errors++
      }
      if (mismatch > 0.001) {
        printf "Power-window duration mismatch: end-start=%.6f, recorded=%.6f ns\n", difference, duration > "/dev/stderr"
        errors++
      }
    }

    exit(errors != 0)
  }
' "${window_file}" || exit 1

echo "Power-window metadata passed: ${window_file}"
