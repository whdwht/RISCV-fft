#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import print_function

"""Analyze final ICC system and CPU area; render headless PNG pie charts."""

import argparse
import csv
import io
import math
import os
import re
import sys


try:
    text_type = unicode
except NameError:
    text_type = str


SOURCE_CEL = "metal_fill_icc"
FLOAT_PATTERN = r"[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][-+]?[0-9]+)?"
AREA_CATEGORIES = (
    ("cpu_subsystem", u"CPU 子系统", "CPU subsystem", "x_sub_system"),
    ("fft8_accelerator", u"FFT8 加速器", "FFT8 accelerator", "u_fft8_top"),
    ("instruction_sram", u"指令 SRAM", "Instruction SRAM", "x_isram_ahbl"),
    ("data_sram", u"数据 SRAM", "Data SRAM", "x_data_sram"),
    ("rom", u"ROM", "ROM", "x_rom_ahbl"),
    ("data_fabric", u"数据总线", "Data fabric", "x_data_fabric"),
)
OTHER_CATEGORY = (
    "other_top_level",
    u"其他顶层逻辑",
    "Other top-level",
    "<top-level residual>",
)
CSV_FIELDS = (
    "category_key",
    "category",
    "instance",
    "area_um2",
    "share_percent",
)
CIRCUIT_CATEGORIES = (
    ("combinational", u"组合逻辑", "Combinational logic", "Combinational area"),
    ("sequential", u"时序单元（寄存器、锁存器等）", "Sequential cells", "Noncombinational area"),
    ("macro_black_box", u"宏/黑盒单元（含 SRAM）", "Macros / black boxes", "Macro/Black Box area"),
)
CIRCUIT_CSV_FIELDS = ("category_key", "category", "area_um2", "share_percent")
CPU_CORE = "x_sub_system/x_core"
CPU_CATEGORIES = (
    ("register_file", u"通用寄存器堆", "Register file", "gen_regfile_ff_register_file_i"),
    ("execution", u"执行单元（ALU、乘除法等）", "Execution (ALU + mul/div)", "ex_block_i"),
    ("csr", u"CSR 与计数器", "CSRs and counters", "cs_registers_i"),
    ("instruction_fetch", u"取指单元", "Instruction fetch", "if_stage_i"),
    ("instruction_decode", u"译码与控制", "Decode and control", "id_stage_i"),
    ("load_store", u"访存单元", "Load / store unit", "load_store_unit_i"),
)


def parse_cpu_breakdown(text, total):
    if total <= 0.0:
        raise AreaReportError("CPU subsystem area must be positive")

    def hierarchy_area(instance):
        area = _single_float(
            r"^\s*%s\s+(%s)\s+%s(?:\s+|$)"
            % (re.escape(instance), FLOAT_PATTERN, FLOAT_PATTERN),
            text, "CPU hierarchy " + instance,
        )
        if area < 0.0:
            raise AreaReportError("negative area for CPU hierarchy %s" % instance)
        return area

    core_area = hierarchy_area(CPU_CORE)
    tolerance = max(0.1, total * 1.0e-6)
    if core_area > total + tolerance:
        raise AreaReportError("CPU core area exceeds CPU subsystem area")
    records = []
    for key, chinese_label, english_label, child in CPU_CATEGORIES:
        instance = CPU_CORE + "/" + child
        records.append({
            "category_key": key, "category": chinese_label,
            "chart_label": english_label, "instance": instance,
            "area_um2": hierarchy_area(instance),
        })
    # Use only these disjoint global areas, never also add their descendants.
    known_area = sum(row["area_um2"] for row in records)
    if math.isinf(known_area) or known_area > core_area + tolerance:
        raise AreaReportError("CPU submodule areas exceed CPU core area")
    records.append({
        "category_key": "cpu_other", "category": u"其他 CPU 逻辑",
        "chart_label": "Other CPU logic", "instance": "<CPU subsystem residual>",
        "area_um2": max(0.0, total - known_area),
    })
    if not _close_enough(sum(row["area_um2"] for row in records), total):
        raise AreaReportError("CPU area categories do not close to CPU subsystem total")
    for row in records:
        row["share_percent"] = 100.0 * (row["area_um2"] / total)
    return records


