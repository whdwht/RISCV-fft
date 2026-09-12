#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import print_function

"""Resumable FFT16 software benchmark and headless report generator.

The EDA host guarantees Python 2.7 but not scientific Python packages.  Keep
the orchestration and CSV/Markdown generation in the standard library; use
the already-installed PyCairo ImageSurface API for headless PNG rendering.
"""

import argparse
import csv
import fcntl
import hashlib
import io
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import time


try:
    text_type = unicode
except NameError:
    text_type = str


SCHEMA_VERSION = 2
CLOCK_PERIOD_NS = 3.0
FFT_POINTS = 16.0
OPTIMIZATION_LEVELS = ("O1", "O2", "O3", "Os")
OPTIMIZATION_TIE_ORDER = {"O3": 0, "O2": 1, "Os": 2, "O1": 3}
BASELINE = {
    "id": "asm_legacy",
    "label": "ASM legacy",
    "variant": "assembly",
    "opt_level": "manual",
    "status": "LEGACY",
    "cycles": 506,
    "trigger1": 83,
    "done1": 87,
    "trigger2": 151,
    "done2": 155,
    "first_result": None,
    "final_result": 506,
    "latency_ns": 1518.0,
    "soc_total_power_mw": 34.3,
    "soc_window_energy_nj": 52.122623,
    "source": "scan_runs/default:f333p333333_w430p72_h560",
}
BASELINE_SYSTEM_PERFORMANCE = FFT_POINTS * 1.0e9 / BASELINE["latency_ns"]
BASELINE_COMPUTE_EFFICIENCY = (
    FFT_POINTS * 1.0e9 / BASELINE["soc_window_energy_nj"]
)

CSV_FIELDS = (
    "id", "label", "variant", "opt_level", "compiler_flags", "status",
    "image_bytes", "artifact_sha256",
    "cycles", "trigger1", "done1", "trigger2", "done2",
    "first_result", "final_result", "pre_fft1_cycles", "fft1_wait_cycles",
    "between_fft_cycles", "fft2_wait_cycles", "post_fft2_cycles",
    "latency_ns", "system_performance_points_per_second",
    "power_window_duration_ns",
    "soc_internal_power_mw",
    "soc_switching_power_mw", "soc_dynamic_power_mw",
    "soc_leakage_power_mw", "soc_total_power_mw",
    "soc_window_energy_nj", "nominal_energy_nj",
    "compute_efficiency_points_per_joule", "cycle_reduction_percent",
    "speedup", "performance_change_percent", "power_change_percent",
    "window_energy_change_percent", "efficiency_change_percent",
    "rtl_log", "gate_func_log",
    "gate_power_log", "power_summary", "source",
)

BREAKDOWN_CSV_FIELDS = (
    "solution_id", "breakdown", "category", "cycles", "power_mw",
    "energy_nj", "share_percent",
)


class BenchmarkError(Exception):
    pass


