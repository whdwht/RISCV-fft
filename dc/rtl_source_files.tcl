################################################################################
# Define rtl search paths
################################################################################
# day1 RISC_V 工程根目录(含 FFT 的 SoC)
set DAY1_RV "/home/master/project/IC_class/RISC_V"

# 各子目录加入搜索路径(含 inc/ 以便解析 `include "prim_assert.svh"` 等)
append RTL_SEARCH_PATHS " ${DAY1_RV}/rtl"
append RTL_SEARCH_PATHS " ${DAY1_RV}/rtl/soc"
append RTL_SEARCH_PATHS " ${DAY1_RV}/rtl/fft"
append RTL_SEARCH_PATHS " ${DAY1_RV}/ibex"
append RTL_SEARCH_PATHS " ${DAY1_RV}/inc"

################################################################################
# Define rtl files
################################################################################
# 注意: SystemVerilog package 必须在引用它的模块之前 analyze!
#   (否则 DC 遇到 import xxx::* 时会去搜 xxx.pvk 并报 VER-292)
# 故 system_pkg.sv / ibex_pkg.sv 放在最前。

# ---- packages (必须最先) ----
append RTL_SOURCE_FILES " system_pkg.sv"
append RTL_SOURCE_FILES " ibex_pkg.sv"

# ---- SoC glue ----
append RTL_SOURCE_FILES " soc_ahblite.sv"
append RTL_SOURCE_FILES " system_itf.sv"
append RTL_SOURCE_FILES " sub_system.sv"
append RTL_SOURCE_FILES " ahblite.sv"
append RTL_SOURCE_FILES " decoder.sv"
append RTL_SOURCE_FILES " data_sram.sv"
append RTL_SOURCE_FILES " inst_sram.sv"
append RTL_SOURCE_FILES " rom.sv"
append RTL_SOURCE_FILES " rom_32x64.sv"

# ---- FFT ----
append RTL_SOURCE_FILES " fft8_top.sv"
append RTL_SOURCE_FILES " fft8_pl.v"
append RTL_SOURCE_FILES " fft8_stages.v"

# ---- ibex CPU core (除 ibex_pkg) ----
append RTL_SOURCE_FILES " ibex_core.sv"
append RTL_SOURCE_FILES " ibex_alu.sv"
append RTL_SOURCE_FILES " ibex_branch_predict.sv"
append RTL_SOURCE_FILES " ibex_compressed_decoder.sv"
append RTL_SOURCE_FILES " ibex_controller.sv"
append RTL_SOURCE_FILES " ibex_counter.sv"
append RTL_SOURCE_FILES " ibex_cs_registers.sv"
append RTL_SOURCE_FILES " ibex_csr.sv"
append RTL_SOURCE_FILES " ibex_decoder.sv"
append RTL_SOURCE_FILES " ibex_dummy_instr.sv"
append RTL_SOURCE_FILES " ibex_ex_block.sv"
append RTL_SOURCE_FILES " ibex_fetch_fifo.sv"
append RTL_SOURCE_FILES " ibex_icache.sv"
append RTL_SOURCE_FILES " ibex_id_stage.sv"
append RTL_SOURCE_FILES " ibex_if_stage.sv"
append RTL_SOURCE_FILES " ibex_load_store_unit.sv"
append RTL_SOURCE_FILES " ibex_multdiv_fast.sv"
append RTL_SOURCE_FILES " ibex_multdiv_slow.sv"
append RTL_SOURCE_FILES " ibex_pmp.sv"
append RTL_SOURCE_FILES " ibex_prefetch_buffer.sv"
append RTL_SOURCE_FILES " ibex_register_file_ff.sv"
append RTL_SOURCE_FILES " ibex_register_file_fpga.sv"
append RTL_SOURCE_FILES " ibex_wb_stage.sv"
append RTL_SOURCE_FILES " prim_clock_gating.v"