class AreaReportError(Exception):
    pass


def read_text(path):
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        raise AreaReportError("missing or empty ICC area input: %s" % path)
    with io.open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def ensure_dir(path):
    if path and not os.path.isdir(path):
        os.makedirs(path)


def atomic_write_text(path, value):
    ensure_dir(os.path.dirname(path))
    temporary = path + ".tmp.%d" % os.getpid()
    if not isinstance(value, text_type):
        value = value.decode("utf-8", "replace")
    with io.open(temporary, "w", encoding="utf-8") as handle:
        handle.write(value)
        handle.flush()
        os.fsync(handle.fileno())
    os.rename(temporary, path)


def _single_float(pattern, text, label):
    matches = re.findall(pattern, text, re.MULTILINE)
    if not matches:
        raise AreaReportError("cannot find %s in ICC area reports" % label)
    if len(matches) != 1:
        raise AreaReportError("duplicate %s in ICC area reports" % label)
    value = float(matches[0])
    if math.isnan(value) or math.isinf(value):
        raise AreaReportError("%s must be finite" % label)
    return value


def _close_enough(left, right):
    if any(math.isnan(value) or math.isinf(value) for value in (left, right)):
        return False
    return abs(left - right) <= max(0.1, max(abs(left), abs(right)) * 1.0e-6)


def parse_hierarchy_report(path):
    text = read_text(path)
    source_matches = re.findall(
        r"^ICC_AREA_SOURCE_CEL\s+(\S+)\s*$", text, re.MULTILINE
    )
    if source_matches != [SOURCE_CEL]:
        raise AreaReportError(
            "hierarchy report must identify exactly one %s source CEL" % SOURCE_CEL
        )
    total_area = _single_float(
        r"^\s*Total cell area:\s*(%s)\s*$" % FLOAT_PATTERN,
        text,
        "hierarchical total cell area",
    )
    if total_area <= 0.0:
        raise AreaReportError("hierarchical total cell area must be positive")

    circuit_records = []
    for key, chinese_label, english_label, field in CIRCUIT_CATEGORIES:
        area = _single_float(
            r"^\s*%s:\s*(%s)\s*$" % (re.escape(field), FLOAT_PATTERN),
            text, field,
        )
        if area < 0.0:
            raise AreaReportError("%s must not be negative" % field)
        circuit_records.append({
            "category_key": key,
            "category": chinese_label,
            "chart_label": english_label,
            "area_um2": area,
            "share_percent": 100.0 * (area / total_area),
        })
    # Buf/Inv is already included in Combinational area, never add it again.
    circuit_total = sum(row["area_um2"] for row in circuit_records)
    if not _close_enough(circuit_total, total_area):
        raise AreaReportError("circuit-type area categories do not close to total")

    modules = {}
    for key, chinese_label, english_label, instance in AREA_CATEGORIES:
        matches = re.findall(
            r"^\s*%s\s+(%s)\s+(%s)(?:\s+|$)"
            % (re.escape(instance), FLOAT_PATTERN, FLOAT_PATTERN),
            text,
            re.MULTILINE,
        )
        if not matches:
            raise AreaReportError("missing top-level ICC hierarchy %s" % instance)
        if len(matches) != 1:
            raise AreaReportError("duplicate top-level ICC hierarchy %s" % instance)
        area = float(matches[0][0])
        if math.isnan(area) or math.isinf(area):
            raise AreaReportError("non-finite area for top-level hierarchy %s" % instance)
        if area < 0.0:
            raise AreaReportError("negative area for top-level hierarchy %s" % instance)
        modules[key] = {
            "category_key": key,
            "category": chinese_label,
            "chart_label": english_label,
            "instance": instance,
            "area_um2": area,
        }
    return {
        "source_cel": SOURCE_CEL,
        "total_cell_area_um2": total_area,
        "modules": modules,
        "circuit_records": circuit_records,
        "cpu_total_cell_area_um2": modules["cpu_subsystem"]["area_um2"],
        "cpu_records": parse_cpu_breakdown(text, modules["cpu_subsystem"]["area_um2"]),
    }


