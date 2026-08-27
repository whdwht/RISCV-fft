# ========== PT功耗分析: tc典型角 + SPEF + 门级VCD(定向窗口) ==========
# 运行前提: post_sim/ 下已用新tb重跑 sim_min.sh 生成 tb_soc.vcd
# 运行方式: pt_shell -f compile_power.tcl | tee power.log

# 1. 设计名
set DESIGN_NAME "soc_ahblite"

# 2. 库路径 (TODO: 替换 <PT_DATA_PATH> 为ICC输出所在目录)
set stdCell_path "/home/master/project1/day2/library"
set sram_path    "/mnt/hgfs/share/sram_hde/gen_hde"
set pt_data_path "/home/master/project1/day4/PT"

# 3. 搜索路径
lappend search_path $stdCell_path
lappend search_path $sram_path

# 4. 目标库: tc典型角(TT/1.0V/25C) + SRAM tt_25c 配对 (平均功耗报告惯例)
set target_library "tcbn65gplusbwp12ttc.db"
set sram_library   "RA1HD_4KB_tt_1p00v_1p00v_25c.db"

# 6. 链接库 (必须含SRAM, 否则link失败且SRAM功耗缺失)
set_app_var link_library "* $target_library $sram_library"

lappend synlib_wait_for_design_license "DesignWare-Foundation"

# 7. 配置: 逐时刻时序功耗
set_app_var delay_calc_waveform_analysis_mode full_design
set_app_var pba_recalculate_full_path true
set power_enable_analysis TRUE
set power_analysis_mode time_based

# 8. 读网表 & SDC (slack收敛那一轮ICC的输出)
read_verilog $pt_data_path/soc_ahblite.output.v
current_design $DESIGN_NAME
link
read_sdc $pt_data_path/soc_ahblite.output.sdc

# 8.5 读SPEF: 线电容计入开关功耗
read_parasitics -format spef $pt_data_path/soc_ahblite.output.spef.max

# 9. 读VCD: 门级VCD实例名与网表一致, 不加-rtl
#    窗口与tb导出窗一致(10300~15800ns): 计算段, 跳过装载
#    注: 若报 strip_path 找不到, 尝试去掉 -strip_path 选项或改为 x_soc
read_vcd ./tb_soc.vcd -time {10300 15800} -strip_path tb_soc/x_soc
report_switching_activity -list_not_annotated > "list_not_annotated_power.rpt"

# 10. 检查与计算
check_power
update_power

#---------------- Report Section ----------------
# 总功耗(内部+开关+漏电 三分量)
report_power > "power_vcd.rpt"
# 层次分解(看CPU/FFT/两块SRAM各自占比)
report_power -hier > "power_vcd_hier.rpt"
