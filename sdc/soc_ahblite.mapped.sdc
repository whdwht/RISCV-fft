###################################################################

# Created by write_sdc on Fri Aug 28 16:11:44 2026

###################################################################
set sdc_version 2.1

set_units -time ns -resistance kOhm -capacitance pF -voltage V -current mA
set_operating_conditions -max WCCOM -max_library tcbn65gplusbwp12twc -min BCCOM -min_library tcbn65gplusbwp12tbc
set_max_transition 0.5 [current_design]
set_max_fanout 32 [current_design]
set_max_capacitance 0.2 [current_design]
set_load -pin_load 0.05 [get_ports uart_tx]
set_load -pin_load 0.05 [get_ports cs_n]
set_load -pin_load 0.05 [get_ports sclk]
set_load -pin_load 0.05 [get_ports spi_do]
set_load -pin_load 0.05 [get_ports rx_dma_req]
set_load -pin_load 0.05 [get_ports tx_dma_req]
set_load -pin_load 0.05 [get_ports sda]
set_load -pin_load 0.05 [get_ports scl]
set_case_analysis 0 [get_ports load_en]
set_case_analysis 0 [get_ports inst_write]
set_case_analysis 0 [get_ports write_start]
create_clock [get_ports sys_clk]  -name clk1  -period 3  -waveform {0 1.5}
set_clock_uncertainty -setup 0.2  [get_clocks clk1]
set_clock_uncertainty -hold 0.05  [get_clocks clk1]
set_clock_transition -min -fall 0.1 [get_clocks clk1]
set_clock_transition -min -rise 0.1 [get_clocks clk1]
set_clock_transition -max -fall 0.1 [get_clocks clk1]
set_clock_transition -max -rise 0.1 [get_clocks clk1]
set_false_path -fall_from [get_ports rstn]
set_false_path   -from [list [get_ports uart_rx] [get_ports spi_rstn] [get_ports cs_n_ext] [get_ports sclk_ext] [get_ports spi_di] [get_ports rx_dma_ack] [get_ports tx_dma_ack] [get_ports sda_ext] [get_ports scl_ext]]
set_input_delay -clock clk1  -max -rise 0.5  [get_ports rstn]
set_input_delay -clock clk1  -min -rise 0.1  [get_ports rstn]
set_input_transition -max 0.2  [get_ports rstn]
set_input_transition -min 0.2  [get_ports rstn]
