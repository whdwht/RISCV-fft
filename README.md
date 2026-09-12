# RISC-V SoC + 8 点 FFT 加速核 —— 前端到签核全流程

基于 lowRISC **Ibex** (RV32IMC) CPU 与**自研 8 点 FFT 流水线加速核**的 SoC，
打通 **RTL 仿真 → DC 综合 → ICC 布局布线 → PrimeTime 签核 → 门级后仿 / 功耗分析** 的完整数字前端流程。

16 点 FFT 采用软硬件协同划分：**2 次 8 点硬件加速核 + CPU 软件合并级（DIT 蝶形）**。

## 成果总览

| 指标 | 数值 | 条件 |
|---|---|---|
| 工艺 | TSMC 65nm `tcbn65gplusbwp12t`，9 层金属 | TLU+ 寄生 |
| 频率 | **333.33 MHz** (3 ns) | 当前 ICC 输出 SDC；wc(SS/0.9V/125℃) 查 setup，bc(FF/1.1V/0℃) 查 hold |
| 面积 | cell 159.6k µm²（含 2×4KB SRAM 宏） | core 430.72×560，die 510.72×640 µm |
| 平均功耗 | 由 PT PX 重跑生成 | tc 角 + spef.max + 3 ns 门级执行窗 VCD，time_based |
| 16 点 FFT 汇编基线 | **506 周期 / 1.518 µs** | 3 ns 时钟；C 优化结果由自动基准脚本实测生成 |

## 16 点 FFT 任务划分（DIT）

```
X[k]   = E[k] + W16^k · O[k]        k = 0..7      (软件合并级)
X[k+8] = E[k] − W16^k · O[k]
E = FFT8(x[0,2,4,...,14])  ← 硬件加速核第 1 次调用 (AHB 从机 @0x4000_0000)
O = FFT8(x[1,3,5,...,15])  ← 硬件加速核第 2 次调用
W16^k: Q10 定点旋转因子 (946/392, 724/724, ...), CPU 用 M 扩展完成复数乘
```

- 硬件侧：全展开 3 级流水 `fft8_pl`（butterfly2 × 12），AHB-Lite 从机接口，
  写 8 字自动触发、读通道带 `valid` 等待态握手（软件无需插 NOP）；
- 软件侧：默认使用 RV32IMC C 程序。reference 版本保持原 E/O 缓存流程，optimized
  版本流式读取 O，并对特殊旋转因子消除或合并乘法；结果仍存 data_sram
  `0x1000_0040~0x1000_00bc`。由于现有 instruction SRAM 的数据端口握手不可用，
  软件镜像强制 `.rodata` 为空，输入与旋转常数均由 RV32 立即数构造。

## 目录结构

```
├── hw/fft8/        自研 FFT 加速核: fft8_top.sv(AHB封装) fft8_pl.v(流水核) fft8_stages.v(蝶形)
├── sw/             fft16.s(汇编主程序) fft16.vmem(机器码) fft16[_ref].cpp(黄金参考) 编译脚本
├── tb/             tb_soc_day1.sv(RTL仿真) tb_soc_postsim.sv(门级后仿+定向VCD)
├── dc/             DC 综合 4 脚本 + soc_ahblite.rpt(面积/时序报告)
├── icc/            ICC Makefile、dependencies.sh、rm_setup/、主流程 RM 与定制 floorplan/PG 脚本
├── pt/             Makefile + 三角STA/SDF + PT PX功耗脚本，输出到 runs/
├── postsim/        功能预跑/max/min SDF后仿 + 自检testbench，输出到 build/
├── sim_16/sw/       FFT16 reference/optimized C、4KB SRAM 链接脚本
├── run_fft16_sw_benchmark.sh  C 优化、前后仿、功耗与 PNG 报告一键入口
└── doc/results/    PT 三角时序报告 / 功耗报告 / ICC QoR
```

## FFT16 C 软件优化基准

当前机器若没有 Synopsys 许可证，可先完成全部交叉编译和 SRAM/ISA/栈检查：

```bash
./run_fft16_sw_benchmark.sh --build-only
./run_fft16_sw_benchmark.sh --dry-run
```

在有 VCS 与 PrimeTime/PrimePower 许可证的无桌面服务器上运行完整流程：

