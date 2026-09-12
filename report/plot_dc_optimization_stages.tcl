#!/usr/bin/env tclsh

# Generate a compact SVG comparison of the three DC optimization stages.
# Values are parsed from the reports so rerunning DC and then this script keeps
# the chart synchronized with the latest synthesis results.

set script_dir [file dirname [file normalize [info script]]]
set output_svg [expr {$argc >= 1
    ? [file normalize [lindex $argv 0]]
    : [file join $script_dir dc_optimization_stages.svg]}]

proc read_text {path} {
    set stream [open $path r]
    fconfigure $stream -encoding utf-8
    set contents [read $stream]
    close $stream
    return $contents
}

proc report_value {path pattern description} {
    set contents [read_text $path]
    if {![regexp -line -- $pattern $contents -> value]} {
        error "Cannot find $description in $path"
    }
    return [expr {double($value)}]
}

set pre_setup_report  [file join $script_dir soc_ahblite.pre_hold_fix.timing_setup.rpt]
set pre_hold_report   [file join $script_dir soc_ahblite.pre_hold_fix.timing_hold.rpt]
set pre_qor_report    [file join $script_dir soc_ahblite.pre_hold_fix.qor.rpt]
set hold_qor_report   [file join $script_dir soc_ahblite.post_hold_fix.qor.rpt]
set final_setup_report [file join $script_dir soc_ahblite.timing_setup.rpt]
set final_hold_report  [file join $script_dir soc_ahblite.timing_hold.rpt]
set final_qor_report   [file join $script_dir soc_ahblite.rpt]

set timing_slack_pattern {^\s*slack \([^)]*\)\s+(-?[0-9.]+)}
set critical_slack_pattern {^\s*Critical Path Slack:\s+(-?[0-9.]+)}
set worst_hold_pattern {^\s*Worst Hold Violation:\s+(-?[0-9.]+)}
set drc_pattern {^\s*Nets With Violations:\s+([0-9.]+)}

set setup_values [list \
    [report_value $pre_setup_report $timing_slack_pattern "pre-hold setup slack"] \
    [report_value $hold_qor_report $critical_slack_pattern "post-hold setup slack"] \
    [report_value $final_setup_report $timing_slack_pattern "final setup slack"]]

set hold_values [list \
    [report_value $pre_hold_report $timing_slack_pattern "pre-hold hold slack"] \
    [report_value $hold_qor_report $worst_hold_pattern "post-hold hold violation"] \
    [report_value $final_hold_report $timing_slack_pattern "final hold slack"]]

set drc_values [list \
    [report_value $pre_qor_report $drc_pattern "pre-hold DRC violations"] \
    [report_value $hold_qor_report $drc_pattern "post-hold DRC violations"] \
    [report_value $final_qor_report $drc_pattern "final DRC violations"]]

