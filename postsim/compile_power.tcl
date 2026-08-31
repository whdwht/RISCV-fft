# Compatibility entry point. The maintained PrimeTime PX flow lives in pt/.
set script_dir [file dirname [file normalize [info script]]]
source [file normalize [file join $script_dir .. pt compile_power.tcl]]
