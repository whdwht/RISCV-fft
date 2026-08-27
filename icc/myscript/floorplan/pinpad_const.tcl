#side 1:left, side 2:top, 3:right, 4:bottom
# soc_ahblite 引脚约束 (原 fft8_top APB 引脚已全部替换)
# 顶边(side 2)不放引脚: 顶部为双SRAM横带+电源环
# 层统一 M5 (高于电源环 M3/M4, 避免冲突)
# 注意: 端口名需与综合网表一致, 可用 report_port 或查看 soc_ahblite.mapped.v 核对

# ---- side 4 (底边): 时钟与控制信号, 远离顶部SRAM, 时钟走线短 ----
set_pin_physical_constraints -pin_name sys_clk      -layers {M5} -side 4
set_pin_physical_constraints -pin_name rstn         -layers {M5} -side 4
set_pin_physical_constraints -pin_name load_en      -layers {M5} -side 4
set_pin_physical_constraints -pin_name inst_write   -layers {M5} -side 4
set_pin_physical_constraints -pin_name write_start  -layers {M5} -side 4

# ---- side 1 (左边): 程序写入数据总线 32bit, 单独占一侧均匀分布 ----
set_pin_physical_constraints -pin_name {inst_wdata[31]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[30]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[29]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[28]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[27]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[26]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[25]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[24]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[23]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[22]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[21]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[20]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[19]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[18]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[17]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[16]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[15]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[14]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[13]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[12]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[11]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[10]} -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[9]}  -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[8]}  -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[7]}  -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[6]}  -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[5]}  -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[4]}  -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[3]}  -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[2]}  -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[1]}  -layers {M5} -side 1
set_pin_physical_constraints -pin_name {inst_wdata[0]}  -layers {M5} -side 1

# ---- side 3 (右边): 外设接口 uart/spi/i2c/dma 按功能聚簇 ----
set_pin_physical_constraints -pin_name uart_rx      -layers {M5} -side 3
set_pin_physical_constraints -pin_name uart_tx      -layers {M5} -side 3
set_pin_physical_constraints -pin_name spi_rstn     -layers {M5} -side 3
set_pin_physical_constraints -pin_name cs_n_ext     -layers {M5} -side 3
set_pin_physical_constraints -pin_name sclk_ext     -layers {M5} -side 3
set_pin_physical_constraints -pin_name spi_di       -layers {M5} -side 3
set_pin_physical_constraints -pin_name cs_n         -layers {M5} -side 3
set_pin_physical_constraints -pin_name sclk         -layers {M5} -side 3
set_pin_physical_constraints -pin_name spi_do       -layers {M5} -side 3
set_pin_physical_constraints -pin_name rx_dma_ack   -layers {M5} -side 3
set_pin_physical_constraints -pin_name tx_dma_ack   -layers {M5} -side 3
set_pin_physical_constraints -pin_name rx_dma_req   -layers {M5} -side 3
set_pin_physical_constraints -pin_name tx_dma_req   -layers {M5} -side 3
set_pin_physical_constraints -pin_name sda_ext      -layers {M5} -side 3
set_pin_physical_constraints -pin_name scl_ext      -layers {M5} -side 3
set_pin_physical_constraints -pin_name sda          -layers {M5} -side 3
set_pin_physical_constraints -pin_name scl          -layers {M5} -side 3
