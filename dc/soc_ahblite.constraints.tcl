# set clock period (ns)
# 首跑: 10ns (100MHz), 跑通后再逐级收紧
set T_CLKV_PER 10.0
# set T_CLKV_PER 5.0
# set T_CLKV_PER 2.5
# set T_CLKV_PER 1.25

# set the time of the rising edge
set T_CLKV_RISE 0
# set the time of the falling edge
set T_CLKV_FALL [expr $T_CLKV_PER/2]

# create clock
# 'sys_clk' is the name of clock port in soc_ahblite top module
create_clock -name clk1 -period $T_CLKV_PER -waveform [list $T_CLKV_RISE $T_CLKV_FALL] sys_clk

# set input/output delay
set_input_delay 0 -clock clk1 -max [all_inputs]
set_input_delay 0 -clock clk1 -min [all_inputs]
set_output_delay 0 -clock clk1 [all_outputs]
