SHELL := /bin/bash
.SHELLFLAGS := -ec
.ONESHELL:

ICC_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
PROJECT_ROOT := $(abspath $(ICC_ROOT)/..)
DEPS_FILE := $(ICC_ROOT)/dependencies.sh

LOGS_DIR := $(ICC_ROOT)/logs_zrt
REPORTS_DIR := $(ICC_ROOT)/reports
RESULTS_DIR := $(ICC_ROOT)/results
PNA_OUTPUT_DIR := $(ICC_ROOT)/pna_output
MARKERS_DIR := $(ICC_ROOT)/.markers
MW_DESIGN_LIBRARY := $(ICC_ROOT)/soc_ahblite_LIB

ICC_OPTIONS ?= -64bit
# auLoadCLF drives a Tk form even in batch mode.  Milkyway's native null
# display supplies the required private X server for SSH/headless sessions.
MW_OPTIONS ?= -nullDisplay

STAGES := init_design_icc load_clf place_opt_icc clock_opt_cts_icc \
	clock_opt_psyn_icc clock_opt_route_icc route_icc route_opt_icc \
	chip_finish_icc metal_fill_icc signoff_drc_icc outputs_icc

.PHONY: all check_dependencies $(STAGES) ic eco_icc eco focal_opt_icc focal_opt \
	focal_cleanup_icc focal_cleanup focal_targeted_icc focal_targeted \
	audit_timing_icc audit_timing clean clean_all

all: ic

check_dependencies:
	@set -o pipefail
	ICC_ROOT="$(ICC_ROOT)" PROJECT_ROOT="$(PROJECT_ROOT)" "$(ICC_ROOT)/check_dependencies.sh"

init_design_icc: $(MARKERS_DIR)/init_design_icc
load_clf: $(MARKERS_DIR)/load_clf
place_opt_icc: $(MARKERS_DIR)/place_opt_icc
clock_opt_cts_icc: $(MARKERS_DIR)/clock_opt_cts_icc
clock_opt_psyn_icc: $(MARKERS_DIR)/clock_opt_psyn_icc
clock_opt_route_icc: $(MARKERS_DIR)/clock_opt_route_icc
route_icc: $(MARKERS_DIR)/route_icc
route_opt_icc: $(MARKERS_DIR)/route_opt_icc
chip_finish_icc: $(MARKERS_DIR)/chip_finish_icc
metal_fill_icc: $(MARKERS_DIR)/metal_fill_icc
signoff_drc_icc: $(MARKERS_DIR)/signoff_drc_icc
outputs_icc: $(MARKERS_DIR)/outputs_icc

$(MARKERS_DIR)/init_design_icc: | check_dependencies
	@set -o pipefail
	mkdir -p "$(LOGS_DIR)" "$(REPORTS_DIR)" "$(RESULTS_DIR)" "$(MARKERS_DIR)"
	source "$(DEPS_FILE)"
	cd "$(ICC_ROOT)"
	"$$ICC_SHELL_BIN" $(ICC_OPTIONS) -f "$(ICC_ROOT)/rm_icc_scripts/init_design_icc.tcl" 2>&1 | tee "$(LOGS_DIR)/init_design_icc.log"
	date > "$@"

$(MARKERS_DIR)/load_clf: $(MARKERS_DIR)/init_design_icc | check_dependencies
	@set -o pipefail
	mkdir -p "$(LOGS_DIR)" "$(MARKERS_DIR)"
	source "$(DEPS_FILE)"
	cd "$(ICC_ROOT)"
	"$$MILKYWAY_BIN" $(MW_OPTIONS) -load "$(ICC_ROOT)/myscript/loadclf.cmd" 2>&1 | tee "$(LOGS_DIR)/load_clf.log"
	date > "$@"

$(MARKERS_DIR)/place_opt_icc: $(MARKERS_DIR)/load_clf | check_dependencies
	$(call run_icc,rm_icc_scripts/place_opt_icc.tcl,place_opt_icc)

$(MARKERS_DIR)/clock_opt_cts_icc: $(MARKERS_DIR)/place_opt_icc | check_dependencies
	$(call run_icc,rm_icc_scripts/clock_opt_cts_icc.tcl,clock_opt_cts_icc)

$(MARKERS_DIR)/clock_opt_psyn_icc: $(MARKERS_DIR)/clock_opt_cts_icc | check_dependencies
	$(call run_icc,rm_icc_zrt_scripts/clock_opt_psyn_icc.tcl,clock_opt_psyn_icc)

