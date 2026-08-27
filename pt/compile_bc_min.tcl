# ============ compile_bc_min.tcl : bc角 + spef.min ============
# 1. 设计名: 与顶层模块一致
set DESIGN_NAME "soc_ahblite"

# 2. 库路径 (TODO: 替换为你的实际绝对路径)
set stdCell_path "/home/master/project1/day2/library"   ;# 例: /home/master/project1/day2/library
set sram_path    "/mnt/hgfs/share/sram_hde/gen_hde"      ;# 例: /home/master/Project/icc_project/sram_hde/gen_hde
set pt_data_path "/home/master/project1/day4/PT"   ;# 你拷贝ICC结果的目录, 例: /home/master/PT/data

# 3. 搜索路径
lappend search_path $stdCell_path
lappend search_path $sram_path

# 4. 目标库: tc典型角; SRAM按角配对tt
set target_library "tcbn65gplusbwp12tbc.db"
set sram_library   "RA1HD_4KB_ff_1p10v_1p10v_m40c.db"

# 6. 链接库: 标准单元 + SRAM (缺SRAM会 link 报 RA1HD_4KB undefined)
set_app_var link_library "* $target_library $sram_library"

# Designware
lappend synlib_wait_for_design_license "DesignWare-Foundation"

# 7. 高精度延迟计算配置 (沿用模板)
set_app_var delay_calc_waveform_analysis_mode full_design
set_app_var read_parasitics_load_locations true
set_app_var pba_recalculate_full_path true
set timing_ocvm_enable_distance_analysis true
set timing_reduce_parallel_arc false

# 9. 读网表 & SDC (ICC输出, 已拷入 $pt_data_path)
read_verilog $pt_data_path/soc_ahblite.output.v
current_design $DESIGN_NAME
link
read_sdc $pt_data_path/soc_ahblite.output.sdc

# 10. 读寄生参数: min分析配 spef.min
read_parasitics -format spef $pt_data_path/soc_ahblite.output.spef.min
report_annotated_parasitics -internal_nets -list_not_annotated -max_nets 320 -constant_arcs > "not_annotated_bc_min.rpt"

#---------------- Report Section (文件名加_tc后缀, 防三角互相覆盖) ----------------
check_constraints -verbose > "check_constr_bc_min.rpt"

update_timing -full
check_timing -verbose > "check_timing_bc_min.rpt"   ;# 模板笔误 -verbos 已修正

report_timing -exclude [all_outputs] -max_paths 20 -delay_type min_max -pba_mode path -derate -slack_lesser_than 100 > "timing_no_inout_bc_min.rpt"
report_disable_timing > "disabled_timing_bc_min.rpt"

# 13. 写SDF (命名带角, 避免与后续bc/wc冲突)
write_sdf my_bc_min.sdf