set stage_colors {#4C78A8 #F28E2B #59A14F}
set stage_labels {{初次 compile_ultra 后} {Hold-only 修复后} {联合增量修复后}}
set x_centers {330 650 970}

proc svg_text {stream x y text size anchor color weight} {
    puts $stream [format \
        {<text x="%.1f" y="%.1f" text-anchor="%s" font-size="%d" fill="%s" font-weight="%s">%s</text>} \
        $x $y $anchor $size $color $weight $text]
}

proc value_y {value minimum maximum top height} {
    return [expr {$top + ($maximum - $value) * $height / ($maximum - $minimum)}]
}

proc draw_panel {stream top title unit values value_labels minimum maximum ticks colors x_centers} {
    set left 150
    set right 1145
    set plot_top [expr {$top + 38}]
    set plot_height 145
    set plot_bottom [expr {$plot_top + $plot_height}]

    svg_text $stream 55 [expr {$top + 20}] $title 21 start #202124 600
    svg_text $stream 1138 [expr {$top + 20}] $unit 15 end #5F6368 normal

    foreach tick $ticks {
        lassign $tick tick_value tick_label
        set y [value_y $tick_value $minimum $maximum $plot_top $plot_height]
        set line_color [expr {abs($tick_value) < 1.0e-12 ? "#7A7F87" : "#E6E8EB"}]
        set line_width [expr {abs($tick_value) < 1.0e-12 ? 1.5 : 1.0}]
        puts $stream [format \
            {<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s" stroke-width="%.1f"/>} \
            $left $y $right $y $line_color $line_width]
        svg_text $stream [expr {$left - 15}] [expr {$y + 5}] $tick_label 14 end #6B7280 normal
    }

    set zero_y [value_y 0.0 $minimum $maximum $plot_top $plot_height]
    set bar_width 112
    for {set index 0} {$index < 3} {incr index} {
        set value [lindex $values $index]
        set label [lindex $value_labels $index]
        set color [lindex $colors $index]
        set center [lindex $x_centers $index]
        set value_position [value_y $value $minimum $maximum $plot_top $plot_height]
        set x [expr {$center - $bar_width / 2.0}]

        if {abs($value) < 1.0e-12} {
            puts $stream [format \
                {<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="4"/>} \
                $x $zero_y [expr {$x + $bar_width}] $zero_y $color]
            set label_y [expr {$zero_y - 9}]
        } elseif {$value > 0.0} {
            set bar_top $value_position
            set bar_height [expr {$zero_y - $value_position}]
            if {$bar_height < 2.0} {
                set bar_height 2.0
                set bar_top [expr {$zero_y - $bar_height}]
            }
            puts $stream [format \
                {<rect x="%.1f" y="%.1f" width="%d" height="%.1f" rx="3" fill="%s"/>} \
                $x $bar_top $bar_width $bar_height $color]
            set label_y [expr {$bar_top - 8}]
        } else {
            set bar_top $zero_y
            set bar_height [expr {$value_position - $zero_y}]
            puts $stream [format \
                {<rect x="%.1f" y="%.1f" width="%d" height="%.1f" rx="3" fill="%s"/>} \
                $x $bar_top $bar_width $bar_height $color]
            set label_y [expr {$value_position - 8}]
        }
        svg_text $stream $center $label_y $label 16 middle #202124 600
    }

    puts $stream [format \
        {<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="#B8BDC5" stroke-width="1"/>} \
        $left $plot_bottom $right $plot_bottom]
}

set stream [open $output_svg w]
fconfigure $stream -encoding utf-8 -translation lf
puts $stream {<?xml version="1.0" encoding="UTF-8"?>}
puts $stream {<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="900" viewBox="0 0 1200 900">}
puts $stream {<rect width="1200" height="900" fill="#FFFFFF"/>}
puts $stream {<style>text { font-family: "WenQuanYi Micro Hei", "Microsoft YaHei", sans-serif; }</style>}

svg_text $stream 600 48 {DC 三阶段时序与 DRC 对比} 29 middle #202124 700
svg_text $stream 600 76 {functional 模式 · 3.0 ns 时钟周期 · slack 为正表示满足约束} 16 middle #6B7280 normal

draw_panel $stream 105 {Setup slack} {(ns)} $setup_values \
    {+0.0003 -1.26 +0.0002} -1.40 0.20 \
    {{0.20 {+0.20}} {0.00 {0}} {-0.70 {-0.70}} {-1.40 {-1.40}}} \
    $stage_colors $x_centers

draw_panel $stream 340 {Hold slack} {(ns)} $hold_values \
    {-0.1119 0.00 +0.0003} -0.13 0.03 \
    {{0.03 {+0.03}} {0.00 {0}} {-0.065 {-0.065}} {-0.13 {-0.13}}} \
    $stage_colors $x_centers

draw_panel $stream 575 {DRC 违例网络数} {(count)} $drc_values \
    {0 45 0} 0.0 50.0 \
    {{50 {50}} {25 {25}} {0 {0}}} \
    $stage_colors $x_centers

for {set index 0} {$index < 3} {incr index} {
    set center [lindex $x_centers $index]
    set color [lindex $stage_colors $index]
    set label [lindex $stage_labels $index]
    puts $stream [format \
        {<circle cx="%.1f" cy="832" r="6" fill="%s"/>} \
        [expr {$center - 83}] $color]
    svg_text $stream [expr {$center - 70}] 838 $label 16 start #34373C 500
}

svg_text $stream 600 878 \
    {注：Hold-only 阶段只保存两位小数的 QoR，0.00 表示无 hold 违例。} \
    14 middle #73777F normal

puts $stream {</svg>}
close $stream

puts "Wrote $output_svg"
