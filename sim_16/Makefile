PROJECT_ROOT   := $(abspath ..)
SOC_ROOT       ?= /home/master/project/IC_class/RISC_V
TECH_LIB       ?= /home/master/project/IC_class/library/tcbn65gplusbwp12t.v
GCC_PROJECT    ?= /home/master/project/IC_class/gcc
RISCV_TOOLCHAIN_BIN ?= /home/master/toolchain/lowrisc-toolchain-gcc-rv32imc-20220210-1/bin
SW_VARIANT     ?= optimized
OPT_LEVEL      ?= O3
SW_SRC         ?= $(CURDIR)/sw/fft16_$(SW_VARIANT).c
LINKER_SCRIPT  ?= $(CURDIR)/sw/link.ld
VMEM           ?= $(CURDIR)/sw/gcc.vmem
BUILD_DIR      ?= $(CURDIR)/build
TIMEOUT_CYCLES ?= 20000

VCS            ?= vcs
VERDI          ?= verdi
FILELIST       := $(CURDIR)/rtl.f
SIMV           := $(BUILD_DIR)/simv
FSDB           := $(BUILD_DIR)/tb_soc_fft16.fsdb
SW_BUILD_DIR   := $(BUILD_DIR)/sw
RISCV_GCC      := $(RISCV_TOOLCHAIN_BIN)/riscv32-unknown-elf-gcc
RISCV_OBJDUMP  := $(RISCV_TOOLCHAIN_BIN)/riscv32-unknown-elf-objdump
RISCV_READELF  := $(RISCV_TOOLCHAIN_BIN)/riscv32-unknown-elf-readelf

VALID_SW_VARIANTS := reference optimized
VALID_OPT_LEVELS  := O0 O1 O2 O3 Os
SW_CFLAGS := -march=rv32imc -mabi=ilp32 -static -mcmodel=medany \
	-fvisibility=hidden -ffreestanding -fno-builtin \
	-fno-asynchronous-unwind-tables -fno-unwind-tables \
	-fno-jump-tables -fno-tree-switch-conversion \
	-msmall-data-limit=0 -mno-relax -nostdlib -nostartfiles \
	-Wall -Wextra -Werror -g -$(OPT_LEVEL) -fstack-usage

VCS_OPTS ?=
SIM_OPTS ?=

COMMON_VCS_OPTS := -full64 -sverilog -timescale=1ns/1ps -top tb_soc \
	+define+FPGA +define+VCS_SIMULATOR+FUNCTIONAL \
	+incdir+$(SOC_ROOT)/ibex +incdir+$(SOC_ROOT)/inc \
	+notimingcheck +nospecify -debug_access+all -kdb -Mupdate -licqueue +error+100

export PROJECT_ROOT
export SOC_ROOT
export TECH_LIB

.PHONY: all sw compile run wave verdi benchmark clean help check_paths check_sw_options

all: run

check_sw_options:
	@case " $(VALID_SW_VARIANTS) " in *" $(SW_VARIANT) "*) ;; *) \
	  echo "ERROR: SW_VARIANT must be one of: $(VALID_SW_VARIANTS)"; exit 2;; esac
	@case " $(VALID_OPT_LEVELS) " in *" $(OPT_LEVEL) "*) ;; *) \
	  echo "ERROR: OPT_LEVEL must be one of: $(VALID_OPT_LEVELS)"; exit 2;; esac

check_paths:
	@test -d "$(SOC_ROOT)" || { echo "ERROR: SOC_ROOT does not exist: $(SOC_ROOT)"; exit 2; }
	@test -f "$(SOC_ROOT)/rtl/soc/soc_ahblite.sv" || { echo "ERROR: missing SoC RTL under $(SOC_ROOT)"; exit 2; }
	@test -f "$(SOC_ROOT)/sram/RA1HD_4KB.v" || { echo "ERROR: missing SRAM model under $(SOC_ROOT)"; exit 2; }
	@test -f "$(TECH_LIB)" || { echo "ERROR: standard-cell model does not exist: $(TECH_LIB)"; exit 2; }

sw: check_sw_options
	@test -f "$(SW_SRC)" || { echo "ERROR: missing $(SW_SRC)"; exit 2; }
	@test -f "$(GCC_PROJECT)/Makefile" || { echo "ERROR: missing $(GCC_PROJECT)/Makefile"; exit 2; }
	@test -f "$(GCC_PROJECT)/crt0.S" || { echo "ERROR: missing $(GCC_PROJECT)/crt0.S"; exit 2; }
	@test -f "$(LINKER_SCRIPT)" || { echo "ERROR: missing $(LINKER_SCRIPT)"; exit 2; }
	@test -x "$(RISCV_GCC)" || { echo "ERROR: RISC-V GCC does not exist: $(RISCV_GCC)"; exit 2; }
	@mkdir -p "$(SW_BUILD_DIR)"
	@cp "$(SW_SRC)" "$(SW_BUILD_DIR)/gcc.c"
	@cp "$(CURDIR)/sw/fft16_common.h" "$(SW_BUILD_DIR)/fft16_common.h"
	@cp "$(GCC_PROJECT)/crt0.S" "$(SW_BUILD_DIR)/crt0.S"
	@cp "$(LINKER_SCRIPT)" "$(SW_BUILD_DIR)/link.ld"
	@echo "[SW16] Building $(SW_VARIANT) with -$(OPT_LEVEL) using $(RISCV_GCC)"
	@$(MAKE) -C "$(SW_BUILD_DIR)" -f "$(GCC_PROJECT)/Makefile" \
		PROGRAM=gcc SRCS=gcc.c CC="$(RISCV_GCC)" \
		LINKER_SCRIPT=link.ld CRT=crt0.S CFLAGS="$(SW_CFLAGS)" \
		LIBS="-lgcc -Wl,-Map,gcc.map" all
	@$(RISCV_OBJDUMP) -d -S "$(SW_BUILD_DIR)/gcc.elf" > "$(SW_BUILD_DIR)/gcc.dis"
	@bash "$(CURDIR)/check_sw_image.sh" \
		"$(SW_BUILD_DIR)/gcc.elf" "$(SW_BUILD_DIR)/gcc.bin" \
		"$(SW_BUILD_DIR)/gcc.vmem" "$(SW_BUILD_DIR)/gcc.su" \
		"$(RISCV_READELF)" "$(SW_BUILD_DIR)/gcc.sha256"
	@mkdir -p "$(dir $(VMEM))"
	@cmp -s "$(SW_BUILD_DIR)/gcc.vmem" "$(VMEM)" || \
		cp "$(SW_BUILD_DIR)/gcc.vmem" "$(VMEM)"
	@echo "[SW16] Installed $(VMEM)"