def parse_qor_report(path):
    text = read_text(path)
    return {
        "qor_cell_area_um2": _single_float(
            r"^\s*Cell Area:\s*(%s)\s*$" % FLOAT_PATTERN, text, "QoR cell area"
        ),
        "design_area_um2": _single_float(
            r"^\s*Design Area:\s*(%s)\s*$" % FLOAT_PATTERN,
            text,
            "QoR design area",
        ),
    }


def parse_physical_summary(path):
    text = read_text(path)
    return {
        "core_area_um2": _single_float(
            r"^Core area\s*:\s*(%s)\s*$" % FLOAT_PATTERN, text, "core area"
        ),
        "cell_utilization_percent": _single_float(
            r"^Cell Utilization\(non-fixed\)\s*=\s*(%s)%%"
            % FLOAT_PATTERN,
            text,
            "cell utilization",
        ),
        "total_leaf_cell_area_um2": _single_float(
            r"^TOTAL LEAF CELLS\s+[0-9]+\s+(%s)(?:\s+|$)" % FLOAT_PATTERN,
            text,
            "total leaf cell area",
        ),
        "normal_cell_area_um2": _single_float(
            r"^\s*NORMAL CELLS\s+[0-9]+\s+(%s)(?:\s+|$)" % FLOAT_PATTERN,
            text,
            "normal cell area",
        ),
        "physical_only_cell_area_um2": _single_float(
            r"^\s*PHYSONLY CELLS\s+[0-9]+\s+(%s)(?:\s+|$)" % FLOAT_PATTERN,
            text,
            "physical-only cell area",
        ),
    }


def collect_area_data(hierarchy_path, qor_path, physical_path):
    data = parse_hierarchy_report(hierarchy_path)
    data.update(parse_qor_report(qor_path))
    data.update(parse_physical_summary(physical_path))
    for label, key in (
        ("QoR cell area", "qor_cell_area_um2"),
        ("design area", "design_area_um2"),
        ("core area", "core_area_um2"),
        ("total leaf cell area", "total_leaf_cell_area_um2"),
        ("normal cell area", "normal_cell_area_um2"),
        ("physical-only cell area", "physical_only_cell_area_um2"),
    ):
        if data[key] < 0.0:
            raise AreaReportError("%s must not be negative" % label)
    if data["core_area_um2"] <= 0.0:
        raise AreaReportError("core area must be positive")
    if not 0.0 <= data["cell_utilization_percent"] <= 100.0:
        raise AreaReportError("cell utilization must be between 0 and 100 percent")
    total = data["total_cell_area_um2"]
    for label, value in (
        ("QoR cell area", data["qor_cell_area_um2"]),
        ("normal cell area", data["normal_cell_area_um2"]),
    ):
        if not _close_enough(total, value):
            raise AreaReportError(
                "hierarchical total %.6f disagrees with %s %.6f"
                % (total, label, value)
            )
    leaf_sum = data["normal_cell_area_um2"] + data["physical_only_cell_area_um2"]
    if not _close_enough(leaf_sum, data["total_leaf_cell_area_um2"]):
        raise AreaReportError(
            "normal and physical-only cell areas do not close to total leaf area"
        )

    records = []
    known_area = 0.0
    for key, unused_chinese, unused_english, unused_instance in AREA_CATEGORIES:
        record = dict(data["modules"][key])
        known_area += record["area_um2"]
        records.append(record)
    residual = total - known_area
    tolerance = max(0.1, total * 1.0e-6)
    if residual < -tolerance:
        raise AreaReportError(
            "named top-level module area exceeds hierarchical total by %.6f um2"
            % (-residual)
        )
    if residual < 0.0:
        residual = 0.0
    other_key, other_chinese, other_english, other_instance = OTHER_CATEGORY
    records.append(
        {
            "category_key": other_key,
            "category": other_chinese,
            "chart_label": other_english,
            "instance": other_instance,
            "area_um2": residual,
        }
    )
    for record in records:
        record["share_percent"] = 100.0 * (record["area_um2"] / total)
    if not _close_enough(sum(row["area_um2"] for row in records), total):
        raise AreaReportError("functional area categories do not close to total")
    data["records"] = records
    return data