```bash
./run_fft16_sw_benchmark.sh
# 中断、许可证暂时不可用或工具故障修复后继续
./run_fft16_sw_benchmark.sh --resume
```

VCS/PrimeTime 使用浮动许可证。脚本默认设置 Synopsys 排队模式，并给 VCS
编译及仿真加入许可证等待选项；许可证服务器恢复或有令牌释放后会自动继续。
可随时用 `Ctrl-C` 中断，之后仍用 `--resume` 从已通过的阶段续跑。

脚本会筛选 reference 与 optimized C 的 `-O1/-O2/-O3/-Os`，对入选版本执行
RTL 前仿、门级功能/功耗后仿和 PT PX，并对最终版本追加 max/min SDF 后仿。
状态和大型中间文件保存在 `benchmark_runs/fft16_sw/`；最终数据保存为
`report/fft16_sw_optimization.csv`、`report/fft16_sw_optimal_breakdown.csv` 和
`report/fft16_sw_optimization.md`。无头绘图除跨版本汇总图外，还会生成当前最优方案的
`report/fft16_sw_optimal_cycle_pies.png` 与 `report/fft16_sw_optimal_energy_pies.png`：
前者给出完整算法阶段及 FFT2 后旋转/合并的周期构成，后者分别按硬件层次和
internal/switching/leakage 给出窗口能耗来源。已有状态可用
`./run_fft16_sw_benchmark.sh --render-only` 重新绘图。图片使用 PyCairo 直接生成 PNG，
不需要桌面、Matplotlib、NumPy 或 Pandas。
该基准的系统性能定义为 `16 / (CPU 完成拍数 × 3 ns)`，单位为
`point/s`；计算能效定义为 `16 / VCD 窗口 SoC 总能量`，单位为
`point/J`。VCD 能量由 PT 时域平均 SoC 功率与同一次门级仿真记录的实际窗口时间
相乘得到。这里的“周期”表示完成时间，而不是直接以时钟拍数作为性能分母。
细分周期优先采用生成该 VCD 的同一次门级功耗仿真里程碑；硬件层次能耗按 SoC
顶层互斥实例的平均功耗乘窗口时间计算。PT 文本中的功耗类型分量存在显示舍入，
因此三类能耗保持报告比例并归一化到窗口总能量，避免图表总和偏离权威总值。

## 各阶段入口

| 阶段 | 工具 | 入口 | 说明 |
|---|---|---|---|
| 1. RTL 仿真 | VCS | `sw/` 编译出 vmem → tb 装载运行 | 验证 16 点 FFT 功能，与 `fft16.cpp` 对拍 |
| 2. DC 综合 | Design Compiler | `dc/compile.sh` → `compile.tcl` | wc 角综合（与 PT 签核角一致），SRAM 以 .db 黑盒链接 |
| 3. ICC 后端 | IC Compiler | `icc/` + RM Makefile | 2×SRAM 顶部摆放 / 双电源环 + gap 内 VDD/GND strap / 整带 blockage，`make ic` 到 GDS |
| 4. PT 签核 | PrimeTime | `make -C pt sta` | WC/max-RC、TC/min-RC、BC/min-RC，生成报告与 SDF |
| 5. 门级后仿 | VCS | `make -C postsim all` | 功能预跑 + max/min SDF，testbench 自动核对 16 点结果 |
| 6. 功耗分析 | PrimeTime PX | `make -C pt power_all` | BC/min SDF 生成执行窗 VCD；tc 角 + spef.max 统计 SoC/FFT 功耗与能量 |

## 主频与核心面积自动扫描

`scan_ppa.py` 将 DC、ICC、PT 三角 STA、门级执行窗 VCD 和 PT PX 串成可断点续跑的
PPA 扫描。脚本兼容本机的 Python 2.7，也可使用 Python 3；完整扫描耗时较长，建议先
检查默认矩阵和外部依赖：

```bash
python scan_ppa.py --dry-run
bash icc/check_dependencies.sh
make -C pt check
make -C postsim check
```

默认矩阵包含 8 个主频和 5 个核心面积档，共 40 个实现点：

- 主频：250、275、300、325、333.333、350、375、400 MHz；
- 核心尺寸：430.72×520、430.72×540、430.72×560、450.72×580、
  470.72×600 µm。

开始扫描或从已有断点继续使用同一个命令：

