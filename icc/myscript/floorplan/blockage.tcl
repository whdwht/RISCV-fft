# blockage: 覆盖整个顶部宏带 (指令SRAM + gap + 数据SRAM), 区域内不布标准单元
# bbox 由 icc_setup.tcl 联动推导: [52, 355.07] -> [458.72, 593.00]
create_placement_blockage -type hard \
    -bbox [list [list $BLOCK_X0 $BLOCK_Y0] [list $BLOCK_X1 $BLOCK_Y1]]