def display_number(value, digits=9):
    return ("%%.%dg" % digits) % float(value)


def _csv_value(value):
    if isinstance(value, float):
        value = "%.6f" % value
    elif not isinstance(value, text_type):
        value = text_type(value)
    if sys.version_info[0] < 3 and isinstance(value, text_type):
        return value.encode("utf-8")
    return value


def write_csv_report(path, data, record_key="records", fields=CSV_FIELDS):
    ensure_dir(os.path.dirname(path))
    temporary = path + ".tmp.%d" % os.getpid()
    if sys.version_info[0] < 3:
        handle = open(temporary, "wb")
    else:
        handle = io.open(temporary, "w", encoding="utf-8", newline="")
    try:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for record in data[record_key]:
            writer.writerow(
                dict((field, _csv_value(record[field])) for field in fields)
            )
    finally:
        handle.close()
    os.rename(temporary, path)


def markdown_report(data):
    lines = [
        u"# ICC 最终系统面积构成",
        u"",
        u"来源：只读重新打开 `%s` CEL 后生成的层次面积报告。" % data["source_cel"],
        u"",
        u"| 指标 | 面积/数值 |",
        u"|---|---:|",
        u"| 两种分类的共同分母（normal/logical cell area，含 SRAM 宏） | %s µm² |"
        % display_number(data["total_cell_area_um2"]),
        u"| ICC Design Area | %s µm² |" % display_number(data["design_area_um2"]),
        u"| Physical-only cell area | %s µm² |"
        % display_number(data["physical_only_cell_area_um2"]),
        u"| Total leaf cell area | %s µm² |"
        % display_number(data["total_leaf_cell_area_um2"]),
        u"| Core area | %s µm² |" % display_number(data["core_area_um2"]),
        u"| Cell utilization (non-fixed) | %s%% |"
        % display_number(data["cell_utilization_percent"]),
        u"",
        u"| 功能模块 | ICC 层次 | 面积 (µm²) | 占逻辑单元面积 |",
        u"|---|---|---:|---:|",
    ]
    for record in data["records"]:
        lines.append(
            u"| %s | `%s` | %s | %.2f%% |"
            % (
                record["category"],
                record["instance"],
                display_number(record["area_um2"]),
                record["share_percent"],
            )
        )
    lines.extend(
        (
            u"",
            u"![ICC 最终功能模块面积饼图](icc_area_breakdown.png)",
            u"",
            u"## 按电路性质划分",
            u"",
            u"| 电路性质 | 面积 (µm²) | 占逻辑单元面积 |",
            u"|---|---:|---:|",
        )
    )
    for record in data["circuit_records"]:
        lines.append(u"| %s | %s | %.2f%% |" % (
            record["category"], display_number(record["area_um2"]),
            record["share_percent"],
        ))
    lines.extend(
        (
            u"",
            u"![ICC 最终电路性质面积饼图](icc_area_by_circuit.png)",
            u"",
            u"## CPU 内部面积分解",
            u"",
            u"分母为 CPU 子系统 `x_sub_system` 的面积：%s µm²。"
            % display_number(data["cpu_total_cell_area_um2"]),
            u"",
            u"| CPU 内部模块 | 面积 (µm²) | 占 CPU 子系统面积 |",
            u"|---|---:|---:|",
        )
    )
    for record in data["cpu_records"]:
        lines.append(u"| %s | %s | %.2f%% |" % (
            record["category"], display_number(record["area_um2"]),
            record["share_percent"],
        ))
    lines.extend(
        (
            u"",
            u"![CPU 内部面积分解图](icc_cpu_area_breakdown.png)",
            u"",
            u"执行单元包含 ALU、乘除法及其局部逻辑；CSR 包含内部计数器；取指包含预取缓存等子模块。各项取全局面积，不重复累加其后代。",
            u"“其他 CPU 逻辑”是 CPU 子系统总面积减去六个命名模块，包含写回、时钟门控、核心局部逻辑及子系统外围逻辑。",
            u"",
            u"## 统计口径",
            u"",
            u"- 六个命名模块取 `report_area -hierarchy` 的顶层全局面积，彼此互斥。",
            u"- “其他顶层逻辑”为总逻辑单元面积扣除六个命名模块后的残差，包含顶层时钟和胶合逻辑。",
            u"- SRAM 宏面积归入对应 SRAM；filler、tap 等 physical-only 单元不能按逻辑层次归属，因此不进入饼图。",
            u"- 电路性质直接取同一份 ICC 报告的 `Combinational area`、`Noncombinational area` 和 `Macro/Black Box area`。",
            u"- 组合逻辑包含缓冲器/反相器，不能再加一次 `Buf/Inv area`；时序单元按 ICC 的非组合分类统计，不能解释为仅有寄存器。",
            u"- SRAM 在电路性质图中属于宏/黑盒单元；ROM 按其实际映射的组合、时序或宏单元归类，不按模块名称推断。",
            u"- 两种分类分别与同一个总面积核对，并与 QoR 和 physical summary 交叉检查；允许报告舍入误差（max(0.1 µm², 总面积 × 10⁻⁶)）。",
            u"- Core area 是版图边界占地，不是饼图各项之和。",
            u"",
        )
    )
    return u"\n".join(lines)


