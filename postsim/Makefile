SHELL := /bin/bash
POSTSIM_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
MODE ?= func

.PHONY: check func max min timing all power_vcd \
	wave wave_func wave_max wave_min \
	verdi verdi_func verdi_max verdi_min help clean

check:
	@bash "$(POSTSIM_DIR)/check_dependencies.sh"

func:
	@bash "$(POSTSIM_DIR)/run.sh" func

max:
	@bash "$(POSTSIM_DIR)/run.sh" max

min:
	@bash "$(POSTSIM_DIR)/run.sh" min

timing: max min

all: func timing

power_vcd:
	@bash "$(POSTSIM_DIR)/run.sh" power

wave:
	@bash "$(POSTSIM_DIR)/run.sh" "$(MODE)" --fsdb

wave_func:
	@bash "$(POSTSIM_DIR)/run.sh" func --fsdb

wave_max:
	@bash "$(POSTSIM_DIR)/run.sh" max --fsdb

wave_min:
	@bash "$(POSTSIM_DIR)/run.sh" min --fsdb

verdi:
	@bash "$(POSTSIM_DIR)/verdi.sh" "$(MODE)"

verdi_func:
	@bash "$(POSTSIM_DIR)/verdi.sh" func

verdi_max:
	@bash "$(POSTSIM_DIR)/verdi.sh" max

verdi_min:
	@bash "$(POSTSIM_DIR)/verdi.sh" min

help:
	@echo "Post-route gate-level simulation"
	@echo ""
	@echo "Simulation:"
	@echo "  make func                 Functional gate simulation"
	@echo "  make max                  WC/max-delay SDF simulation"
	@echo "  make min                  BC/min-delay SDF simulation"
	@echo "  make power_vcd            BC/min SDF run with measured-window VCD metadata"
	@echo ""
	@echo "Waveforms:"
	@echo "  make wave MODE=func       Run and generate build/func/tb_soc.fsdb"
	@echo "  make verdi MODE=func      Open that FSDB in Verdi"
	@echo "  MODE may be func, max, or min"
	@echo "  Shortcut targets: wave_func/wave_max/wave_min and"
	@echo "                    verdi_func/verdi_max/verdi_min"

clean:
	@source "$(POSTSIM_DIR)/dependencies.sh"; \
	  if [[ "$${POSTSIM_BUILD_DIR}" != "$${POSTSIM_ROOT}/build" ]]; then \
	    echo "Refusing to clean non-default POSTSIM_BUILD_DIR=$${POSTSIM_BUILD_DIR}" >&2; exit 1; \
	  fi; \
	  rm -rf "$${POSTSIM_ROOT}/build"
