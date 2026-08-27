# Wenxun: disable this rule check to ensure rings and connection will be made
set_preroute_drc_strategy -ignore_discrete_metal_width_rule

create_rectangular_rings -around core -nets GND_SOC -left_segment_layer M4 -right_segment_layer M4 -bottom_segment_layer M3 -top_segment_layer M3 -left_segment_width $POWER_RING_WIDTH -right_segment_width $POWER_RING_WIDTH -bottom_segment_width $POWER_RING_WIDTH -top_segment_width $POWER_RING_WIDTH -left_offset $POWER_RING_PITCH -right_offset $POWER_RING_PITCH -bottom_offset $POWER_RING_PITCH -top_offset $POWER_RING_PITCH -offsets absolute

create_rectangular_rings -around core -nets VDD_SOC -left_segment_layer M4 -right_segment_layer M4 -bottom_segment_layer M3 -top_segment_layer M3 -left_segment_width $POWER_RING_WIDTH -right_segment_width $POWER_RING_WIDTH -bottom_segment_width $POWER_RING_WIDTH -top_segment_width $POWER_RING_WIDTH -left_offset [expr 2*$POWER_RING_PITCH + $POWER_RING_WIDTH] -right_offset [expr 2*$POWER_RING_PITCH + $POWER_RING_WIDTH] -bottom_offset [expr 2*$POWER_RING_PITCH + $POWER_RING_WIDTH] -top_offset [expr 2*$POWER_RING_PITCH + $POWER_RING_WIDTH] -offsets absolute

# TO DO: Create your Ring and Straps, must exists rings and straps both.
# e.g. create_power_straps -nets {xxx} -direction vertical -start_at [$POS] -width 5 -num_placement_strap 1 -start_low_ends coordinate -start_low_ends_coordinate [$POS1] -start_high_ends coordinate -start_high_ends_coordinate [$POS2] -layer M4 -extend_low_ends off -extend_high_ends off

# 两块SRAM之间窄gap内的一对垂直供电strap (VDD_SOC + GND_SOC, M4, 与环同宽)
# 下端: 固定在SRAM底边(坐标控制, 不延伸); 上端: 延伸至第一个同网目标(顶部环)并打孔连接
# 若 -start_low_ends coordinate 在当前版本报错, 删去该行及坐标行,
# 改用 -extend_low_ends off 单独测试
create_power_straps -nets VDD_SOC -direction vertical -layer M4 \
    -width $POWER_RING_WIDTH -start_at $STRAP_VDD_X \
    -start_low_ends coordinate -start_low_ends_coordinate $STRAP_LOW_Y \
    -extend_low_ends off \
    -extend_high_ends to_first_target

create_power_straps -nets GND_SOC -direction vertical -layer M4 \
    -width $POWER_RING_WIDTH -start_at $STRAP_GND_X \
    -start_low_ends coordinate -start_low_ends_coordinate $STRAP_LOW_Y \
    -extend_low_ends off \
    -extend_high_ends to_first_target