def _load_cairo():
    try:
        import cairo
        return cairo
    except ImportError:
        raise AreaReportError(
            "PyCairo is required for PNG output (python -c 'import cairo')"
        )


def _text(context, x, y, value, size, bold=False, color=(0.12, 0.15, 0.20)):
    context.set_source_rgb(*color)
    context.select_font_face(
        "Sans",
        0,
        1 if bold else 0,
    )
    context.set_font_size(size)
    context.move_to(x, y)
    context.show_text(value)


def render_png(path, data, record_key="records"):
    cairo = _load_cairo()
    width, height = 900, 720
    temporary = path + ".tmp.%d.png" % os.getpid()
    ensure_dir(os.path.dirname(path))
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    context = cairo.Context(surface)
    context.set_source_rgb(1.0, 1.0, 1.0)
    context.paint()
    circuit_view = record_key == "circuit_records"
    cpu_view = record_key == "cpu_records"
    title = "ICC Final Area by Circuit Type" if circuit_view else "ICC Final Functional Area Breakdown"
    if cpu_view:
        title = "ICC Final CPU Area Breakdown"
    records = data[record_key]
    total = data["cpu_total_cell_area_um2"] if cpu_view else data["total_cell_area_um2"]
    subtitle = (
        "%s | CPU subsystem area %.3f um2 | shares within CPU" % (data["source_cel"], total)
        if cpu_view else
        "%s | logical cell area %.3f um2 | core area %.3f um2"
        % (data["source_cel"], total, data["core_area_um2"])
    )
    _text(context, 35, 57, title, 30, True)
    _text(
        context,
        35,
        89,
        subtitle,
        15,
        False,
        (0.42, 0.45, 0.50),
    )

    panel_x, panel_y, panel_width, panel_height = 25, 115, width - 50, 530
    context.set_source_rgb(0.97, 0.98, 0.99)
    context.rectangle(panel_x, panel_y, panel_width, panel_height)
    context.fill()
    center_x, center_y, radius = 280.0, 380.0, 220.0
    colors = (
        (0.25, 0.36, 0.55),
        (0.93, 0.49, 0.18),
        (0.22, 0.68, 0.45),
        (0.42, 0.65, 0.82),
        (0.94, 0.72, 0.25),
        (0.55, 0.42, 0.72),
        (0.58, 0.60, 0.63),
    )
    angle = -math.pi / 2.0
    for index, record in enumerate(records):
        value = max(0.0, record["area_um2"])
        if value <= 0.0:
            continue
        next_angle = angle + 2.0 * math.pi * value / total
        context.move_to(center_x, center_y)
        context.arc(center_x, center_y, radius, angle, next_angle)
        context.close_path()
        context.set_source_rgb(*colors[index])
        context.fill_preserve()
        context.set_source_rgb(1.0, 1.0, 1.0)
        context.set_line_width(2.0)
        context.stroke()
        if record["share_percent"] >= 3.0:
            mid_angle = (angle + next_angle) / 2.0
            label = "%.1f%%" % record["share_percent"]
            context.set_font_size(20)
            extents = context.text_extents(label)
            label_x = center_x + radius * 0.68 * math.cos(mid_angle)
            label_y = center_y + radius * 0.68 * math.sin(mid_angle)
            _text(context, label_x - extents[2] / 2.0, label_y + 7,
                  label, 20, False, (1.0, 1.0, 1.0))
        angle = next_angle

    legend_x = 550
    legend_step = 68
    legend_y = center_y - ((len(records) - 1) * legend_step + 43) / 2.0
    for index, record in enumerate(records):
        row_y = legend_y + index * legend_step
        context.set_source_rgb(*colors[index])
        context.rectangle(legend_x, row_y, 25, 22)
        context.fill()
        _text(context, legend_x + 38, row_y + 18, record["chart_label"], 17, True)
        _text(
            context,
            legend_x + 38,
            row_y + 43,
            "%.3f um2 | %.2f%%" % (record["area_um2"], record["share_percent"]),
            15,
            False,
            (0.42, 0.45, 0.50),
        )
    _text(
        context,
        35,
        688,
        ("Other CPU logic includes writeback, clock gating, and core/subsystem local logic."
         if cpu_view else
         "Combinational includes buffers/inverters; sequential follows ICC; macros include SRAM."
         if circuit_view else
         "Functional slices include SRAM macros; physical-only filler/tap area is reported separately."),
        14,
        False,
        (0.42, 0.45, 0.50),
    )
    surface.write_to_png(temporary)
    os.rename(temporary, path)