$(MARKERS_DIR)/clock_opt_route_icc: $(MARKERS_DIR)/clock_opt_psyn_icc | check_dependencies
	$(call run_icc,rm_icc_zrt_scripts/clock_opt_route_icc.tcl,clock_opt_route_icc)

$(MARKERS_DIR)/route_icc: $(MARKERS_DIR)/clock_opt_route_icc | check_dependencies
	$(call run_icc,rm_icc_zrt_scripts/route_icc.tcl,route_icc)

$(MARKERS_DIR)/route_opt_icc: $(MARKERS_DIR)/route_icc | check_dependencies
	$(call run_icc,rm_icc_zrt_scripts/route_opt_icc.tcl,route_opt_icc)

$(MARKERS_DIR)/chip_finish_icc: $(MARKERS_DIR)/route_opt_icc | check_dependencies
	$(call run_icc,rm_icc_zrt_scripts/chip_finish_icc.tcl,chip_finish_icc)

$(MARKERS_DIR)/metal_fill_icc: $(MARKERS_DIR)/chip_finish_icc | check_dependencies
	$(call run_icc,rm_icc_zrt_scripts/metal_fill_icc.tcl,metal_fill_icc)

$(MARKERS_DIR)/signoff_drc_icc: $(MARKERS_DIR)/metal_fill_icc | check_dependencies
	$(call run_icc,rm_icc_zrt_scripts/signoff_drc_icc.tcl,signoff_drc_icc)

$(MARKERS_DIR)/outputs_icc: $(MARKERS_DIR)/signoff_drc_icc | check_dependencies
	$(call run_icc,rm_icc_zrt_scripts/outputs_icc.tcl,outputs_icc)

define run_icc
	@set -o pipefail
	mkdir -p "$(LOGS_DIR)" "$(REPORTS_DIR)" "$(RESULTS_DIR)" "$(MARKERS_DIR)"
	source "$(DEPS_FILE)"
	cd "$(ICC_ROOT)"
	"$$ICC_SHELL_BIN" $(ICC_OPTIONS) -f "$(ICC_ROOT)/$(1)" 2>&1 | tee "$(LOGS_DIR)/$(2).log"
	date > "$@"
endef

ic: outputs_icc

eco_icc: $(MARKERS_DIR)/eco_icc
$(MARKERS_DIR)/eco_icc: | check_dependencies
	$(call run_icc,rm_icc_zrt_scripts/eco_icc.tcl,eco_icc)
eco: eco_icc

focal_opt_icc: $(MARKERS_DIR)/focal_opt_icc
$(MARKERS_DIR)/focal_opt_icc: $(MARKERS_DIR)/chip_finish_icc | check_dependencies
	$(call run_icc,rm_icc_zrt_scripts/focal_opt_icc.tcl,focal_opt_icc)
focal_opt: focal_opt_icc

focal_cleanup_icc: $(MARKERS_DIR)/focal_cleanup_icc
$(MARKERS_DIR)/focal_cleanup_icc: $(MARKERS_DIR)/focal_opt_icc | check_dependencies
	$(call run_icc,rm_icc_zrt_scripts/focal_cleanup_icc.tcl,focal_cleanup_icc)
focal_cleanup: focal_cleanup_icc

focal_targeted_icc: $(MARKERS_DIR)/focal_targeted_icc
$(MARKERS_DIR)/focal_targeted_icc: $(MARKERS_DIR)/focal_opt_icc | check_dependencies
	$(call run_icc,rm_icc_zrt_scripts/focal_targeted_icc.tcl,focal_targeted_icc)
focal_targeted: focal_targeted_icc

audit_timing_icc: $(MARKERS_DIR)/audit_timing_icc
$(MARKERS_DIR)/audit_timing_icc: $(MARKERS_DIR)/metal_fill_icc | check_dependencies
	$(call run_icc,rm_icc_zrt_scripts/audit_timing_icc.tcl,audit_timing_icc)
audit_timing: audit_timing_icc

clean_all: clean

clean:
	@set -o pipefail
	test "$(ICC_ROOT)" != "/"
	rm -rf -- "$(LOGS_DIR)" "$(REPORTS_DIR)" "$(RESULTS_DIR)" \
		"$(PNA_OUTPUT_DIR)" "$(MARKERS_DIR)" "$(MW_DESIGN_LIBRARY)"
