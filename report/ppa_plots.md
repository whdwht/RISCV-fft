# PPA 三维柱状图

数据源为 `scan_runs/default/summary.csv`，对应结果更新时间为
`2026-08-31T15:51:50Z`。三张图使用完全相同的 10 个有效点，频率轴和
尺寸轴仅保留有效点覆盖的 **5 档频率 × 3 档请求核心尺寸**：

- 频率：250、275、300、325、333.333 MHz。
- 请求核心尺寸：430.72 × 520、430.72 × 540、430.72 × 560 µm。

350/375/400 MHz 和 450.72 × 580、470.72 × 600 µm 档没有有效数据，
因此移除对应坐标档。保留范围内的 5 个无效组合不绘柱、不补零。
三张图共用同一组坐标类别及范围，数据筛选口径保持一致。

| 图表 | PNG | SVG |
|---|---|---|
| 计算能效提升比 | [PNG](ppa_compute_efficiency_ratio_3d.png) | [SVG](ppa_compute_efficiency_ratio_3d.svg) |
| 计算密度提升比 | [PNG](ppa_compute_density_ratio_3d.png) | [SVG](ppa_compute_density_ratio_3d.svg) |
| 两者的算术平均值 | [PNG](ppa_mean_ratio_3d.png) | [SVG](ppa_mean_ratio_3d.svg) |

PNG 为 4200 × 3000 像素、300 dpi；SVG 的文字转换为矢量路径，避免在其他
机器查看时因缺少中文字体出现乱码。三张图采用相同视角、画布和坐标布局，
纵轴统一截断为 **0.75–1.10 倍**，刻度间隔统一为 **0.05**。相较原来的
0–1.15 范围，数值差异在纵向放大约 3.29 倍；三张图仍可按同一比例比较。
每张图明确标注纵轴截断及非零起点，并保留 1.00 基线参考面。柱底位于 0.75，
柱顶及数值标签仍为原始比值；可见柱长表示比值减去 0.75，不能把柱长倍数
解释为指标倍数。
横向两轴为按数值递增排列的等间距类别，尺寸标签为请求尺寸；密度计算采用
ICC 实际核心面积。

## 数据口径

筛选条件为 `density_timing_valid=true`，且 `compute_density_ratio` 和
`compute_efficiency_ratio` 均为有限正数。直接使用 CSV 中已有的比值，
平均值为 `(compute_efficiency_ratio + compute_density_ratio) / 2`。
缺失值不补零、不插值；1 倍表示与基线相同，1.05 倍表示提升 5%。

固定基线为 3 ns、506 周期（1518 ns）、240791.52 µm²、34.3 mW：

```text
能效比 = (T_baseline × P_baseline) / (T_point × P_point)
密度比 = (T_baseline × A_baseline) / (T_point × A_point)
```

保留历史数据的有效性判断：275 MHz、430.72 × 520 µm 点的
`postsim_pass` 字段为空，但 `density_timing_valid=true` 且已具备能效数据，
所以包含在这 10 个点中。此处没有将该空值解释为已明确通过门级自检。

| 指标 | 最高比值 | 主频 (MHz) | 请求核心尺寸 (µm) |
|---|---:|---:|---|
| 能效比 | 1.07635983 | 250 | 430.72 × 540 |
| 密度比 | 1.07870370 | 333.333333 | 430.72 × 520 |
| 平均值 | 1.049768515 | 333.333333 | 430.72 × 520 |

## 复现

在仓库根目录执行：

```bash
python report/plot_ppa_3d.py
python report/plot_ppa_3d.py --input scan_runs/default/summary.csv --output-dir report
```

本机使用 Python 2.7；Matplotlib 2.2.5、NumPy 1.16.6、Pillow 6.2.2 及
依赖隔离安装在 `scan_runs/.plot-python/`，脚本自动加载该目录。无需管理员权限，
不修改系统 Python。Matplotlib 字体缓存位于 `scan_runs/.plot-cache/`。
中文字体使用系统已有的 `/usr/share/fonts/wqy-microhei/wqy-microhei.ttc`。

若需要重建本机隔离依赖，在已有 pip 的情况下执行：

```bash
PYTHONPATH=scan_runs/.plot-python python -m pip install \
  --target scan_runs/.plot-python --only-binary=:all: \
  'numpy==1.16.6' 'matplotlib==2.2.5' 'Pillow==6.2.2'
```

脚本也支持已有 Matplotlib/NumPy 的 Python 3 环境；Python 3 不会加载本机
Python 2 的隔离包。纵轴范围在绘图前由三项指标的全部有效值共同确定；未来
数据超出当前范围时，三张图会一起扩展为同一范围，不会分别自动缩放。