```bash
python scan_ppa.py
python scan_ppa.py --status
```

状态、隔离工作区、DC 频率缓存及结果默认放在 `scan_runs/default/`。可用
`--run-dir <目录>` 启动另一组互不干扰的扫描。每个阶段开始和完成时都会原子更新
`state.json`；ICC 还会复用自身的阶段 marker。扫描互斥使用内核 `flock`，因此
`.lock` 文件会作为所有者元数据长期保留，文件存在本身不表示扫描仍在运行；进程退出
后内核会自动释放锁。许可证服务器暂时失联或许可证已被
占满时，扫描器默认每 60 秒自动重试当前阶段（可用 `--license-retry-delay` 调整），
并把各次失败日志保存为 `*.attempt-NNN.log`；Ctrl-C 后仍可断点续跑。工具崩溃、
缺文件、永久许可证配置错误或报告损坏会停止在当前阶段，修复环境后重新执行即可重试。
若 VCS 已正常运行但某个设计点
门级自检失败或出现 SDF timing-check violation，扫描器会记录 `postsim_pass=false`、
跳过该点无效的功耗分析并自动继续后续组合。若确认其他工具失败的点永久无法实现，
可用 `python scan_ppa.py --skip-current` 标记并继续。

PT 收敛要求 WC setup、TC setup/hold 和 BC hold 全部通过，并且没有项目级
transition/capacitance/fanout 违例。只有收敛点继续执行窗口功耗，门级自检还要求
FFT16 的 testbench、功耗窗口和 PT 报告周期数相互一致；周期可随软件优化动态变化。
主要结果为：

- `summary.csv`：便于表格处理的完整 40 点矩阵；
- `summary.md`：时序、面积、功耗和归一化指标总表及能效排名；
- `results.json`：结构化结果；
- `points/<point>/reports/`：逐点文本报告，`logs/` 为阶段控制日志。

系统面积取 ICC 最终、经过 site/row 吸附后的 core area，并同时记录 Design Area 和
利用率。FFT16 计算时间取 `实测周期 × 时钟周期`。归一化使用固定汇编基线：3 ns、
240791.52 µm²、34.3 mW，即：

```text
计算密度比 = (T_baseline × A_baseline) / (T_point × A_point)
计算能效比 = (T_baseline × P_baseline) / (T_point × P_point)
```

扫描始终在隔离工作区运行，不覆盖仓库当前的综合网表和后端结果。为控制磁盘占用，
逐点长期保存文本报告，不复制大型 GDS、SPEF、SDF 和 VCD。

## PT 签核与门级后仿

以下两个检查只验证工具、库、网表、约束和寄生文件是否存在，不会取许可证：

```bash
make -C pt check
make -C postsim check
```

实际 STA、SDF 生成和 VCS 仿真需要 Synopsys 许可证，由用户在有许可证的终端运行：

```bash
# WC/TC/BC STA；报告和 SDF 位于 pt/runs/<corner>/
make -C pt sta
make -C pt verify_sta

# func 使用 10 ns 且关闭 specify/timing check；max/min 使用 3 ns 且开启检查
make -C postsim func
make -C postsim timing
# 或一次运行上述三项
make -C postsim all
```

`sta` 成功表示三个 PT 会话均正常完成，并不等于所有签核检查都已通过。
`verify_sta` 会检查 WC setup、BC hold、TC setup/hold，并在 PrimeTime/GCA 错误或
max transition/capacitance/fanout 违例存在时返回非零；因此真实的 reset removal 和
DRC 问题不会被“脚本运行成功”掩盖。max/min 后仿同样要求 testbench 报告
`CPU+FFT16 TEST PASS`、SDF 无错误且日志中没有 timing-check violation。
max/min/power 后仿会定义 `NTC` 和 `RECREM`，使 TSMC 标准单元模型使用
`$recrem` 接收 PT SDF 中可能为负的 recovery/removal 限值；`SDFCOM_NL`
会被结果验证器视为反标失败。