class RunLock(object):
    def __init__(self, path):
        self.path = path
        self.handle = None

    def __enter__(self):
        ensure_dir(os.path.dirname(self.path))
        self.handle = open(self.path, "a+")
        try:
            fcntl.flock(self.handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except IOError:
            self.handle.close()
            self.handle = None
            raise BenchmarkError("another FFT16 benchmark process holds %s" % self.path)
        self.handle.seek(0)
        self.handle.truncate()
        self.handle.write("pid=%d host=%s started=%s\n" % (
            os.getpid(), os.uname()[1], utc_now()
        ))
        self.handle.flush()
        return self

    def __exit__(self, unused_type, unused_value, unused_traceback):
        if self.handle is not None:
            fcntl.flock(self.handle.fileno(), fcntl.LOCK_UN)
            self.handle.close()
        return False


def utc_now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def ensure_dir(path):
    if path and not os.path.isdir(path):
        os.makedirs(path)


def read_text(path):
    with io.open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


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


def atomic_write_json(path, value):
    atomic_write_text(
        path, json.dumps(value, indent=2, sort_keys=True, ensure_ascii=True) + "\n"
    )


def read_json(path):
    with io.open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            block = handle.read(1024 * 1024)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def fingerprint(paths, extra=""):
    digest = hashlib.sha256()
    digest.update(extra.encode("utf-8"))
    expanded = []
    for path in paths:
        if os.path.isdir(path):
            for root, directories, files in os.walk(path):
                directories[:] = sorted(
                    value for value in directories
                    if value not in ("build", "runs", "__pycache__")
                )
                for name in sorted(files):
                    expanded.append(os.path.join(root, name))
        else:
            expanded.append(path)
    for path in sorted(set(expanded)):
        digest.update(path.encode("utf-8"))
        digest.update(b"\0")
        if os.path.isfile(path):
            digest.update(sha256_file(path).encode("ascii"))
        else:
            digest.update(b"MISSING")
        digest.update(b"\0")
    return digest.hexdigest()


def find_executable(name):
    if os.path.isabs(name):
        return name if os.path.isfile(name) and os.access(name, os.X_OK) else None
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = os.path.join(directory or ".", name)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def key_values(path):
    values = {}
    for line in read_text(path).splitlines():
        fields = line.strip().split()
        if len(fields) == 2:
            values[fields[0]] = fields[1]
    return values


METRIC_PATTERN = re.compile(
    r"^FFT16_METRIC\s+cycles=(\d+)\s+trigger1=(-?\d+)\s+done1=(-?\d+)"
    r"\s+trigger2=(-?\d+)\s+done2=(-?\d+)\s+first_result=(-?\d+)"
    r"\s+final_result=(-?\d+)\s*$", re.MULTILINE
)

PHASE_METRIC_PATTERN = re.compile(
    r"^FFT16_PHASE_METRIC\s+first_even_input=(\d+)\s+first_odd_input=(\d+)"
    r"\s+bin0_done=(\d+)\s+bin1_done=(\d+)\s+bin2_done=(\d+)"
    r"\s+bin3_done=(\d+)\s+bin4_done=(\d+)\s+bin5_done=(\d+)"
    r"\s+bin6_done=(\d+)\s+bin7_done=(\d+)\s*$", re.MULTILINE
)


def parse_simulation_log(path):
    log = read_text(path)
    if "CPU+FFT16 TEST PASS" not in log:
        raise BenchmarkError("self-checking simulation did not pass: %s" % path)
    match = METRIC_PATTERN.search(log)
    if not match:
        raise BenchmarkError("FFT16_METRIC is missing from %s" % path)
    names = (
        "cycles", "trigger1", "done1", "trigger2", "done2",
        "first_result", "final_result",
    )
    metrics = dict((name, int(value)) for name, value in zip(names, match.groups()))
    if metrics["cycles"] <= 0:
        raise BenchmarkError("non-positive cycle count in %s" % path)
    ordered = (
        metrics["trigger1"], metrics["done1"], metrics["trigger2"],
        metrics["done2"], metrics["first_result"], metrics["final_result"],
        metrics["cycles"],
    )
    if ordered[0] < 0 or any(left > right for left, right in zip(ordered, ordered[1:])):
        raise BenchmarkError("invalid FFT16 milestone order in %s" % path)
    phase_match = PHASE_METRIC_PATTERN.search(log)
    if not phase_match:
        raise BenchmarkError("FFT16_PHASE_METRIC is missing from %s" % path)
    phase_names = (
        "first_even_input", "first_odd_input",
        "bin0_done", "bin1_done", "bin2_done", "bin3_done",
        "bin4_done", "bin5_done", "bin6_done", "bin7_done",
    )
    metrics.update(dict(
        (name, int(value)) for name, value in zip(phase_names, phase_match.groups())
    ))
    phase_order = (
        metrics["first_even_input"], metrics["trigger1"], metrics["done1"],
        metrics["first_odd_input"], metrics["trigger2"], metrics["done2"],
        metrics["first_result"], metrics["bin0_done"], metrics["bin1_done"],
        metrics["bin2_done"], metrics["bin3_done"], metrics["bin4_done"],
        metrics["bin5_done"], metrics["bin6_done"], metrics["bin7_done"],
        metrics["final_result"], metrics["cycles"],
    )
    if any(left > right for left, right in zip(phase_order, phase_order[1:])):
        raise BenchmarkError("invalid FFT16 detailed phase order in %s" % path)
    if metrics["bin7_done"] != metrics["final_result"]:
        raise BenchmarkError("FFT16 final bin/result mismatch in %s" % path)
    return metrics


def parse_power_summary(path):
    values = key_values(path)
    if values.get("POWER_RESULT") != "PASS":
        raise BenchmarkError("PrimeTime power summary did not pass: %s" % path)
    required_float = (
        "POWER_WINDOW_DURATION_NS", "SOC_INTERNAL_POWER_MW",
        "SOC_SWITCHING_POWER_MW", "SOC_DYNAMIC_POWER_MW",
        "SOC_LEAKAGE_POWER_MW", "SOC_TOTAL_POWER_MW",
        "SOC_WINDOW_ENERGY_NJ", "SOC_INTERNAL_ENERGY_NJ",
        "SOC_INTERNAL_ENERGY_PERCENT", "SOC_SWITCHING_ENERGY_NJ",
        "SOC_SWITCHING_ENERGY_PERCENT", "SOC_LEAKAGE_ENERGY_NJ",
        "SOC_LEAKAGE_ENERGY_PERCENT", "SOC_CPU_SUBSYSTEM_POWER_MW",
        "SOC_CPU_SUBSYSTEM_ENERGY_NJ", "SOC_CPU_SUBSYSTEM_ENERGY_PERCENT",
        "SOC_INSTRUCTION_SRAM_POWER_MW", "SOC_INSTRUCTION_SRAM_ENERGY_NJ",
        "SOC_INSTRUCTION_SRAM_ENERGY_PERCENT", "SOC_DATA_SRAM_POWER_MW",
        "SOC_DATA_SRAM_ENERGY_NJ", "SOC_DATA_SRAM_ENERGY_PERCENT",
        "SOC_ROM_POWER_MW", "SOC_ROM_ENERGY_NJ", "SOC_ROM_ENERGY_PERCENT",
        "SOC_DATA_FABRIC_POWER_MW", "SOC_DATA_FABRIC_ENERGY_NJ",
        "SOC_DATA_FABRIC_ENERGY_PERCENT", "SOC_OTHER_POWER_MW",
        "SOC_OTHER_ENERGY_NJ", "SOC_OTHER_ENERGY_PERCENT",
        "FFT_TOTAL_POWER_MW", "FFT_SOC_POWER_PERCENT", "FFT_WINDOW_ENERGY_NJ",
    )
    parsed = {}
    for key in required_float:
        try:
            parsed[key.lower()] = float(values[key])
        except (KeyError, ValueError):
            raise BenchmarkError("missing or invalid %s in %s" % (key, path))
    try:
        parsed["power_window_cycles"] = int(values["POWER_WINDOW_CYCLES"])
    except (KeyError, ValueError):
        raise BenchmarkError("invalid POWER_WINDOW_CYCLES in %s" % path)
    type_energy = sum(parsed[key] for key in (
        "soc_internal_energy_nj", "soc_switching_energy_nj",
        "soc_leakage_energy_nj",
    ))
    hierarchy_energy = sum(parsed[key] for key in (
        "soc_cpu_subsystem_energy_nj", "fft_window_energy_nj",
        "soc_instruction_sram_energy_nj", "soc_data_sram_energy_nj",
        "soc_rom_energy_nj", "soc_data_fabric_energy_nj", "soc_other_energy_nj",
    ))
    total_energy = parsed["soc_window_energy_nj"]
    tolerance = max(1.0e-6, total_energy * 1.0e-6)
    if abs(type_energy - total_energy) > tolerance:
        raise BenchmarkError("SoC energy-type breakdown does not close in %s" % path)
    if abs(hierarchy_energy - total_energy) > tolerance:
        raise BenchmarkError("SoC hierarchy energy breakdown does not close in %s" % path)
    return parsed


def image_size_from_sha(path):
    values = key_values(path)
    try:
        return int(values["IMAGE_BYTES"])
    except (KeyError, ValueError):
        raise BenchmarkError("IMAGE_BYTES is missing from %s" % path)


def choose_best(rows):
    if not rows:
        raise BenchmarkError("cannot choose an optimization from an empty result set")
    for row in rows:
        if "cycles" not in row or "image_bytes" not in row:
            raise BenchmarkError("candidate is missing cycle or image-size data")
    return min(
        rows,
        key=lambda row: (
            int(row["cycles"]), int(row["image_bytes"]),
            OPTIMIZATION_TIE_ORDER.get(row["opt_level"], 99),
        ),
    )


def derived_metrics(row):
    result = dict(row)
    cycles = result.get("cycles")
    if cycles is not None:
        cycles = int(cycles)
        result["cycles"] = cycles
        result["latency_ns"] = cycles * CLOCK_PERIOD_NS
        result["system_performance_points_per_second"] = (
            FFT_POINTS * 1.0e9 / result["latency_ns"]
        )
        result["performance_change_percent"] = 100.0 * (
            result["system_performance_points_per_second"]
            / BASELINE_SYSTEM_PERFORMANCE - 1.0
        )
        result["cycle_reduction_percent"] = (
            100.0 * (BASELINE["cycles"] - cycles) / BASELINE["cycles"]
        )
        result["speedup"] = float(BASELINE["cycles"]) / cycles
        milestones = ("trigger1", "done1", "trigger2", "done2")
        if all(result.get(name) is not None and result.get(name) >= 0
               for name in milestones):
            result["pre_fft1_cycles"] = result["trigger1"]
            result["fft1_wait_cycles"] = result["done1"] - result["trigger1"]
            result["between_fft_cycles"] = result["trigger2"] - result["done1"]
            result["fft2_wait_cycles"] = result["done2"] - result["trigger2"]
            result["post_fft2_cycles"] = cycles - result["done2"]

    power = result.get("soc_total_power_mw")
    if cycles is not None and power is not None:
        power = float(power)
        result["soc_total_power_mw"] = power
        result["nominal_energy_nj"] = power * result["latency_ns"] / 1000.0
        result["power_change_percent"] = (
            100.0 * (power - BASELINE["soc_total_power_mw"])
            / BASELINE["soc_total_power_mw"]
        )
    energy = result.get("soc_window_energy_nj")
    if energy is not None:
        energy = float(energy)
        result["soc_window_energy_nj"] = energy
        result["compute_efficiency_points_per_joule"] = (
            FFT_POINTS * 1.0e9 / energy
        )
        result["window_energy_change_percent"] = (
            100.0 * (energy - BASELINE["soc_window_energy_nj"])
            / BASELINE["soc_window_energy_nj"]
        )
        result["efficiency_change_percent"] = 100.0 * (
            result["compute_efficiency_points_per_joule"]
            / BASELINE_COMPUTE_EFFICIENCY - 1.0
        )
    return result


def optimal_row(state):
    selected_id = state.get("selected", {}).get("optimized")
    row = state.get("runs", {}).get(selected_id) if selected_id else None
    return derived_metrics(row) if row else None


def cycle_breakdowns(row):
    """Return full-window phases and post-FFT2 twiddle groups."""
    source = row.get("power_metrics") or row
    required = (
        "cycles", "first_even_input", "trigger1", "done1",
        "first_odd_input", "trigger2", "done2", "bin0_done", "bin1_done",
        "bin2_done", "bin3_done", "bin4_done", "bin5_done", "bin6_done",
        "bin7_done", "final_result",
    )
    if not all(source.get(key) is not None for key in required):
        raise BenchmarkError("selected optimized run has no detailed power-run milestones")
    full_cycles = int(source["cycles"])
    phases = (
        ("startup", "Startup to first even input", int(source["first_even_input"])),
        ("even_input", "Build/feed even samples",
         int(source["trigger1"]) - int(source["first_even_input"])),
        ("fft8_even", "FFT8(E)", int(source["done1"]) - int(source["trigger1"])),
        ("read_even_prepare_odd", "Read E / prepare odd samples",
         int(source["first_odd_input"]) - int(source["done1"])),
        ("odd_input", "Build/feed odd samples",
         int(source["trigger2"]) - int(source["first_odd_input"])),
        ("fft8_odd", "FFT8(O)", int(source["done2"]) - int(source["trigger2"])),
        ("merge_writeback", "Read O / merge / writeback",
         int(source["final_result"]) - int(source["done2"])),
    )
    if any(value < 0 for unused_key, unused_label, value in phases):
        raise BenchmarkError("negative cycle count in detailed phase breakdown")
    if sum(value for unused_key, unused_label, value in phases) != full_cycles:
        raise BenchmarkError("detailed phase cycles do not sum to total cycles")

    bin_done = [int(source["bin%d_done" % index]) for index in range(8)]
    previous = int(source["done2"])
    bin_cycles = []
    for value in bin_done:
        bin_cycles.append(value - previous)
        previous = value
    if any(value < 0 for value in bin_cycles):
        raise BenchmarkError("negative per-bin merge/writeback cycle count")
    post_cycles = full_cycles - int(source["done2"])
    if sum(bin_cycles) != post_cycles:
        raise BenchmarkError("per-bin cycles do not sum to post-FFT2 cycles")
    twiddle_groups = (
        ("unity_k0", "W0: unity (k=0)", bin_cycles[0]),
        ("swap_k4", "W4: swap/sign (k=4)", bin_cycles[4]),
        ("quarter_k2_k6", "W2/W6: pi/4 (k=2,6)",
         bin_cycles[2] + bin_cycles[6]),
        ("general_odd_k", "W1/W3/W5/W7: general",
         sum(bin_cycles[index] for index in (1, 3, 5, 7))),
    )
    if sum(value for unused_key, unused_label, value in twiddle_groups) != post_cycles:
        raise BenchmarkError("twiddle groups do not sum to post-FFT2 cycles")
    return phases, twiddle_groups


def energy_breakdowns(row):
    hierarchy_specs = (
        ("cpu_subsystem", "CPU subsystem", "soc_cpu_subsystem"),
        ("fft8_accelerator", "FFT8 accelerator", "fft"),
        ("instruction_sram", "Instruction SRAM", "soc_instruction_sram"),
        ("data_sram", "Data SRAM", "soc_data_sram"),
        ("rom", "ROM", "soc_rom"),
        ("data_fabric", "Data fabric", "soc_data_fabric"),
        ("other_top_level", "Other top-level logic", "soc_other"),
    )
    type_specs = (
        ("cell_internal", "Cell internal", "soc_internal"),
        ("net_switching", "Net switching", "soc_switching"),
        ("cell_leakage", "Cell leakage", "soc_leakage"),
    )
    hierarchy = []
    for key, label, prefix in hierarchy_specs:
        power_key = prefix + "_total_power_mw" if prefix == "fft" else prefix + "_power_mw"
        energy_key = prefix + "_window_energy_nj" if prefix == "fft" else prefix + "_energy_nj"
        if row.get(power_key) is None or row.get(energy_key) is None:
            raise BenchmarkError("selected optimized run has no hierarchy energy breakdown")
        hierarchy.append((key, label, float(row[power_key]), float(row[energy_key])))
    energy_types = []
    for key, label, prefix in type_specs:
        power_key = prefix + "_power_mw"
        energy_key = prefix + "_energy_nj"
        if row.get(power_key) is None or row.get(energy_key) is None:
            raise BenchmarkError("selected optimized run has no energy-type breakdown")
        energy_types.append((key, label, float(row[power_key]), float(row[energy_key])))
    total = float(row["soc_window_energy_nj"])
    tolerance = max(1.0e-6, total * 1.0e-6)
    if abs(sum(value[3] for value in hierarchy) - total) > tolerance:
        raise BenchmarkError("hierarchy energy breakdown does not close to total")
    if abs(sum(value[3] for value in energy_types) - total) > tolerance:
        raise BenchmarkError("energy-type breakdown does not close to total")
    return tuple(hierarchy), tuple(energy_types)


def display(value, digits=6):
    if value is None or value == "":
        return ""
    if isinstance(value, float):
        return ("%%.%dg" % digits) % value
    return str(value)


def write_csv_report(path, rows):
    ensure_dir(os.path.dirname(path))
    temporary = path + ".tmp.%d" % os.getpid()
    if sys.version_info[0] < 3:
        handle = open(temporary, "wb")
    else:
        handle = open(temporary, "w", newline="")
    try:
        writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow(dict((key, display(row.get(key))) for key in CSV_FIELDS))
    finally:
        handle.close()
    os.rename(temporary, path)


def breakdown_records(state):
    row = optimal_row(state)
    if row is None:
        return []
    try:
        phases, twiddle_groups = cycle_breakdowns(row)
        hierarchy, energy_types = energy_breakdowns(row)
    except BenchmarkError:
        return []
    records = []
    total_cycles = float((row.get("power_metrics") or row)["cycles"])
    post_cycles = float(sum(value for unused_key, unused_label, value in twiddle_groups))
    for key, unused_label, cycles in phases:
        records.append({
            "solution_id": row["id"], "breakdown": "total_cycles",
            "category": key, "cycles": cycles,
            "share_percent": 100.0 * cycles / total_cycles,
        })
    for key, unused_label, cycles in twiddle_groups:
        records.append({
            "solution_id": row["id"], "breakdown": "post_fft2_cycles",
            "category": key, "cycles": cycles,
            "share_percent": 100.0 * cycles / post_cycles,
        })
    total_energy = float(row["soc_window_energy_nj"])
    for breakdown, values in (
            ("energy_by_hierarchy", hierarchy), ("energy_by_type", energy_types)):
        for key, unused_label, power_mw, energy_nj in values:
            records.append({
                "solution_id": row["id"], "breakdown": breakdown,
                "category": key, "power_mw": power_mw, "energy_nj": energy_nj,
                "share_percent": 100.0 * energy_nj / total_energy,
            })
    return records


def write_breakdown_csv(path, state):
    ensure_dir(os.path.dirname(path))
    temporary = path + ".tmp.%d" % os.getpid()
    if sys.version_info[0] < 3:
        handle = open(temporary, "wb")
    else:
        handle = open(temporary, "w", newline="")
    try:
        writer = csv.DictWriter(handle, fieldnames=BREAKDOWN_CSV_FIELDS)
        writer.writeheader()
        for row in breakdown_records(state):
            writer.writerow(dict(
                (key, display(row.get(key))) for key in BREAKDOWN_CSV_FIELDS
            ))
    finally:
        handle.close()
    os.rename(temporary, path)


def markdown_report(rows, state):
    baseline_phases = derived_metrics(BASELINE)
    one_fft_latency = baseline_phases["fft1_wait_cycles"]
    overlap_cycles = BASELINE["cycles"] - one_fft_latency
    fully_hidden_cycles = (
        BASELINE["cycles"] - baseline_phases["fft1_wait_cycles"]
        - baseline_phases["fft2_wait_cycles"]
    )
    lines = [
        u"# FFT16 软件优化结果", u"",
        u"生成时间：%s" % state.get("updated_at", utc_now()), u"",
        u"时钟周期：3 ns。汇编基线来自扫描点 "
        u"`f333p333333_w430p72_h560`，未在本次脚本中重跑。", u"",
        u"本次物理工件指纹：`%s`。" %
        state.get("physical_fingerprint", "unknown"), u"",
    ]
    if state.get("error"):
        lines.extend((u"> 本次流程未完整通过：%s" % state["error"], u""))
    lines.extend((
        u"| 版本 | 状态 | 编译 | 镜像(B) | 拍数 | 时间(ns) | 系统性能(point/s) | 功耗(mW) | 窗口能量(nJ) | 计算能效(point/J) | 加速比 |",
        u"|---|:---:|:---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ))
    for row in rows:
        lines.append(
            u"| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
                row.get("label", row.get("id", "")), row.get("status", ""),
                row.get("opt_level", ""), display(row.get("image_bytes")),
                display(row.get("cycles")), display(row.get("latency_ns")),
                display(row.get("system_performance_points_per_second")),
                display(row.get("soc_total_power_mw")),
                display(row.get("soc_window_energy_nj")),
                display(row.get("compute_efficiency_points_per_joule")),
                display(row.get("speedup")),
            )
        )
    lines.extend((u"", u"## 口径", u"", u"- CPU 完成时间 = 实测拍数 × 3 ns。",
                  u"- 系统性能 = 16 ÷ CPU 完成一次 16 点 FFT 的时间，单位 point/s。",
                  u"- VCD 窗口能量 = PT 时域平均 SoC 功率 × 实际 VCD 窗口时间。",
                  u"- 计算能效 = 16 ÷ VCD 窗口 SoC 总能量，单位 point/J。",
                  u"", u"## 汇编基线瓶颈与重叠上限", u"",
                  u"- 末次 FFT8 完成后的软件合并/写回为 %d/%d 拍（%.1f%%）。" % (
                      baseline_phases["post_fft2_cycles"], BASELINE["cycles"],
                      100.0 * baseline_phases["post_fft2_cycles"] / BASELINE["cycles"]),
                  u"- 两次 FFT8 等待合计 %d 拍（%.1f%%），并非主要周期来源。" % (
                      baseline_phases["fft1_wait_cycles"] + baseline_phases["fft2_wait_cycles"],
                      100.0 * (baseline_phases["fft1_wait_cycles"] +
                               baseline_phases["fft2_wait_cycles"]) / BASELINE["cycles"]),
                  u"- 仅将两次 FFT8 执行完美重叠，理论上从 506 降到 %d 拍："
                  u"减少 %.2f%%，加速 %.3f×。" % (
                      overlap_cycles,
                      100.0 * one_fft_latency / BASELINE["cycles"],
                      float(BASELINE["cycles"]) / overlap_cycles),
                  u"- 若连两段硬件等待都被其他软件工作完全隐藏，绝对上限为 %d 拍："
                  u"减少 %.2f%%，加速 %.3f×。" % (
                      fully_hidden_cycles,
                      100.0 * (BASELINE["cycles"] - fully_hidden_cycles) / BASELINE["cycles"],
                      float(BASELINE["cycles"]) / fully_hidden_cycles), u""))
    selected = optimal_row(state)
    if selected is not None:
        try:
            phases, twiddle_groups = cycle_breakdowns(selected)
            hierarchy, energy_types = energy_breakdowns(selected)
            phase_total = float(sum(value for unused_key, unused_label, value in phases))
            post_total = float(sum(
                value for unused_key, unused_label, value in twiddle_groups
            ))
            lines.extend((
                u"## 当前最优方案周期细分", u"",
                u"以下数据来自与功耗 VCD 同一次门级仿真，方案为 `%s`。"
                % selected.get("label", selected.get("id", "")), u"",
                u"| 阶段 | 周期 | 占完整计算窗口 |",
                u"|---|---:|---:|",
            ))
            phase_labels = {
                "startup": u"启动至首个偶序列输入",
                "even_input": u"构造并送入偶序列",
                "fft8_even": u"第一次 FFT8：E",
                "read_even_prepare_odd": u"读取 E 并准备奇序列",
                "odd_input": u"构造并送入奇序列",
                "fft8_odd": u"第二次 FFT8：O",
                "merge_writeback": u"读取 O、旋转合并与写回",
            }
            for key, label, cycles in phases:
                lines.append(u"| %s | %d | %.2f%% |" % (
                    phase_labels.get(key, label), cycles,
                    100.0 * cycles / phase_total,
                ))
            lines.extend((
                u"", u"FFT2 完成后的读取、旋转、蝶形合并和写回继续按旋转类型细分：",
                u"", u"| 旋转类型 | 周期 | 占 FFT2 后阶段 |",
                u"|---|---:|---:|",
            ))
            twiddle_labels = {
                "unity_k0": u"W0：单位旋转（k=0）",
                "swap_k4": u"W4：交换/取反（k=4）",
                "quarter_k2_k6": u"W2/W6：±π/4（k=2,6）",
                "general_odd_k": u"W1/W3/W5/W7：通用旋转",
            }
            for key, label, cycles in twiddle_groups:
                lines.append(u"| %s | %d | %.2f%% |" % (
                    twiddle_labels.get(key, label), cycles,
                    100.0 * cycles / post_total,
                ))

            total_energy = float(selected["soc_window_energy_nj"])
            lines.extend((
                u"", u"![当前最优方案周期饼图](fft16_sw_optimal_cycle_pies.png)",
                u"", u"## 当前最优方案能耗来源", u"",
                u"模块能量由同一完整执行窗内的层次平均功耗乘以窗口时长得到；"
                u"各模块是互斥的 SoC 顶层分支。", u"",
                u"| 硬件来源 | 平均功耗 (mW) | 能量 (nJ) | 占比 |",
                u"|---|---:|---:|---:|",
            ))
            hierarchy_labels = {
                "cpu_subsystem": u"CPU 子系统",
                "fft8_accelerator": u"FFT8 加速器",
                "instruction_sram": u"指令 SRAM",
                "data_sram": u"数据 SRAM",
                "rom": u"ROM",
                "data_fabric": u"数据总线",
                "other_top_level": u"其他顶层逻辑",
            }
            for key, label, power_mw, energy_nj in hierarchy:
                lines.append(u"| %s | %s | %s | %.2f%% |" % (
                    hierarchy_labels.get(key, label), display(power_mw),
                    display(energy_nj),
                    100.0 * energy_nj / total_energy,
                ))
            lines.extend((
                u"", u"| 功耗类型 | PT 平均功耗 (mW) | 分配能量 (nJ) | 占比 |",
                u"|---|---:|---:|---:|",
            ))
            type_labels = {
                "cell_internal": u"单元内部",
                "net_switching": u"网络翻转",
                "cell_leakage": u"单元漏电",
            }
            for key, label, power_mw, energy_nj in energy_types:
                lines.append(u"| %s | %s | %s | %.2f%% |" % (
                    type_labels.get(key, label), display(power_mw),
                    display(energy_nj),
                    100.0 * energy_nj / total_energy,
                ))
            lines.extend((
                u"", u"Internal/switching/leakage 的 PT 文本功耗存在末位舍入；"
                u"表中分配能量保留三者相对权重并归一到 %.6g nJ 的窗口总能量。"
                % total_energy,
                u"`Other top-level logic` 为 SoC 总功耗扣除已列顶层模块后的残差，"
                u"主要覆盖顶层时钟与胶合逻辑。", u"",
                u"![当前最优方案能耗饼图](fft16_sw_optimal_energy_pies.png)", u"",
            ))
        except BenchmarkError as error:
            lines.extend((
                u"## 当前最优方案详细细分", u"",
                u"> 暂无可绘制的详细数据：%s" % error, u"",
            ))
    return u"\n".join(lines)


def _load_cairo():
    try:
        import cairo
        return cairo
    except ImportError:
        raise BenchmarkError(
            "PyCairo is required for headless PNG output (python -c 'import cairo')"
        )


COLORS = (
    (0.25, 0.36, 0.55), (0.18, 0.58, 0.72),
    (0.22, 0.68, 0.45), (0.93, 0.49, 0.18),
)

PIE_COLORS = (
    (0.20, 0.35, 0.58), (0.16, 0.58, 0.72),
    (0.20, 0.68, 0.46), (0.94, 0.70, 0.22),
    (0.93, 0.45, 0.18), (0.63, 0.40, 0.72),
    (0.53, 0.57, 0.62), (0.82, 0.30, 0.42),
)


def _text(context, x, y, value, size=18, bold=False, color=(0.12, 0.14, 0.18)):
    context.set_source_rgb(*color)
    context.select_font_face(
        "Liberation Sans", 0, 1 if bold else 0
    )
    context.set_font_size(size)
    context.move_to(x, y)
    context.show_text(str(value))


def _panel(context, x, y, width, height, title):
    context.set_source_rgb(0.97, 0.98, 0.99)
    context.rectangle(x, y, width, height)
    context.fill()
    context.set_source_rgb(0.82, 0.85, 0.89)
    context.rectangle(x, y, width, height)
    context.set_line_width(1)
    context.stroke()
    _text(context, x + 20, y + 35, title, 21, True)


def _pie_panel(context, x, y, width, height, title, items, unit):
    _panel(context, x, y, width, height, title)
    total = sum(max(0.0, float(item[2])) for item in items)
    if total <= 0.0:
        _text(context, x + 35, y + 90, "Detailed data unavailable", 17,
              False, (0.55, 0.57, 0.60))
        return
    center_x = x + 205
    center_y = y + height / 2.0 + 18
    radius = min(155.0, (height - 110.0) / 2.0)
    angle = -math.pi / 2.0
    for index, item in enumerate(items):
        value = max(0.0, float(item[2]))
        if value <= 0.0:
            continue
        next_angle = angle + 2.0 * math.pi * value / total
        context.move_to(center_x, center_y)
        context.arc(center_x, center_y, radius, angle, next_angle)
        context.close_path()
        context.set_source_rgb(*PIE_COLORS[index % len(PIE_COLORS)])
        context.fill_preserve()
        context.set_source_rgb(1.0, 1.0, 1.0)
        context.set_line_width(2)
        context.stroke()
        angle = next_angle
    legend_x = x + 405
    legend_y = y + 78
    line_height = min(55.0, (height - 100.0) / max(1, len(items)))
    for index, item in enumerate(items):
        unused_key, label, value = item
        row_y = legend_y + index * line_height
        context.set_source_rgb(*PIE_COLORS[index % len(PIE_COLORS)])
        context.rectangle(legend_x, row_y, 22, 18)
        context.fill()
        _text(context, legend_x + 32, row_y + 15, label, 14, True)
        if unit == "cycles":
            detail = "%d cycles | %.2f%%" % (int(value), 100.0 * value / total)
        else:
            detail = "%.5g %s | %.2f%%" % (value, unit, 100.0 * value / total)
        _text(context, legend_x + 32, row_y + 34, detail, 13, False,
              (0.42, 0.45, 0.50))


def _bar_panel(context, rows, x, y, width, height, title, key, unit,
               scale=1.0, delta_key=None):
    _panel(context, x, y, width, height, title)
    values = [row.get(key) for row in rows]
    numeric = [float(value) * scale for value in values if value is not None]
    maximum = max(numeric) if numeric else 1.0
    plot_x = x + 155
    plot_width = width - 330
    row_height = (height - 70.0) / max(1, len(rows))
    for index, row in enumerate(rows):
        center = y + 62 + index * row_height + row_height / 2.0
        _text(context, x + 18, center + 6, row.get("label", row["id"]), 15)
        value = row.get(key)
        if value is None:
            _text(context, plot_x, center + 6, "N/A", 15, False, (0.55, 0.57, 0.60))
            continue
        plotted = float(value) * scale
        bar_width = plot_width * plotted / maximum
        context.set_source_rgb(*COLORS[index % len(COLORS)])
        context.rectangle(plot_x, center - 12, bar_width, 24)
        context.fill()
        label = "%s %s" % (display(plotted, 5), unit)
        if delta_key and row.get("id") != BASELINE["id"] and row.get(delta_key) is not None:
            label += " (%+.1f%%)" % float(row[delta_key])
        _text(context, plot_x + bar_width + 8, center + 6, label, 14)


def render_summary_png(path, rows, state):
    cairo = _load_cairo()
    width, height = 1600, 1040
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    context = cairo.Context(surface)
    context.set_source_rgb(1.0, 1.0, 1.0)
    context.paint()
    _text(context, 55, 58, "FFT16 Software Optimization Summary", 32, True)
    subtitle = "3 ns clock | generated %s" % state.get("updated_at", utc_now())
    if state.get("error"):
        subtitle += " | INCOMPLETE"
    _text(context, 55, 88, subtitle, 16, False, (0.42, 0.45, 0.50))
    _bar_panel(context, rows, 45, 120, 740, 405, "System performance",
               "system_performance_points_per_second", "M point/s", 1.0e-6,
               delta_key="performance_change_percent")
    _bar_panel(context, rows, 815, 120, 740, 405, "SoC total power", "soc_total_power_mw", "mW",
               delta_key="power_change_percent")
    _bar_panel(context, rows, 45, 555, 740, 405, "VCD window energy", "soc_window_energy_nj", "nJ",
               delta_key="window_energy_change_percent")
    _bar_panel(context, rows, 815, 555, 740, 405, "Compute efficiency",
               "compute_efficiency_points_per_joule", "M point/J", 1.0e-6,
               delta_key="efficiency_change_percent")
    _text(context, 55, 995, "Missing bars indicate stages not run or failed; no estimated values are plotted.", 15, False, (0.42, 0.45, 0.50))
    _text(context, 55, 1020, "Ideal overlap of the two 4-cycle FFT8 calls alone: 506 -> 502 cycles (-0.79%, 1.008x).", 15, False, (0.42, 0.45, 0.50))
    surface.write_to_png(path)


def render_breakdown_png(path, rows, state):
    cairo = _load_cairo()
    row_height = 105
    width = 1600
    height = max(760, 230 + len(rows) * row_height)
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    context = cairo.Context(surface)
    context.set_source_rgb(1.0, 1.0, 1.0)
    context.paint()
    _text(context, 55, 58, "FFT16 Cycle Breakdown", 32, True)
    _text(context, 55, 88, "ASM baseline: merge/writeback 351/506 cycles (69.4%); FFT8 waits 8/506 cycles (1.6%).", 16, False, (0.42, 0.45, 0.50))
    phase_keys = (
        ("pre_fft1_cycles", "Setup/input 1", (0.25, 0.36, 0.55)),
        ("fft1_wait_cycles", "FFT8 wait 1", (0.42, 0.65, 0.82)),
        ("between_fft_cycles", "E transfer/input 2", (0.22, 0.68, 0.45)),
        ("fft2_wait_cycles", "FFT8 wait 2", (0.94, 0.72, 0.25)),
        ("post_fft2_cycles", "Post FFT2/merge", (0.93, 0.49, 0.18)),
    )
    maximum = max([float(row.get("cycles") or 0) for row in rows] or [1.0])
    plot_x, plot_width = 245, 1270
    for index, row in enumerate(rows):
        center = 150 + index * row_height
        _text(context, 55, center + 8, row.get("label", row["id"]), 17)
        cursor = plot_x
        if not all(row.get(key) is not None for key, unused, unused_color in phase_keys):
            _text(context, cursor, center + 8, "N/A", 16, False, (0.55, 0.57, 0.60))
            continue
        for key, unused, color in phase_keys:
            segment = max(0.0, float(row[key]))
            segment_width = plot_width * segment / maximum
            context.set_source_rgb(*color)
            context.rectangle(cursor, center - 18, segment_width, 36)
            context.fill()
            cursor += segment_width
        _text(context, cursor + 8, center + 8, "%s cycles" % row["cycles"], 15)
    legend_x, legend_y = 70, height - 90
    for index, (unused, label, color) in enumerate(phase_keys):
        x = legend_x + index * 290
        context.set_source_rgb(*color)
        context.rectangle(x, legend_y, 24, 18)
        context.fill()
        _text(context, x + 32, legend_y + 16, label, 14)
    surface.write_to_png(path)


def render_optimal_cycle_pies(path, state):
    cairo = _load_cairo()
    width, height = 1600, 840
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    context = cairo.Context(surface)
    context.set_source_rgb(1.0, 1.0, 1.0)
    context.paint()
    _text(context, 55, 58, "Optimal FFT16 Cycle Composition", 32, True)
    selected = optimal_row(state)
    subtitle = "%s | 3 ns clock | power-run milestones" % (
        selected.get("label", selected.get("id", "")) if selected else "No selected run"
    )
    _text(context, 55, 88, subtitle, 16, False, (0.42, 0.45, 0.50))
    try:
        phases, twiddle_groups = cycle_breakdowns(selected) if selected else ((), ())
    except BenchmarkError:
        phases, twiddle_groups = (), ()
    _pie_panel(context, 45, 120, 740, 650, "Full execution window",
               phases, "cycles")
    _pie_panel(context, 815, 120, 740, 650, "Post-FFT2 merge by twiddle class",
               twiddle_groups, "cycles")
    _text(context, 55, 812,
          "Slices are milestone deltas and close exactly to the measured window; post-FFT2 groups include O reads and four result stores per k.",
          14, False, (0.42, 0.45, 0.50))
    surface.write_to_png(path)


def render_optimal_energy_pies(path, state):
    cairo = _load_cairo()
    width, height = 1600, 840
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    context = cairo.Context(surface)
    context.set_source_rgb(1.0, 1.0, 1.0)
    context.paint()
    _text(context, 55, 58, "Optimal FFT16 Energy Sources", 32, True)
    selected = optimal_row(state)
    if selected and selected.get("soc_window_energy_nj") is not None:
        subtitle = "%s | full VCD window: %.6g nJ" % (
            selected.get("label", selected.get("id", "")),
            float(selected["soc_window_energy_nj"]),
        )
    else:
        subtitle = "No selected power-complete run"
    _text(context, 55, 88, subtitle, 16, False, (0.42, 0.45, 0.50))
    try:
        hierarchy, energy_types = energy_breakdowns(selected) if selected else ((), ())
        hierarchy_items = tuple((key, label, energy) for key, label, unused, energy in hierarchy)
        type_items = tuple((key, label, energy) for key, label, unused, energy in energy_types)
    except BenchmarkError:
        hierarchy_items, type_items = (), ()
    _pie_panel(context, 45, 120, 740, 650, "Energy by hardware hierarchy",
               hierarchy_items, "nJ")
    _pie_panel(context, 815, 120, 740, 650, "Energy by power mechanism",
               type_items, "nJ")
    _text(context, 55, 812,
          "Mechanism energies are normalized to PT total energy to absorb report rounding; Other is the top-level hierarchy residual.",
          14, False, (0.42, 0.45, 0.50))
    surface.write_to_png(path)


def report_rows(state):
    rows = [derived_metrics(BASELINE)]
    for report_id in state.get("report_order", []):
        if report_id in state.get("runs", {}):
            rows.append(derived_metrics(state["runs"][report_id]))
    return rows


def write_reports(repo_root, state):
    report_dir = os.path.join(repo_root, "report")
    ensure_dir(report_dir)
    rows = report_rows(state)
    csv_path = os.path.join(report_dir, "fft16_sw_optimization.csv")
    md_path = os.path.join(report_dir, "fft16_sw_optimization.md")
    summary_png = os.path.join(report_dir, "fft16_sw_summary.png")
    breakdown_png = os.path.join(report_dir, "fft16_sw_cycle_breakdown.png")
    detail_csv = os.path.join(report_dir, "fft16_sw_optimal_breakdown.csv")
    cycle_pies_png = os.path.join(report_dir, "fft16_sw_optimal_cycle_pies.png")
    energy_pies_png = os.path.join(report_dir, "fft16_sw_optimal_energy_pies.png")
    write_csv_report(csv_path, rows)
    atomic_write_text(md_path, markdown_report(rows, state))
    render_summary_png(summary_png, rows, state)
    render_breakdown_png(breakdown_png, rows, state)
    write_breakdown_csv(detail_csv, state)
    render_optimal_cycle_pies(cycle_pies_png, state)
    render_optimal_energy_pies(energy_pies_png, state)
    return (
        csv_path, md_path, summary_png, breakdown_png, detail_csv,
        cycle_pies_png, energy_pies_png,
    )


class Runner(object):
    def __init__(self, repo_root, arguments):
        self.repo_root = repo_root
        self.arguments = arguments
        self.run_root = os.path.join(repo_root, "benchmark_runs", "fft16_sw")
        self.state_path = os.path.join(self.run_root, "state.json")
        self.log_dir = os.path.join(self.run_root, "logs")
        self.program_dir = os.path.join(self.run_root, "programs")
        self.source_hash = fingerprint(
            [
                os.path.join(repo_root, "sim_16", "sw"),
                os.path.join(repo_root, "sim_16", "Makefile"),
                os.path.join(repo_root, "sim_16", "check_sw_image.sh"),
                os.path.join(repo_root, "sim_16", "fft16_benchmark.py"),
                os.path.join(repo_root, "sim_16", "tb", "tb_soc.sv"),
                os.path.join(repo_root, "postsim"),
                os.path.join(repo_root, "pt"),
                os.path.join(repo_root, "hw"),
            ],
            "fft16-benchmark-schema-%d" % SCHEMA_VERSION,
        )
        physical_hash = self.physical_fingerprint()
        saved = read_json(self.state_path) if os.path.isfile(self.state_path) else None
        if self.arguments.render_only and saved is None:
            raise BenchmarkError(
                "no saved FFT16 benchmark state; run the full benchmark first"
            )
        if (self.arguments.render_only and saved is not None and
                saved.get("schema_version") != SCHEMA_VERSION):
            raise BenchmarkError(
                "saved FFT16 benchmark schema %s lacks detailed phase data; "
                "run the full benchmark once before --render-only" %
                saved.get("schema_version", "unknown")
            )
        if self.arguments.render_only:
            # Report formulas and rendering code may change without changing
            # any simulation result.  Render the recorded run rather than
            # discarding it merely because this file's fingerprint changed.
            self.state = saved
        elif (saved is not None and
                saved.get("schema_version") == SCHEMA_VERSION and
                saved.get("source_fingerprint") == self.source_hash and
                saved.get("physical_fingerprint") == physical_hash):
            self.state = saved
        else:
            self.state = self.new_state(physical_hash)

    def new_state(self, physical_hash):
        return {
            "schema_version": SCHEMA_VERSION,
            "created_at": utc_now(),
            "updated_at": utc_now(),
            "source_fingerprint": self.source_hash,
            "physical_fingerprint": physical_hash,
            "stages": {},
            "runs": {},
            "report_order": [],
            "selected": {},
            "error": "",
        }

    def physical_fingerprint(self):
        return fingerprint(
            [
                os.path.join(self.repo_root, "icc", "results", "soc_ahblite.output.v"),
                os.path.join(self.repo_root, "icc", "results", "soc_ahblite.output.spef.max"),
                os.path.join(self.repo_root, "icc", "results", "soc_ahblite.output.spef.min"),
                os.path.join(self.repo_root, "pt", "runs", "wc_max", "my_wc_max.sdf"),
                os.path.join(self.repo_root, "pt", "runs", "bc_min", "my_bc_min.sdf"),
            ],
            "430.72x560-3ns",
        )

    def save(self):
        self.state["updated_at"] = utc_now()
        ensure_dir(self.run_root)
        atomic_write_json(self.state_path, self.state)

    def stage_fingerprint(self, name, command, inputs):
        return fingerprint(inputs, name + "\0" + "\0".join(command) + "\0" + self.source_hash)

    def run_stage(self, name, command, cwd, environment, outputs, inputs):
        stage_hash = self.stage_fingerprint(name, command, inputs)
        previous = self.state["stages"].get(name, {})
        if (self.arguments.resume and previous.get("status") == "PASS" and
                previous.get("fingerprint") == stage_hash and
                all(os.path.isfile(path) and os.path.getsize(path) > 0 for path in outputs)):
            print("[resume] %s" % name)
            return
        log_path = os.path.join(self.log_dir, name.replace("/", "__") + ".log")
        if self.arguments.dry_run:
            print("[dry-run] %s: %s" % (name, " ".join(command)))
            return
        ensure_dir(os.path.dirname(log_path))
        self.state["stages"][name] = {
            "status": "RUNNING", "started_at": utc_now(),
            "fingerprint": stage_hash, "log": log_path,
        }
        self.save()
        print("[run] %s" % name)
        child_env = os.environ.copy()
        child_env.update(environment)
        # Synopsys batch jobs should wait for a floating license instead of
        # turning transient license contention into a cached failed stage.
        child_env.setdefault("SNPSLMD_QUEUE", "true")
        with open(log_path, "wb") as log_handle:
            process = subprocess.Popen(
                command, cwd=cwd, env=child_env,
                stdout=log_handle, stderr=subprocess.STDOUT,
            )
            return_code = process.wait()
        stage = self.state["stages"][name]
        stage["finished_at"] = utc_now()
        if return_code != 0:
            stage["status"] = "FAIL"
            stage["return_code"] = return_code
            self.save()
            raise BenchmarkError("stage %s failed; see %s" % (name, log_path))
        missing = [path for path in outputs if not os.path.isfile(path) or os.path.getsize(path) == 0]
        if missing:
            stage["status"] = "FAIL"
            stage["missing_outputs"] = missing
            self.save()
            raise BenchmarkError("stage %s did not create %s" % (name, ", ".join(missing)))
        stage["status"] = "PASS"
        self.save()

    def fail_stage_validation(self, name, error):
        """Make semantic validation failures resumable instead of caching them."""
        stage = self.state["stages"].setdefault(name, {})
        stage["status"] = "FAIL"
        stage["validation_error"] = str(error)
        stage["finished_at"] = utc_now()
        self.save()

    def preflight(self, need_eda, need_cairo):
        required_programs = ["make", "bash", "srec_cat"]
        toolchain_bin = os.environ.get(
            "RISCV_TOOLCHAIN_BIN",
            "/home/master/toolchain/lowrisc-toolchain-gcc-rv32imc-20220210-1/bin",
        )
        for tool in ("gcc", "objcopy", "objdump", "readelf"):
            required_programs.append(
                os.path.join(toolchain_bin, "riscv32-unknown-elf-%s" % tool)
            )
        if need_eda:
            required_programs.extend((
                os.environ.get("VCS_BIN", "vcs"),
                os.environ.get(
                    "PT_SHELL_BIN",
                    "/export/SoftWare/Synopsys/pts/O-2018.06-SP1/bin/pt_shell",
                ),
            ))
        missing = [value for value in required_programs if find_executable(value) is None]
        if missing:
            raise BenchmarkError("missing executable(s): %s" % ", ".join(missing))
        if need_cairo:
            _load_cairo()
        if need_eda:
            netlist = os.environ.get(
                "NETLIST",
                os.path.join(self.repo_root, "icc", "results", "soc_ahblite.output.v"),
            )
            wc_sdf = os.environ.get(
                "WC_SDF", os.path.join(self.repo_root, "pt", "runs", "wc_max", "my_wc_max.sdf")
            )
            bc_sdf = os.environ.get(
                "BC_SDF", os.path.join(self.repo_root, "pt", "runs", "bc_min", "my_bc_min.sdf")
            )
            required_files = (
                netlist, wc_sdf, bc_sdf,
                os.path.join(self.repo_root, "icc", "results", "soc_ahblite.output.spef.max"),
            )
            absent = [path for path in required_files if not os.path.isfile(path)]
            if absent:
                raise BenchmarkError("missing physical artifact(s): %s" % ", ".join(absent))
        gcc_project = os.environ.get("GCC_PROJECT", "/home/master/project/IC_class/gcc")
        software_files = (
            os.path.join(self.repo_root, "sim_16", "sw", "link.ld"),
            os.path.join(gcc_project, "Makefile"),
            os.path.join(gcc_project, "crt0.S"),
        )
        absent = [path for path in software_files if not os.path.isfile(path)]
        if absent:
            raise BenchmarkError("missing software build dependency: %s" % ", ".join(absent))

    def build_program(self, variant, opt_level):
        run_id = "%s_%s" % (variant, opt_level)
        build_dir = os.path.join(self.run_root, "build", run_id)
        vmem = os.path.join(self.program_dir, run_id, "gcc.vmem")
        sha_file = os.path.join(build_dir, "sw", "gcc.sha256")
        command = [
            "make", "-C", os.path.join(self.repo_root, "sim_16"), "sw",
            "SW_VARIANT=%s" % variant, "OPT_LEVEL=%s" % opt_level,
            "BUILD_DIR=%s" % build_dir, "VMEM=%s" % vmem,
        ]
        gcc_project = os.environ.get("GCC_PROJECT", "/home/master/project/IC_class/gcc")
        self.run_stage(
            "build/%s" % run_id, command, self.repo_root, {},
            [vmem, sha_file, os.path.join(build_dir, "sw", "gcc.dis")],
            [
                os.path.join(self.repo_root, "sim_16", "sw", "fft16_%s.c" % variant),
                os.path.join(self.repo_root, "sim_16", "sw", "fft16_common.h"),
                os.path.join(self.repo_root, "sim_16", "sw", "link.ld"),
                os.path.join(self.repo_root, "sim_16", "Makefile"),
                os.path.join(gcc_project, "Makefile"),
                os.path.join(gcc_project, "crt0.S"),
            ],
        )
        if self.arguments.dry_run:
            return {"id": run_id, "variant": variant, "opt_level": opt_level, "vmem": vmem}
        row = self.state["runs"].setdefault(run_id, {})
        row.update({
            "id": run_id,
            "label": "%s -%s" % ("C ref" if variant == "reference" else "C opt", opt_level),
            "variant": variant,
            "opt_level": opt_level,
            "status": "BUILT",
            "vmem": vmem,
            "image_bytes": image_size_from_sha(sha_file),
            "artifact_sha256": sha256_file(vmem),
            "compiler_flags": "-march=rv32imc -mabi=ilp32 -%s" % opt_level,
            "source": "sim_16/sw/fft16_%s.c" % variant,
        })
        self.save()
        return row

    def compile_rtl(self):
        build_dir = os.path.join(self.run_root, "rtl")
        simv = os.path.join(build_dir, "simv")
        vcs_bin = os.environ.get("VCS_BIN", os.environ.get("VCS", "vcs"))
        command = [
            "make", "-C", os.path.join(self.repo_root, "sim_16"), "compile",
            "BUILD_DIR=%s" % build_dir, "VCS=%s" % vcs_bin,
        ]
        self.run_stage(
            "rtl/compile", command, self.repo_root, {}, [simv],
            [os.path.join(self.repo_root, "sim_16", "rtl.f"),
             os.path.join(self.repo_root, "sim_16", "tb", "tb_soc.sv"),
             os.path.join(self.repo_root, "hw")],
        )
        return simv

    def run_rtl(self, row, simv):
        stage_name = "rtl/run/%s" % row["id"]
        log_path = os.path.join(self.run_root, "rtl", "%s.run.log" % row["id"])
        command = [
            simv, "+vcs+lic+wait", "+VMEM=%s" % row["vmem"],
            "+TIMEOUT_CYCLES=20000", "-l", log_path,
        ]
        self.run_stage(
            stage_name, command,
            os.path.join(self.run_root, "rtl"), {}, [log_path], [simv, row["vmem"]],
        )
        if not self.arguments.dry_run:
            try:
                metrics = parse_simulation_log(log_path)
            except BenchmarkError as error:
                self.fail_stage_validation(stage_name, error)
                raise
            row.update(metrics)
            row["rtl_log"] = log_path
            row["status"] = "RTL_PASS"
            self.save()

    def run_gate_mode(self, row, mode):
        stage_name = "gate/%s/%s" % (row["id"], mode)
        build_root = os.path.join(self.run_root, "postsim", row["id"])
        run_log = os.path.join(build_root, mode, "run.log")
        environment = {
            "POSTSIM_BUILD_DIR": build_root,
            "VMEM": row["vmem"],
            "CLOCK_PERIOD_NS": "3.0",
        }
        command = ["make", "-C", os.path.join(self.repo_root, "postsim"), mode]
        outputs = [run_log]
        if mode == "power":
            outputs.extend((
                os.path.join(build_root, "power", "tb_soc.vcd"),
                os.path.join(build_root, "power", "power_window.rpt"),
            ))
            make_target = "power_vcd"
            command[-1] = make_target
        stage_inputs = [
            row["vmem"], os.path.join(self.repo_root, "postsim", "tb", "tb_soc.sv"),
            os.environ.get(
                "NETLIST",
                os.path.join(self.repo_root, "icc", "results", "soc_ahblite.output.v"),
            ),
        ]
        if mode == "max":
            stage_inputs.append(os.environ.get(
                "WC_SDF", os.path.join(self.repo_root, "pt", "runs", "wc_max", "my_wc_max.sdf")
            ))
        elif mode in ("min", "power"):
            stage_inputs.append(os.environ.get(
                "BC_SDF", os.path.join(self.repo_root, "pt", "runs", "bc_min", "my_bc_min.sdf")
            ))
        self.run_stage(
            stage_name, command, self.repo_root,
            environment, outputs, stage_inputs,
        )
        if not self.arguments.dry_run:
            try:
                gate_metrics = parse_simulation_log(run_log)
                if row.get("cycles") is not None and gate_metrics["cycles"] != row["cycles"]:
                    raise BenchmarkError(
                        "%s cycle mismatch: RTL=%s gate-%s=%s" %
                        (row["id"], row["cycles"], mode, gate_metrics["cycles"])
                    )
            except BenchmarkError as error:
                self.fail_stage_validation(stage_name, error)
                raise
            if mode == "func":
                row["gate_func_log"] = run_log
            elif mode == "power":
                row["gate_power_log"] = run_log
                # Detailed plots use milestones from the exact gate run that
                # generated the VCD, not the logically equivalent RTL run.
                row["power_metrics"] = gate_metrics
            self.save()

    def run_power(self, row):
        stage_name = "pt/power/%s" % row["id"]
        post_root = os.path.join(self.run_root, "postsim", row["id"])
        pt_root = os.path.join(self.run_root, "pt", row["id"])
        summary = os.path.join(pt_root, "power", "power_summary.rpt")
        power_vcd = os.path.join(post_root, "power", "tb_soc.vcd")
        power_window = os.path.join(post_root, "power", "power_window.rpt")
        environment = {
            "PT_RUNS_DIR": pt_root,
            "POWER_VCD": power_vcd,
            "POWER_WINDOW_FILE": power_window,
        }
        command = ["make", "-C", os.path.join(self.repo_root, "pt"), "power"]
        self.run_stage(
            stage_name, command, self.repo_root,
            environment, [summary],
            [power_vcd, power_window,
             os.path.join(self.repo_root, "icc", "results", "soc_ahblite.output.spef.max")],
        )
        if not self.arguments.dry_run:
            try:
                power = parse_power_summary(summary)
                if power["power_window_cycles"] != row["cycles"]:
                    raise BenchmarkError(
                        "%s cycle mismatch: simulation=%s PT=%s" %
                        (row["id"], row["cycles"], power["power_window_cycles"])
                    )
            except BenchmarkError as error:
                self.fail_stage_validation(stage_name, error)
                raise
            row.update(power)
            row["power_summary"] = summary
            row["status"] = "POWER_PASS"
            self.save()

    def full_run(self):
        self.preflight(need_eda=True, need_cairo=True)
        rows = []
        rows.append(self.build_program("reference", "O0"))
        for variant in ("reference", "optimized"):
            for opt_level in OPTIMIZATION_LEVELS:
                rows.append(self.build_program(variant, opt_level))
        simv = self.compile_rtl()
        for row in rows:
            self.run_rtl(row, simv)
        if self.arguments.dry_run:
            print("[dry-run] best compiler options are selected after RTL metrics")
            print("[dry-run] selected C stages then run gate func/power/PT; final C also runs max/min")
            return

        reference_candidates = [row for row in rows if row["variant"] == "reference" and row["opt_level"] != "O0"]
        optimized_candidates = [row for row in rows if row["variant"] == "optimized"]
        best_reference = choose_best(reference_candidates)
        best_optimized = choose_best(optimized_candidates)
        reference_o0 = [row for row in rows if row["variant"] == "reference" and row["opt_level"] == "O0"][0]
        selected = (reference_o0, best_reference, best_optimized)
        self.state["selected"] = {
            "reference": best_reference["id"], "optimized": best_optimized["id"]
        }
        self.state["report_order"] = [row["id"] for row in selected]
        self.save()

        for row in selected:
            self.run_gate_mode(row, "func")
            self.run_gate_mode(row, "power")
            self.run_power(row)
        self.run_gate_mode(best_optimized, "max")
        self.run_gate_mode(best_optimized, "min")
        best_optimized["status"] = "PASS"
        reference_o0["status"] = "PASS"
        best_reference["status"] = "PASS"
        self.state["error"] = ""
        self.save()
        write_reports(self.repo_root, self.state)

    def build_only(self):
        self.preflight(need_eda=False, need_cairo=True)
        rows = []
        for variant, levels in (
                ("reference", ("O0",) + OPTIMIZATION_LEVELS),
                ("optimized", OPTIMIZATION_LEVELS)):
            for opt_level in levels:
                rows.append(self.build_program(variant, opt_level))
        if not self.arguments.dry_run:
            self.state["error"] = "Build-only run: simulations and power analysis were not executed."
            self.state["report_order"] = [row["id"] for row in rows]
            self.save()
            paths = write_reports(self.repo_root, self.state)
            print("Build-only checks passed. No simulation or power result was generated.")
            print("Partial reports generated:\n  %s" % "\n  ".join(paths))


def parse_arguments(argv):
    parser = argparse.ArgumentParser(
        description="Build, simulate, power-analyze, and plot FFT16 C optimizations"
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--build-only", action="store_true", help="compile and statically check all C images without EDA tools")
    mode.add_argument("--render-only", action="store_true", help="regenerate reports and PNGs from saved state")
    parser.add_argument("--resume", action="store_true", help="reuse successful stages whose input fingerprints still match")
    parser.add_argument("--dry-run", action="store_true", help="print the planned commands without executing them")
    return parser.parse_args(argv)


def main(argv=None):
    arguments = parse_arguments(argv if argv is not None else sys.argv[1:])
    repo_root = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
    try:
        lock_path = os.path.join(repo_root, "benchmark_runs", "fft16_sw", ".lock")
        lock_context = RunLock(lock_path) if not arguments.dry_run else _NullContext()
        with lock_context:
            runner = Runner(repo_root, arguments)
            if arguments.render_only:
                runner.preflight(need_eda=False, need_cairo=True)
                paths = write_reports(repo_root, runner.state)
                print("Reports regenerated:\n  %s" % "\n  ".join(paths))
            elif arguments.build_only:
                runner.build_only()
            else:
                runner.full_run()
    except KeyboardInterrupt:
        print("Benchmark interrupted; rerun with --resume.", file=sys.stderr)
        return 130
    except BenchmarkError as error:
        if "runner" in locals() and not arguments.dry_run:
            runner.state["error"] = str(error)
            runner.save()
            try:
                write_reports(repo_root, runner.state)
            except Exception as report_error:
                print("Could not render partial report: %s" % report_error, file=sys.stderr)
        print("Benchmark failed: %s" % error, file=sys.stderr)
        print("Fix the reported issue, then rerun with --resume.", file=sys.stderr)
        return 1
    return 0


class _NullContext(object):
    def __enter__(self):
        return self

    def __exit__(self, unused_type, unused_value, unused_traceback):
        return False


if __name__ == "__main__":
    sys.exit(main())