compile: check_paths
	@mkdir -p "$(BUILD_DIR)"
	@echo "[VCS] Compiling CPU+FFT16 RTL"
	@cd "$(BUILD_DIR)" && $(VCS) $(COMMON_VCS_OPTS) $(VCS_OPTS) \
		-f "$(FILELIST)" -o "$(SIMV)" -Mdir="$(BUILD_DIR)/csrc" \
		-l "$(BUILD_DIR)/compile.log"

run: sw compile
	@test -f "$(VMEM)" || { echo "ERROR: VMEM does not exist: $(VMEM)"; exit 2; }
	@echo "[SIM] Running self-checking CPU+FFT16 simulation"
	@cd "$(BUILD_DIR)" && "$(SIMV)" \
		+vcs+lic+wait +VMEM="$(VMEM)" +TIMEOUT_CYCLES=$(TIMEOUT_CYCLES) $(SIM_OPTS) \
		-l "$(BUILD_DIR)/run.log"
	@grep -q "CPU+FFT16 TEST PASS" "$(BUILD_DIR)/run.log" || \
		{ echo "ERROR: simulation did not report PASS; see $(BUILD_DIR)/run.log"; exit 1; }

wave: sw compile
	@test -f "$(VMEM)" || { echo "ERROR: VMEM does not exist: $(VMEM)"; exit 2; }
	@echo "[SIM] Running CPU+FFT16 simulation with FSDB dumping"
	@cd "$(BUILD_DIR)" && "$(SIMV)" \
		+vcs+lic+wait +VMEM="$(VMEM)" +TIMEOUT_CYCLES=$(TIMEOUT_CYCLES) \
		+DUMP_FSDB +FSDB="$(FSDB)" $(SIM_OPTS) \
		-l "$(BUILD_DIR)/wave.log"
	@grep -q "CPU+FFT16 TEST PASS" "$(BUILD_DIR)/wave.log" || \
		{ echo "ERROR: simulation did not report PASS; see $(BUILD_DIR)/wave.log"; exit 1; }

verdi:
	@test -f "$(FSDB)" || { echo "ERROR: $(FSDB) not found; run 'make wave' first"; exit 2; }
	@cd "$(BUILD_DIR)" && $(VERDI) -sx -sverilog -f "$(FILELIST)" -ssf "$(FSDB)" &

benchmark:
	@bash "$(PROJECT_ROOT)/run_fft16_sw_benchmark.sh"

clean:
	@echo "[CLEAN] Removing $(BUILD_DIR)"
	@rm -rf "$(BUILD_DIR)"

help:
	@echo "CPU+FFT16 RTL simulation"
	@echo ""
	@echo "Targets:"
	@echo "  make sw       Build the selected C program and update VMEM"
	@echo "  make compile  Compile RTL with VCS"
	@echo "  make run      Compile and run the self-checking test (default)"
	@echo "  make wave     Compile, run, and generate an FSDB"
	@echo "  make verdi    Open the FSDB generated by 'make wave'"
	@echo "  make benchmark Run the resumable software optimization benchmark"
	@echo "  make clean    Remove sim_16/build"
	@echo ""
	@echo "Overrides:"
	@echo "  SOC_ROOT=<path>       SoC/Ibex/SRAM source root"
	@echo "  TECH_LIB=<file>       Standard-cell Verilog model"
	@echo "  GCC_PROJECT=<path>    Course GCC project with crt0.S/link.ld"
	@echo "  RISCV_TOOLCHAIN_BIN=<path>  Directory containing RISC-V GCC"
	@echo "  SW_VARIANT=reference|optimized  C implementation (default: optimized)"
	@echo "  OPT_LEVEL=O0|O1|O2|O3|Os       Compiler optimization (default: O3)"
	@echo "  SW_SRC=<path>         Override the selected C source"
	@echo "  VMEM=<path>           Program image (default: sim_16/sw/gcc.vmem)"
	@echo "  TIMEOUT_CYCLES=<n>    Post-reset timeout (default: 20000)"
	@echo "  VCS_OPTS='<options>'  Extra VCS compile options"
	@echo "  SIM_OPTS='<plusargs>' Extra simulation options"