`rstn` 采用低有效异步断言、同 `clk1` 上升沿同步发射的释放协议。静态约束使用
0.20–0.50 ns 的外部 clock-to-Q 窗口，所有 testbench 使用 0.30 ns 标称值；复位
上升沿仍执行 recovery/removal 检查。项目级 DRC 上限为 fanout 128、transition
0.60 ns、capacitance 0.20 pF，库中更严格的电气限制仍然有效。ICC 中可通过
`ICC_RESET_RELEASE_MIN/MAX`、`ICC_MAX_FANOUT`、`ICC_MAX_TRANSITION` 和
`ICC_MAX_CAPACITANCE` 覆盖这些默认值。为吸收 ICC/PT 寄生与角落相关性误差，
ICC 默认用 reset min 0.14 ns、transition 0.50 ns、capacitance 0.18 pF 做物理
优化，并对数据 SRAM `D[*]` 使用 0.40 ns 局部 slew 目标；输出 SDC 前恢复上述
签核值。实现 guardband 可分别通过
`ICC_OPT_RESET_RELEASE_MIN`、`ICC_OPT_MAX_TRANSITION` 和
`ICC_OPT_MAX_CAPACITANCE` 覆盖，SRAM 局部目标可通过
`ICC_OPT_SRAM_DATA_MAX_TRANSITION` 覆盖。

修改 DC/ICC 约束后必须完整重跑。以下清理命令会删除原有生成结果，必要时先备份：

```bash
dc/compile.sh
make -C icc clean
make -C icc ic
make -C pt clean
make -C pt sta
make -C pt verify_sta
make -C postsim all
```

功耗流程先用 BC/min SDF 生成仅含程序执行段的门级 VCD，再由 TC/TT PT PX 读取。
推荐使用一键目标（会依次占用 VCS 和 PrimeTime/PrimePower 许可证）：

```bash
make -C pt power_all
```

也可以拆开运行，便于保留 VCD 后反复调整 PT 报告：

```bash
make -C postsim power_vcd  # 生成 postsim/build/power/tb_soc.vcd 和 power_window.rpt
make -C pt power           # 复用上述文件，不再运行 VCS
```

testbench 在二次复位释放前开启 VCD，并在最后一个正确结果写回后关闭；同一次仿真
会把绝对起止时间、持续时间和周期数写入 `power_window.rpt`。PT 脚本以这些数值调用
`read_vcd -time`，因此不会把程序装载、复位或 VCD 时间零点误计入平均功耗。
`pt/runs/power/` 中的主要结果为：

- `power_vcd.rpt`：整个 SoC 在测量窗内的 time-based 功耗；
- `power_fft8.rpt`：同一测量窗内 `u_fft8_top` 的功耗；
- `power_vcd_hier.rpt`：层次化功耗明细；
- `power_summary.rpt`：统一换算为 mW，并给出窗口能量 nJ、每周期能量 pJ 和 FFT 占比；
- `power_window_used.rpt`：PT 实际采用的窗口、角落、SPEF 和 FFT 实例记录。

若 FFT 实例名因网表层次改变，可设置 `POWER_FFT_INSTANCE`。功耗输入也可分别通过
`POWER_VCD` 与 `POWER_WINDOW_FILE` 覆盖；两者必须来自同一次后仿真。

主要外部路径集中在 `pt/dependencies.sh` 和 `postsim/dependencies.sh`。可通过同名
环境变量覆盖，例如 `PT_SHELL_BIN`、`VCS_BIN`、`STD_CELL_*_DB`、`SRAM_*_DB`、
`NETLIST`、`STD_CELL_MODEL`、`SRAM_MODEL`、`VMEM`、`WC_SDF`、`BC_SDF` 和
`POWER_VCD`、`POWER_WINDOW_FILE` 和 `POWER_FFT_INSTANCE`，无需修改 Tcl、testbench
或 Makefile。

## 第三方依赖（不随仓库分发，需自备）