def report_paths(project_root):
    raw_dir = os.path.join(project_root, "icc", "reports")
    output_dir = os.path.join(project_root, "report")
    return {
        "hierarchy": os.path.join(raw_dir, "area_metal_fill_icc.hier.rpt"),
        "qor": os.path.join(raw_dir, "area_metal_fill_icc.qor"),
        "physical": os.path.join(raw_dir, "area_metal_fill_icc.sum"),
        "csv": os.path.join(output_dir, "icc_area_breakdown.csv"),
        "markdown": os.path.join(output_dir, "icc_area_breakdown.md"),
        "png": os.path.join(output_dir, "icc_area_breakdown.png"),
        "circuit_csv": os.path.join(output_dir, "icc_area_by_circuit.csv"),
        "circuit_png": os.path.join(output_dir, "icc_area_by_circuit.png"),
        "cpu_csv": os.path.join(output_dir, "icc_cpu_area_breakdown.csv"),
        "cpu_png": os.path.join(output_dir, "icc_cpu_area_breakdown.png"),
    }


def generate_reports(project_root):
    paths = report_paths(os.path.abspath(project_root))
    _load_cairo()
    data = collect_area_data(paths["hierarchy"], paths["qor"], paths["physical"])
    write_csv_report(paths["csv"], data)
    write_csv_report(paths["circuit_csv"], data, "circuit_records", CIRCUIT_CSV_FIELDS)
    write_csv_report(paths["cpu_csv"], data, "cpu_records")
    atomic_write_text(paths["markdown"], markdown_report(data))
    render_png(paths["png"], data)
    render_png(paths["circuit_png"], data, "circuit_records")
    render_png(paths["cpu_png"], data, "cpu_records")
    return paths


def main(argv=None):
    default_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root",
        default=default_root,
        help="repository root containing icc/reports and report (default: script parent)",
    )
    arguments = parser.parse_args(argv)
    try:
        paths = generate_reports(arguments.project_root)
    except (AreaReportError, IOError, OSError) as error:
        print("ERROR: %s" % error, file=sys.stderr)
        return 1
    for key in ("csv", "circuit_csv", "cpu_csv", "markdown", "png", "circuit_png", "cpu_png"):
        print("wrote %s" % paths[key])
    return 0


if __name__ == "__main__":
    sys.exit(main())
