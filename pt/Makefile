SHELL := /bin/bash
PT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

.PHONY: all check wc_max tc_min bc_min sta verify_sta power power_all help clean

all: sta

check:
	@bash "$(PT_DIR)/check_dependencies.sh"

wc_max: check
	@set -euo pipefail; source "$(PT_DIR)/dependencies.sh"; \
	  mkdir -p "$${PT_RUNS_DIR}/wc_max"; \
	  cd "$${PT_RUNS_DIR}/wc_max"; \
	  "$${PT_SHELL_BIN}" -f "$${PT_ROOT}/compile_wc_max.tcl" 2>&1 | tee pt.log

tc_min: check
	@set -euo pipefail; source "$(PT_DIR)/dependencies.sh"; \
	  mkdir -p "$${PT_RUNS_DIR}/tc_min"; \
	  cd "$${PT_RUNS_DIR}/tc_min"; \
	  "$${PT_SHELL_BIN}" -f "$${PT_ROOT}/compile_tc_min.tcl" 2>&1 | tee pt.log

bc_min: check
	@set -euo pipefail; source "$(PT_DIR)/dependencies.sh"; \
	  mkdir -p "$${PT_RUNS_DIR}/bc_min"; \
	  cd "$${PT_RUNS_DIR}/bc_min"; \
	  "$${PT_SHELL_BIN}" -f "$${PT_ROOT}/compile_bc_min.tcl" 2>&1 | tee pt.log

sta: wc_max tc_min bc_min

verify_sta:
	@bash "$(PT_DIR)/verify_results.sh"

power:
	@bash "$(PT_DIR)/check_dependencies.sh" --power
	@set -euo pipefail; source "$(PT_DIR)/dependencies.sh"; \
	  mkdir -p "$${PT_RUNS_DIR}/power"; \
	  rm -f -- \
	    "$${PT_RUNS_DIR}/power/power_vcd.rpt" \
	    "$${PT_RUNS_DIR}/power/power_vcd_hier.rpt" \
	    "$${PT_RUNS_DIR}/power/power_fft8.rpt" \
	    "$${PT_RUNS_DIR}/power/power_units.rpt" \
	    "$${PT_RUNS_DIR}/power/power_window_used.rpt" \
	    "$${PT_RUNS_DIR}/power/power_summary.rpt"; \
	  cd "$${PT_RUNS_DIR}/power"; \
	  "$${PT_SHELL_BIN}" -f "$${PT_ROOT}/compile_power.tcl" 2>&1 | tee pt.log; \
	  bash "$${PT_ROOT}/summarize_power.sh" "$${PT_RUNS_DIR}/power" \
	    "$${POWER_WINDOW_FILE}" "$${POWER_FFT_INSTANCE}"

power_all:
	@$(MAKE) --no-print-directory -C "$(PT_DIR)/../postsim" power_vcd
	@$(MAKE) --no-print-directory -C "$(PT_DIR)" power

help:
	@echo "PrimeTime signoff and power analysis"
	@echo "  make sta          Run WC/max, TC/min, and BC/min STA"
	@echo "  make verify_sta   Verify timing and design-rule reports"
	@echo "  make power        Analyze an existing postsim power VCD"
	@echo "  make power_all    Generate the measured VCD, run PT PX, and summarize"

clean:
	@source "$(PT_DIR)/dependencies.sh"; \
	  if [[ "$${PT_RUNS_DIR}" != "$${PT_ROOT}/runs" ]]; then \
	    echo "Refusing to clean non-default PT_RUNS_DIR=$${PT_RUNS_DIR}" >&2; exit 1; \
	  fi; \
	  rm -rf "$${PT_ROOT}/runs"
