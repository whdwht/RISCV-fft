# RISC-V SoC + 8 点 FFT 加速核 —— 前端到签核全流程

基于 lowRISC **Ibex** (RV32IMFC) CPU 与**自研 8 点 FFT 流水线加速核**的 SoC，
打通 **RTL 仿真 → DC 综合 → ICC 布局布线 → PrimeTime 签核 → 门级后仿 / 功耗分析** 的完整数字前端流程。

16 点 FFT 采用软硬件协同划分：**2 次 8 点硬件加速核 + CPU 软件合并级（DIT 蝶形）**。

## 成果总览

| 指标 | 数值 | 条件 |
|---|---|---|
| 工艺 | TSMC 65nm `tcbn65gplusbwp12t`，9 层金属 | TLU+ 寄生 |
| 频率 | **100 MHz** (10 ns) | wc(SS/0.9V/125℃) setup 收敛；bc(FF/1.1V/0℃) hold 收敛 |
| 面积 | cell 159.6k µm²（含 2×4KB SRAM 宏） | core 430.72×560，die 510.72×640 µm |
| 平均功耗 | **9.736 mW** | tc 角 + spef.max + 门级 VCD（10.3–15.8µs 计算窗），time_based |
| 16 点 FFT | **506 周期 / 5.06 µs** | 二次复位释放 → 末结果字写回，不含程序装载 |

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
- 软件侧：`fft16.s` 全展开手写汇编（无栈/无 .bss），结果存 data_sram `0x1000_0040~`。

## 目录结构

```
├── hw/fft8/        自研 FFT 加速核: fft8_top.sv(AHB封装) fft8_pl.v(流水核) fft8_stages.v(蝶形)
├── sw/             fft16.s(汇编主程序) fft16.vmem(机器码) fft16[_ref].cpp(黄金参考) 编译脚本
├── tb/             tb_soc_day1.sv(RTL仿真) tb_soc_postsim.sv(门级后仿+定向VCD)
├── dc/             DC 综合 4 脚本 + soc_ahblite.rpt(面积/时序报告)
├── icc/            common_setup.tcl icc_setup.tcl myscript/(floorplan/电源环 strap/SRAM摆放/blockage)
├── pt/             compile_bc/tc/wc.tcl(三角STA) compile_power.tcl(功耗)
├── postsim/        sim_min/max.sh(VCS SDF反标后仿) test/filelist
└── doc/results/    PT 三角时序报告 / 功耗报告 / ICC QoR
```

## 各阶段入口

| 阶段 | 工具 | 入口 | 说明 |
|---|---|---|---|
| 1. RTL 仿真 | VCS | `sw/` 编译出 vmem → tb 装载运行 | 验证 16 点 FFT 功能，与 `fft16.cpp` 对拍 |
| 2. DC 综合 | Design Compiler | `dc/compile.sh` → `compile.tcl` | wc 角综合（与 PT 签核角一致），SRAM 以 .db 黑盒链接 |
| 3. ICC 后端 | IC Compiler | `icc/` + RM Makefile | 2×SRAM 顶部摆放 / 双电源环 + gap 内 VDD/GND strap / 整带 blockage，`make ic` 到 GDS |
| 4. PT 签核 | PrimeTime | `pt/compile_{wc,tc,bc}.tcl` | SPEF 反标率 100%（pin-to-pin），setup 看 wc、hold 看 bc |
| 5. 门级后仿 | VCS | `postsim/sim_min/max.sh` | SDF 反标 `tb_soc.x_soc`，Verdi 核对 16 组结果字 |
| 6. 功耗分析 | PrimeTime PX | `pt/compile_power.tcl` | tc 角 + SPEF + 门级 VCD（计算窗 10.3–15.8µs） |

## 第三方依赖（不随仓库分发，需自备）

| 依赖 | 来源 | 放置建议 |
|---|---|---|
| Ibex core（RTL） | [lowRISC/ibex](https://github.com/lowRISC/ibex)，Apache-2.0 | `RISC_V/ibex/` |
| TSMC 65nm PDK / `tcbn65gplus*` 标准单元库 | 台积电（NDA 授权） | `day2/library/` 等，勿入任何仓库 |
| ARM `RA1HD_4KB` SRAM（.db/.v/Milkyway） | ARM Physical IP（NDA 授权） | `sram_hde/` |
| Synopsys DC / ICC / PT / VCS / Verdi | EDA 许可 | — |

> 脚本中的绝对路径（`/home/master/...`）为本人环境，复现时按实际修改。

## 声明

- ICC 阶段的 RM 流程脚本（`rm_icc_*/`，RM-Info 头）改编自 Synopsys Reference
  Methodology 模板，版权归 Synopsys，本仓库仅收录**自研配置与定制脚本**
  （`icc/myscript/`、`common_setup.tcl`、`icc_setup.tcl`），私有学习用途；
- Ibex 核版权归 lowRISC，未收录在本仓库中；
- 本仓库为课程作业，仅用于学习交流。
