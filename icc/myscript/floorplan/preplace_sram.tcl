# soc_ahblite: 两块 RA1HD_4KB (177.86 x 221.93) 预摆放
# 指令SRAM(x_isram_ahbl/i_sram_block) -> 左上
# 数据SRAM(x_data_sram/i_sram_block) -> 右上
# 坐标/keepout 均取自 icc_setup.tcl 中的联动变量

#----------------------------------------------------------
# 1. 指令 SRAM (左上)
#----------------------------------------------------------
# unfix and unplace SRAM (解除默认固定状态, 否则无法移动)
set_undoable_attribute [get_cells -all x_isram_ahbl/i_sram_block] is_fixed  {0}
set_undoable_attribute [get_cells -all x_isram_ahbl/i_sram_block] is_placed {0}

# 摆放到指定坐标 (core 顶部左侧)
move_objects -x $INST_SRAM_X -y $INST_SRAM_Y [get_cells -all x_isram_ahbl/i_sram_block]

# 连接 VDD/VSS: 沿宏四侧(跳过底侧)生成 M3横/M4竖 PG 接线
# (与电源环/strap 同层, 底侧朝向标准单元区, 跳过以留出通道)
preroute_instances -connect_instances specified \
    -cells [get_cells -all x_isram_ahbl/i_sram_block] \
    -select_net_by_type pg \
    -target_directions four_sides -skip_bottom_side \
    -primary_routing_layer specified \
    -specified_horizontal_layer M3 -specified_vertical_layer M4

# 宏四周禁布标准单元, 预留布线通道 (左 下 右 上)
set_keepout_margin -type hard \
    -outer [list $SRAM_KEEPOUT $SRAM_KEEPOUT $SRAM_KEEPOUT $SRAM_KEEPOUT] \
    [get_cells -all x_isram_ahbl/i_sram_block]

#----------------------------------------------------------
# 2. 数据 SRAM (右上)
#----------------------------------------------------------
set_undoable_attribute [get_cells -all x_data_sram/i_sram_block] is_fixed  {0}
set_undoable_attribute [get_cells -all x_data_sram/i_sram_block] is_placed {0}

move_objects -x $DATA_SRAM_X -y $DATA_SRAM_Y [get_cells -all x_data_sram/i_sram_block]

preroute_instances -connect_instances specified \
    -cells [get_cells -all x_data_sram/i_sram_block] \
    -select_net_by_type pg \
    -target_directions four_sides -skip_bottom_side \
    -primary_routing_layer specified \
    -specified_horizontal_layer M3 -specified_vertical_layer M4

set_keepout_margin -type hard \
    -outer [list $SRAM_KEEPOUT $SRAM_KEEPOUT $SRAM_KEEPOUT $SRAM_KEEPOUT] \
    [get_cells -all x_data_sram/i_sram_block]