| 依赖 | 来源 | 放置建议 |
|---|---|---|
| Ibex core（RTL） | [lowRISC/ibex](https://github.com/lowRISC/ibex)，Apache-2.0 | `RISC_V/ibex/` |
| TSMC 65nm PDK / `tcbn65gplus*` 标准单元库 | 台积电（NDA 授权） | `day2/library/` 等，勿入任何仓库 |
| ARM `RA1HD_4KB` SRAM（.db/.v/Milkyway） | ARM Physical IP（NDA 授权） | `sram_hde/` |
| Synopsys DC / ICC / PT / VCS / Verdi | EDA 许可 | — |

ICC 的外部文件路径集中在 `icc/dependencies.sh`，PDK、库与工具均不随仓库分发。

## ICC 主流程

仓库内收录课程使用的 Synopsys ICC netlist-to-GDS 主流程：

```
init_design_icc → load_clf → place_opt_icc
→ clock_opt_cts_icc → clock_opt_psyn_icc → clock_opt_route_icc
→ route_icc → route_opt_icc → chip_finish_icc
→ metal_fill_icc → signoff_drc_icc → outputs_icc
```

输入固定为当前综合交接文件：

- `syn_rtl/soc_ahblite.mapped.ddc`
- `syn_rtl/soc_ahblite.mapped.v`
- `sdc/soc_ahblite.mapped.sdc`（当前时钟周期目标为 3 ns）

先检查本机工具、逻辑库、Milkyway 库、TLU+、CLF 与 layer map：

```bash
make -C icc check_dependencies
```

运行初始化或完整流程：

```bash
make -C icc init_design_icc
make -C icc outputs_icc   # make -C icc ic 等价
```

每个成功阶段会在 `icc/.markers/` 写入 marker；日志、报告和最终交付物分别位于
`icc/logs_zrt/`、`icc/reports/` 和 `icc/results/`。`eco` 与 `focal_opt` 入口也保留。

所有外部依赖都可以通过同名环境变量覆盖，无需修改 Tcl 或 Makefile。例如：

```bash
STD_CELL_DB=/path/to/wc.db \
STD_CELL_MIN_DB=/path/to/bc.db \
make -C icc check_dependencies
```

可覆盖变量包括 `ICC_SHELL_BIN`、`MILKYWAY_BIN`、`STD_CELL_DB`、
`STD_CELL_MIN_DB`、`SRAM_DB`、`SRAM_MIN_DB`、`STD_CELL_MW_LIB`、
`SRAM_MW_LIB`、`TECH_FILE`、`TLUPLUS_MAP_FILE`、`TLUPLUS_MAX_FILE`、
`TLUPLUS_MIN_FILE`、`ANTENNA_RULES_TCL`、`SRAM_CLF`、`STD_CELL_CLF` 和
`GDS_LAYER_MAP`。功耗相关的可选变量为 `ICC_SAIF_FILE`（建议使用绝对路径）、
`ICC_SAIF_INSTANCE_NAME` 和 `ICC_TOTAL_POWER_STRATEGY_EFFORT`（`none`、
`medium` 或 `high`）。例如，从 `chip_finish_icc` 独立执行“setup 修复 + 功耗恢复”：

```bash
ICC_SAIF_FILE=/path/to/gate.saif \
ICC_SAIF_INSTANCE_NAME=soc_ahblite \
ICC_TOTAL_POWER_STRATEGY_EFFORT=medium \
make -C icc focal_opt_icc
```

ICC在导入DDC后、创建floorplan前，会通过
`icc/myscript/icc_timing_constraints.tcl` 覆盖时钟不确定度。默认值为setup 0.20 ns、
hold 0.05 ns，时钟周期仍继承自DDC。可以在运行前覆盖，无需修改Tcl：

```bash
ICC_SETUP_UNCERTAINTY=0.20 \
ICC_HOLD_UNCERTAINTY=0.05 \
make -C icc init_design_icc
```

相关变量为 `ICC_CLOCK_NAME`、`ICC_SETUP_UNCERTAINTY` 和
`ICC_HOLD_UNCERTAINTY`。使用DDC输入时，直接修改生成的mapped SDC不会替代DDC内
已有的约束；应使用该初始化脚本进行ICC端覆盖。

为优先收敛3 ns时序，主流程默认设置
`ICC_ROUTE_OPT_AREA_RECOVERY=FALSE`，使第一次post-route优化不使用
`route_opt -area_recovery`。时序具有足够正裕量后，可用
`ICC_ROUTE_OPT_AREA_RECOVERY=TRUE` 做一次独立的面积/功耗对比。切换时序不确定度或
area-recovery选项后，必须清理旧marker和Milkyway设计库，再运行完整ICC流程：

```bash
make -C icc clean
make -C icc outputs_icc
make -C icc audit_timing_icc
```

`focal_opt_icc` 是独立的 PPA 对比实验，不属于 `outputs_icc` 主依赖链；确认
`icc/reports/focal_opt_icc.{qor,power,max.tim}` 优于主流程结果后再决定是否采用。
若只剩少量 setup 违例，应在 `icc/myscript/focal_targeted_setup_endpoints.txt`
列出准确的 endpoint，再从该 CEL 做定点修复：

```bash
make -C icc focal_targeted_icc
```

该阶段不修 hold、不做全量 DRC、size-only 或第二次 power recovery；其输出保存在
`focal_targeted_icc` CEL 和 `icc/reports/focal_targeted_icc.*`，用于确认定点修复
是否导致 hold、面积或功耗反弹。它同样不自动覆盖主流程最终结果。

最终候选必须在新的 ICC 会话中重新打开后复核，避免采用只能在优化会话内复现的
瞬态 QoR。以下命令只读打开 `metal_fill_icc`，不保存或修改 CEL，也不会触发 focal：

```bash
make -C icc audit_timing_icc
```

复核报告为 `icc/reports/audit_metal_fill_icc.{qor,max.tim,min.tim,power}`。

最终 ICC 系统面积构成可通过独立的只读目标统计，不修改或保存 Milkyway CEL，也不接入
40 点 PPA 扫描：

```bash
make -C icc area_report
```

该目标要求已有最终实现，以只读方式重新打开 `metal_fill_icc`；缺少最终实现时直接报错，
不会自动重跑布局布线。一次生成系统的两种分类及 CPU 内部分解的饼图与 CSV：

| 分类 | 内容 | 输出文件（位于 `report/`） |
|---|---|---|
| 功能模块 | CPU 子系统、FFT8、指令 SRAM、数据 SRAM、ROM、数据总线、其他顶层逻辑 | `icc_area_breakdown.csv`、`icc_area_breakdown.png` |
| 电路性质 | 组合逻辑、时序单元（寄存器/锁存器等）、宏/黑盒单元（含 SRAM） | `icc_area_by_circuit.csv`、`icc_area_by_circuit.png` |
| CPU 内部 | 寄存器堆、执行单元、CSR 与计数器、取指、译码与控制、访存、其他 CPU 逻辑 | `icc_cpu_area_breakdown.csv`、`icc_cpu_area_breakdown.png` |

`report/icc_area_breakdown.md` 汇总三张图、面积、占比和统计口径。两张系统饼图均以
normal/logical cell area（含 SRAM 宏）为分母，图例显示 µm² 和百分比。组合逻辑已包含
缓冲器/反相器，不重复加入 `Buf/Inv area`；时序单元沿用 ICC 的 `Noncombinational area`
分类。模块图中 SRAM 宏归入对应 SRAM 模块，电路性质图中归入宏/黑盒。
Filler、tap 等 physical-only 单元面积以及 core area 在 Markdown 中单列，不混入饼图。
脚本核对两种分类与总面积、QoR 及 physical summary；数据缺失或不一致时返回非零退出码。

CPU 内部图以 `x_sub_system` 面积为分母，CSV 的 `share_percent` 表示占 CPU 子系统的比例。
六个命名模块取 `x_core` 下互不重叠的全局面积，执行单元包含 ALU 和乘除法，不重复累加后代。
“其他 CPU 逻辑”为子系统总面积的残差，包含写回、时钟门控及核心/子系统局部逻辑。
该图沿用紧凑的 900×720 布局，已有层次报告即可离线生成。

绘图使用 PyCairo（`python -c 'import cairo'` 可检查），支持无显示器运行和 Python 2/3。
首次导出需要 ICC 许可证。已有 `icc/reports/area_metal_fill_icc.hier.rpt`、
`area_metal_fill_icc.qor` 和 `area_metal_fill_icc.sum` 时，可不取 ICC 许可证重新汇总：

```bash
python icc/summarize_area.py --project-root .
```

## 声明

- ICC 阶段的 RM 流程脚本（`rm_icc_scripts/`、`rm_icc_zrt_scripts/`，RM-Info
  头）改编自 Synopsys Reference Methodology 模板，版权归 Synopsys。本仓库仅收录
  课程使用的 netlist-to-GDS 主流程，不收录 DP/HRM、历史结果、PDK、库或工具，
  仅限已授权的私有课程环境使用；
- Ibex 核版权归 lowRISC，未收录在本仓库中；
- 本仓库为课程作业，仅用于学习交流。
