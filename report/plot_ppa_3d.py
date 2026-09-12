#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Plot the existing PPA sweep with Python 2.7 or Python 3.

Usage: python report/plot_ppa_3d.py [--input summary.csv] [--output-dir report]
Dependencies: matplotlib, numpy. On the original Python 2 host these are
installed locally under scan_runs/.plot-python (see ppa_plots.md).
"""
from __future__ import print_function

import argparse
import csv
import io
import math
import os
import sys


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
METRICS = (
    ("compute_efficiency_ratio", u"计算能效提升比", "#268998"),
    ("compute_density_ratio", u"计算密度提升比", "#4976b4"),
    ("mean_ratio", u"能效与密度提升比的平均值", "#cf8945"),
)


def finite_positive(value):
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number > 0 and not math.isnan(number) and not math.isinf(number) else None


def load_points(path):
    if sys.version_info[0] < 3:
        handle = open(path, "rb")
    else:
        handle = io.open(path, "r", encoding="utf-8-sig", newline="")
    with handle:
        reader = csv.DictReader(handle)
        required = {
            "point_id", "frequency_mhz", "requested_core_width_um",
            "requested_core_height_um", "density_timing_valid",
            "compute_density_ratio", "compute_efficiency_ratio",
        }
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError("Missing CSV columns: " + ", ".join(sorted(missing)))
        rows = list(reader)
    if not rows:
        raise ValueError("The input CSV contains no sweep points")
    points, frequencies, sizes, seen = [], set(), set(), set()
    for row in rows:
        frequency = finite_positive(row["frequency_mhz"])
        size = tuple(finite_positive(row[key]) for key in (
            "requested_core_width_um", "requested_core_height_um"))
        if frequency is None or None in size:
            raise ValueError("Invalid sweep coordinates: " + row["point_id"])
        coordinate = (frequency, size)
        if coordinate in seen:
            raise ValueError("Duplicate sweep coordinates: " + row["point_id"])
        seen.add(coordinate)
        efficiency = finite_positive(row["compute_efficiency_ratio"])
        density = finite_positive(row["compute_density_ratio"])
        if row["density_timing_valid"].strip().lower() != "true":
            continue
        if efficiency is None or density is None:
            continue
        # Crop both categorical axes to the points actually shown in all plots.
        frequencies.add(frequency)
        sizes.add(size)
        points.append({
            "point_id": row["point_id"], "frequency": frequency, "size": size,
            "compute_efficiency_ratio": efficiency,
            "compute_density_ratio": density,
            "mean_ratio": (efficiency + density) / 2.0,
        })
    if not points:
        raise ValueError("No points have valid density and both finite positive ratios")
    return points, sorted(frequencies), sorted(sizes, key=lambda s: (s[0] * s[1], s)), len(rows)


def initialize_plotting():
    local_packages = os.path.join(ROOT, "scan_runs", ".plot-python")
    if sys.version_info[0] == 2 and os.path.isdir(local_packages):
        sys.path.insert(0, local_packages)
        # Process the wheel's namespace-package .pth for mpl_toolkits.
        import site
        site.addsitedir(local_packages)
    os.environ.setdefault("MPLCONFIGDIR", os.path.join(ROOT, "scan_runs", ".plot-cache"))
    import matplotlib
    matplotlib.use("Agg")
    from matplotlib import font_manager
    font_path = "/usr/share/fonts/wqy-microhei/wqy-microhei.ttc"
    if os.path.isfile(font_path):
        if hasattr(font_manager.fontManager, "addfont"):
            font_manager.fontManager.addfont(font_path)
        else:
            font_manager.fontManager.ttflist.extend(font_manager.createFontList([font_path]))
        family = font_manager.FontProperties(fname=font_path).get_name()
    else:
        family = "sans-serif"
    matplotlib.rcParams.update({
        "font.family": family, "font.size": 11,
        "axes.unicode_minus": False, "svg.fonttype": "path",
        "figure.facecolor": "white", "savefig.facecolor": "white",
    })


def shared_z_limits(points):
    """Choose one truncated scale using all three metrics, never per figure."""
    values = [point[metric[0]] for point in points for metric in METRICS]
    lower = min(0.75, math.floor((min(values) - 0.01) / 0.05) * 0.05)
    upper = max(1.10, math.ceil((max(values) + 0.01) / 0.05) * 0.05)
    return max(0.0, lower), upper


def plot_metric(points, frequencies, sizes, total, key, title, color, output_dir, source, z_limits):
    import numpy as np
    import matplotlib.pyplot as plt
    from matplotlib.ticker import FormatStrFormatter
    from mpl_toolkits.mplot3d import Axes3D  # noqa: F401; registers 3D projection

    fig = plt.figure(figsize=(14, 10))
    ax = fig.add_axes([0.025, 0.17, 0.93, 0.71], projection="3d")
    fig.text(0.075, 0.955, title, fontsize=24, weight="bold", color="#24384b")
    fig.text(0.075, 0.917,
             u"PPA 扫参  |  %d/%d 个有效点  |  仅保留有效频率与尺寸档  |  基线 = 1.000" % (len(points), total),
             fontsize=12, color="#607181")
    zmin, zmax = z_limits
    fig.text(0.075, 0.881,
             u"纵轴截断：%.2f–%.2f 倍  |  三图统一比例，每格 0.05  |  柱底为 %.2f，非零起点" %
             (zmin, zmax, zmin), fontsize=11, color="#a15d23")

    xs = np.array([frequencies.index(p["frequency"]) for p in points], dtype=float)
    ys = np.array([sizes.index(p["size"]) for p in points], dtype=float)
    values = np.array([p[key] for p in points])
    width, depth = 0.58, 0.52
    ax.bar3d(xs - width / 2, ys - depth / 2, np.full(len(points), zmin),
             width, depth, values - zmin, color=color, shade=True,
             edgecolor="white", linewidth=0.45, zsort="average")
    for x, y, value in zip(xs, ys, values):
        ax.text(x, y, value + (zmax - zmin) * 0.025, "%.3f" % value,
                ha="center", va="bottom", fontsize=10, color="#24384b",
                bbox=dict(facecolor="white", edgecolor="none", alpha=0.9, pad=1.0))

    xmin, xmax, ymin, ymax = -0.6, len(frequencies) - 0.4, -0.6, len(sizes) - 0.4
    plane_x, plane_y = np.meshgrid([xmin, xmax], [ymin, ymax])
    ax.plot_surface(plane_x, plane_y, np.ones_like(plane_x),
                    color="#74899a", alpha=0.055, shade=False, linewidth=0)
    ax.plot([xmin, xmax, xmax, xmin, xmin], [ymin, ymin, ymax, ymax, ymin],
            [1.0] * 5, color="#7a8c9d", linestyle="--", linewidth=0.9, alpha=0.7)

    ax.set_xlim(xmin, xmax)
    ax.set_ylim(ymin, ymax)
    ax.set_zlim(zmin, zmax)
    ax.set_xticks(range(len(frequencies)))
    ax.set_xticklabels([("%.3f" % value).rstrip("0").rstrip(".") for value in frequencies], fontsize=10)
    ax.set_yticks(range(len(sizes)))
    ax.set_yticklabels([u"%g × %g" % size for size in sizes], fontsize=10)
    ax.set_zticks(np.linspace(zmin, zmax, int(round((zmax - zmin) / 0.05)) + 1))
    ax.zaxis.set_major_formatter(FormatStrFormatter("%.2f"))
    ax.set_xlabel(u"主频 (MHz)", labelpad=13)
    ax.set_ylabel(u"请求核心尺寸 (µm × µm)", labelpad=19)
    ax.set_zlabel(u"相对基线的比值 (倍)", labelpad=10)
    ax.view_init(elev=43, azim=125)
    ax.dist = 11
    for axis in (ax.xaxis, ax.yaxis, ax.zaxis):
        axis.pane.set_facecolor((0.96, 0.97, 0.98, 1.0))
        axis.pane.set_edgecolor((0.88, 0.91, 0.93, 1.0))
        axis._axinfo["grid"]["color"] = (0.84, 0.88, 0.91, 0.6)

    best = max(points, key=lambda point: point[key])
    fig.text(0.075, 0.135,
             u"最高值  %.4f 倍  |  %g MHz  |  %g × %g µm" %
             (best[key], best["frequency"], best["size"][0], best["size"][1]),
             fontsize=13, color=color, weight="bold")
    fig.text(0.075, 0.098,
             u"比值沿用扫参结果；1 表示与基线相同。密度按实际核心面积计算，尺寸轴为等间距类别。",
             fontsize=10, color="#607181")
    fig.text(0.075, 0.07,
             u"平均值 = (能效提升比 + 密度提升比) / 2；缺失数据不补零、不插值。",
             fontsize=10, color="#607181")
    fig.text(0.075, 0.042, u"数据源：" + source, fontsize=9, color="#7a8996")
    for extension in ("png", "svg"):
        path = os.path.join(output_dir, "ppa_%s_3d.%s" % (key, extension))
        fig.savefig(path, dpi=300)
        print(path)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default=os.path.join(ROOT, "scan_runs", "default", "summary.csv"))
    parser.add_argument("--output-dir", default=os.path.join(ROOT, "report"))
    args = parser.parse_args()
    points, frequencies, sizes, total = load_points(args.input)
    initialize_plotting()
    if not os.path.isdir(args.output_dir):
        os.makedirs(args.output_dir)
    source = os.path.relpath(os.path.abspath(args.input), ROOT)
    print("Plotting %d/%d points on a %d x %d grid" % (len(points), total, len(frequencies), len(sizes)))
    z_limits = shared_z_limits(points)
    print("Shared truncated Z range: %.2f to %.2f; tick interval: 0.05" % z_limits)
    for key, title, color in METRICS:
        plot_metric(points, frequencies, sizes, total, key, title, color, args.output_dir, source, z_limits)


if __name__ == "__main__":
    main()
