#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import print_function

"""Restartable frequency/core-area PPA sweep for the RISC-V FFT SoC.

The host EDA image only guarantees Python 2.7, so this file deliberately uses
the Python 2.7/3.x common subset and the standard library only.
"""

import argparse
import csv
import errno
import fcntl
import hashlib
import io
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time


try:
    text_type = unicode
except NameError:
    text_type = str


SCHEMA_VERSION = 1
EXPECTED_FFT16_CYCLES = 506
DEFAULT_FREQUENCIES_MHZ = (
    250.0,
    275.0,
    300.0,
    325.0,
    1000.0 / 3.0,
    350.0,
    375.0,
    400.0,
)
DEFAULT_CORE_SIZES_UM = (
    (430.72, 520.0),
    (430.72, 540.0),
    (430.72, 560.0),
    (450.72, 580.0),
    (470.72, 600.0),
)
BASELINE = {
    "frequency_mhz": 1000.0 / 3.0,
    "clock_period_ns": 3.0,
    "fft16_cycles": EXPECTED_FFT16_CYCLES,
    "fft16_time_ns": 1518.0,
    "core_area_um2": 240791.52,
    "soc_total_power_mw": 34.3,
}

# The controller is copied into each isolated workspace for provenance, but it
# is not an EDA input.  Keeping it out of the flow fingerprint lets a scanner
# bug fix resume existing DC/ICC/PT artifacts safely.
FLOW_SOURCE_PATHS = ("hw", "dc", "icc", "pt", "postsim", "sim_16")
SOURCE_PATHS = FLOW_SOURCE_PATHS + ("scan_ppa.py",)
DEFAULT_LICENSE_RETRY_DELAY_SECONDS = 60.0
PERMANENT_LICENSE_ERROR_PATTERNS = (
    re.compile(r"no such feature exists", re.IGNORECASE),
    re.compile(r"license server system does not support this feature", re.IGNORECASE),
    re.compile(r"invalid (?:or inconsistent )?license", re.IGNORECASE),
)
TRANSIENT_LICENSE_ERROR_PATTERNS = (
    re.compile(r"re-attempting to check if license server is up", re.IGNORECASE),
    re.compile(r"cannot connect to license server", re.IGNORECASE),
    re.compile(r"unable to connect to license server", re.IGNORECASE),
    re.compile(r"lost connection to license server", re.IGNORECASE),
    re.compile(r"license server .* (?:down|not responding)", re.IGNORECASE),
    re.compile(r"licensed number of users already reached", re.IGNORECASE),
    re.compile(r"all licenses are (?:currently )?in use", re.IGNORECASE),
    re.compile(r"unable to obtain (?:a |an )?.*license", re.IGNORECASE),
)
STAGE_NAMES = (
    "prepare",
    "dc",
    "icc",
    "area",
    "pt_wc_max",
    "pt_tc_min",
    "pt_bc_min",
    "timing",
    "power_vcd",
    "power_pt",
    "collect",
)
PT_CORNERS = ("wc_max", "tc_min", "bc_min")

CSV_FIELDS = (
    "point_id",
    "status",
    "frequency_mhz",
    "clock_period_ns",
    "requested_core_width_um",
    "requested_core_height_um",
    "actual_core_width_um",
    "actual_core_height_um",
    "core_area_um2",
    "design_area_um2",
    "cell_utilization_percent",
    "wc_setup_wns_ns",
    "tc_setup_wns_ns",
    "tc_hold_wns_ns",
    "bc_hold_wns_ns",
    "timing_converged",
    "postsim_pass",
    "fft16_cycles",
    "fft16_time_ns",
    "soc_total_power_mw",
    "soc_window_energy_nj",
    "compute_density_fft_per_s_um2",
    "compute_density_ratio",
    "density_timing_valid",
    "compute_efficiency_fft_per_joule",
    "compute_efficiency_ratio",
    "postsim_error",
    "error",
)


class ScanError(Exception):
    pass


class CommandError(ScanError):
    def __init__(self, command, returncode, log_path):
        self.command = command
        self.returncode = returncode
        self.log_path = log_path
        ScanError.__init__(
            self,
            "command failed with exit code %s; see %s" % (returncode, log_path),
        )


def utc_now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def ensure_dir(path):
    if not os.path.isdir(path):
        os.makedirs(path)


def atomic_write_text(path, text_value):
    ensure_dir(os.path.dirname(path))
    temporary = path + ".tmp.%d" % os.getpid()
    if not isinstance(text_value, text_type):
        text_value = text_value.decode("utf-8", "replace")
    with io.open(temporary, "w", encoding="utf-8") as handle:
        handle.write(text_value)
        handle.flush()
        os.fsync(handle.fileno())
    os.rename(temporary, path)


def atomic_write_json(path, value):
    payload = json.dumps(value, indent=2, sort_keys=True, ensure_ascii=True)
    atomic_write_text(path, payload + "\n")


def read_json(path):
    with io.open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def read_text(path):
    with io.open(path, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read()


def decimal_id(value, digits=6):
    text_value = ("%%.%df" % digits) % float(value)
    text_value = text_value.rstrip("0").rstrip(".")
    return text_value.replace("-", "m").replace(".", "p")


def display_number(value, digits=9):
    if value is None or value == "":
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return ("%%.%dg" % digits) % value
    return str(value)


def point_identifier(frequency_mhz, width_um, height_um):
    return "f%s_w%s_h%s" % (
        decimal_id(frequency_mhz),
        decimal_id(width_um),
        decimal_id(height_um),
    )


def make_config():
    return {
        "frequencies_mhz": list(DEFAULT_FREQUENCIES_MHZ),
        "core_sizes_um": [list(value) for value in DEFAULT_CORE_SIZES_UM],
        "baseline": dict(BASELINE),
        "power_policy": "all_timing_converged_points",
        "area_metric": "icc_final_core_area",
        "fft16_cycles": EXPECTED_FFT16_CYCLES,
    }


def stable_hash(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def git_source_files(repo_root, source_paths=SOURCE_PATHS):
    command = [
        "git",
        "ls-files",
        "-z",
        "--cached",
        "--others",
        "--exclude-standard",
        "--",
    ] + list(source_paths)
    process = subprocess.Popen(command, cwd=repo_root, stdout=subprocess.PIPE)
    output = process.communicate()[0]
    if process.returncode != 0:
        raise ScanError("cannot enumerate source files with git ls-files")
    if not isinstance(output, str):
        output = output.decode(sys.getfilesystemencoding() or "utf-8")
    return sorted(path for path in output.split("\0") if path)


def source_fingerprint(repo_root, source_files):
    digest = hashlib.sha256()
    for relative_path in source_files:
        absolute_path = os.path.join(repo_root, relative_path)
        if not os.path.isfile(absolute_path) and not os.path.islink(absolute_path):
            raise ScanError("source file disappeared: %s" % relative_path)
        digest.update(relative_path.encode("utf-8"))
        digest.update(b"\0")
        if os.path.islink(absolute_path):
            digest.update(os.readlink(absolute_path).encode("utf-8"))
        else:
            with open(absolute_path, "rb") as handle:
                while True:
                    chunk = handle.read(1024 * 1024)
                    if not chunk:
                        break
                    digest.update(chunk)
        digest.update(b"\0")
    return digest.hexdigest()


def read_log_tail(path, maximum_bytes=4 * 1024 * 1024):
    try:
        with open(path, "rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - maximum_bytes), os.SEEK_SET)
            payload = handle.read()
    except (IOError, OSError):
        return u""
    if not isinstance(payload, text_type):
        payload = payload.decode("utf-8", "replace")
    return payload


def is_transient_license_failure(error):
    if not isinstance(error, CommandError):
        return False
    log_tail = read_log_tail(error.log_path)
    if any(pattern.search(log_tail) for pattern in PERMANENT_LICENSE_ERROR_PATTERNS):
        return False
    return any(pattern.search(log_tail) for pattern in TRANSIENT_LICENSE_ERROR_PATTERNS)


def archive_failed_command_log(log_path):
    if not os.path.isfile(log_path):
        return ""
    base, extension = os.path.splitext(log_path)
    attempt = 1
    while True:
        destination = "%s.attempt-%03d%s" % (base, attempt, extension)
        if not os.path.exists(destination):
            shutil.copy2(log_path, destination)
            return destination
        attempt += 1


def build_points(config):
    points = []
    index = 0
    for width_um, height_um in config["core_sizes_um"]:
        for frequency_mhz in config["frequencies_mhz"]:
            period_ns = 1000.0 / float(frequency_mhz)
            point_id = point_identifier(frequency_mhz, width_um, height_um)
            points.append(
                {
                    "index": index,
                    "id": point_id,
                    "frequency_mhz": float(frequency_mhz),
                    "clock_period_ns": period_ns,
                    "requested_core_width_um": float(width_um),
                    "requested_core_height_um": float(height_um),
                    "status": "pending",
                    "stages": dict((name, {"status": "pending"}) for name in STAGE_NAMES),
                    "result": {},
                    "error": "",
                }
            )
            index += 1
    return points


def initial_state(config, source_hash):
    return {
        "schema_version": SCHEMA_VERSION,
        "created_at": utc_now(),
        "updated_at": utc_now(),
        "config": config,
        "config_fingerprint": stable_hash(config),
        "source_fingerprint": source_hash,
        "current_point": None,
        "points": build_points(config),
    }


def safe_rmtree(path, allowed_root):
    path = os.path.realpath(path)
    allowed_root = os.path.realpath(allowed_root)
    if path == allowed_root or not path.startswith(allowed_root + os.sep):
        raise ScanError("refusing to remove path outside scan run: %s" % path)
    if os.path.lexists(path):
        shutil.rmtree(path)


def copy_source_workspace(repo_root, workspace, source_files, run_root):
    if os.path.exists(workspace):
        safe_rmtree(workspace, run_root)
    ensure_dir(workspace)
    for relative_path in source_files:
        source = os.path.join(repo_root, relative_path)
        destination = os.path.join(workspace, relative_path)
        ensure_dir(os.path.dirname(destination))
        if os.path.islink(source):
            os.symlink(os.readlink(source), destination)
        else:
            shutil.copy2(source, destination)


def copy_tree(source, destination):
    if os.path.exists(destination):
        shutil.rmtree(destination)
    shutil.copytree(source, destination, symlinks=True)


def cache_key(frequency_mhz):
    return "f%s" % decimal_id(frequency_mhz)


def cache_metadata_path(cache_dir):
    return os.path.join(cache_dir, "cache.json")


def valid_dc_cache(cache_dir, point, source_hash):
    metadata_file = cache_metadata_path(cache_dir)
    required = (
        os.path.join(cache_dir, "syn_rtl", "soc_ahblite.mapped.ddc"),
        os.path.join(cache_dir, "syn_rtl", "soc_ahblite.mapped.v"),
        os.path.join(cache_dir, "sdc", "soc_ahblite.mapped.sdc"),
        metadata_file,
    )
    if not all(os.path.isfile(path) and os.path.getsize(path) > 0 for path in required):
        return False
    try:
        metadata = read_json(metadata_file)
    except (ValueError, IOError):
        return False
    return (
        metadata.get("source_fingerprint") == source_hash
        and abs(float(metadata.get("clock_period_ns", -1.0)) - point["clock_period_ns"])
        < 1.0e-9
    )


def restore_dc_cache(cache_dir, workspace):
    for directory in ("syn_rtl", "sdc", "report"):
        source = os.path.join(cache_dir, directory)
        if os.path.isdir(source):
            copy_tree(source, os.path.join(workspace, directory))


def create_dc_cache(cache_dir, workspace, point, source_hash, run_root):
    temporary = cache_dir + ".tmp.%d" % os.getpid()
    if os.path.exists(temporary):
        safe_rmtree(temporary, run_root)
    ensure_dir(temporary)
    for directory in ("syn_rtl", "sdc", "report"):
        source = os.path.join(workspace, directory)
        if os.path.isdir(source):
            copy_tree(source, os.path.join(temporary, directory))
    atomic_write_json(
        cache_metadata_path(temporary),
        {
            "created_at": utc_now(),
            "frequency_mhz": point["frequency_mhz"],
            "clock_period_ns": point["clock_period_ns"],
            "source_fingerprint": source_hash,
        },
    )
    if os.path.exists(cache_dir):
        safe_rmtree(cache_dir, run_root)
    os.rename(temporary, cache_dir)


def file_key_values(path):
    values = {}
    for line_number, line in enumerate(read_text(path).splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        fields = stripped.split(None, 1)
        if len(fields) != 2:
            raise ScanError("malformed key/value line %s:%d" % (path, line_number))
        if fields[0] in values:
            raise ScanError("duplicate key %s in %s" % (fields[0], path))
        values[fields[0]] = fields[1].strip()
    return values


def require_float(values, key, path):
    if key not in values:
        raise ScanError("missing %s in %s" % (key, path))
    try:
        return float(values[key])
    except ValueError:
        raise ScanError("non-numeric %s in %s: %s" % (key, path, values[key]))


def require_int(values, key, path):
    value = require_float(values, key, path)
    integer = int(value)
    if value != integer:
        raise ScanError("non-integer %s in %s: %s" % (key, path, values[key]))
    return integer


def parse_area_reports(workspace):
    summary_path = os.path.join(workspace, "icc", "reports", "metal_fill_icc.sum")
    qor_path = os.path.join(workspace, "icc", "reports", "metal_fill_icc.qor")
    if not os.path.isfile(summary_path) or not os.path.isfile(qor_path):
        raise ScanError("ICC metal-fill area reports are missing")
    summary = read_text(summary_path)
    qor = read_text(qor_path)

    def match_float(pattern, text, label):
        match = re.search(pattern, text, re.MULTILINE)
        if not match:
            raise ScanError("cannot find %s in ICC reports" % label)
        return float(match.group(1))

    core_area = match_float(r"^Core area\s*:\s*([0-9.eE+-]+)\s*$", summary, "core area")
    utilization = match_float(
        r"^Cell Utilization\(non-fixed\)\s*=\s*([0-9.eE+-]+)%",
        summary,
        "cell utilization",
    )
    design_area = match_float(
        r"^\s*Design Area:\s*([0-9.eE+-]+)\s*$", qor, "design area"
    )
    cell_area = match_float(r"^\s*Cell Area:\s*([0-9.eE+-]+)\s*$", qor, "cell area")
    bbox_match = re.search(
        r"^\s*Core area:\s*\((-?[0-9]+)\s+(-?[0-9]+)\s+(-?[0-9]+)\s+(-?[0-9]+)\)",
        qor,
        re.MULTILINE,
    )
    scale_match = re.search(
        r"Physical DB scale:\s*([0-9.eE+-]+)\s+db_unit\s*=\s*1\s+um", summary
    )
    if not scale_match:
        reports_dir = os.path.join(workspace, "icc", "reports")
        for name in os.listdir(reports_dir):
            if not name.endswith(".placement_utilization.rpt"):
                continue
            scale_match = re.search(
                r"Physical DB scale:\s*([0-9.eE+-]+)\s+db_unit\s*=\s*1\s+um",
                read_text(os.path.join(reports_dir, name)),
            )
            if scale_match:
                break
    if not bbox_match or not scale_match:
        raise ScanError("cannot determine actual ICC core dimensions")
    scale = float(scale_match.group(1))
    coordinates = [float(value) / scale for value in bbox_match.groups()]
    actual_width = coordinates[2] - coordinates[0]
    actual_height = coordinates[3] - coordinates[1]
    bbox_area = actual_width * actual_height
    if abs(bbox_area - core_area) > max(1.0, core_area * 1.0e-5):
        raise ScanError(
            "ICC core bbox area %.6f disagrees with reported area %.6f"
            % (bbox_area, core_area)
        )
    return {
        "actual_core_width_um": actual_width,
        "actual_core_height_um": actual_height,
        "core_area_um2": core_area,
        "design_area_um2": design_area,
        "cell_area_um2": cell_area,
        "cell_utilization_percent": utilization,
    }


ERROR_PATTERN = re.compile(r"(^|\s)(Error:|Fatal:)", re.MULTILINE)
DRC_PATTERN = re.compile(
    r"^\s*(max_transition|max_capacitance|max_fanout)\s+", re.MULTILINE
)


def parse_pt_corner(workspace, corner):
    run_dir = os.path.join(workspace, "pt", "runs", corner)
    status_path = os.path.join(run_dir, "timing_status_%s.rpt" % corner)
    constraint_path = os.path.join(run_dir, "constraint_violators_%s.rpt" % corner)
    check_constraint_path = os.path.join(run_dir, "check_constraints_%s.rpt" % corner)
    log_path = os.path.join(run_dir, "pt.log")
    for required in (status_path, constraint_path, check_constraint_path, log_path):
        if not os.path.isfile(required) or os.path.getsize(required) == 0:
            raise ScanError("PrimeTime output is missing or empty: %s" % required)

    for name in os.listdir(run_dir):
        if not (name.endswith(".rpt") or name == "pt.log"):
            continue
        path = os.path.join(run_dir, name)
        if ERROR_PATTERN.search(read_text(path)):
            raise ScanError("PrimeTime Error/Fatal found in %s" % path)

    values = file_key_values(status_path)
    required_checks = values.get("PT_REQUIRED_CHECKS")
    if required_checks not in ("setup", "hold", "both"):
        raise ScanError("invalid PT_REQUIRED_CHECKS in %s" % status_path)
    setup_violations = require_int(values, "PT_SETUP_VIOLATING_PATHS", status_path)
    hold_violations = require_int(values, "PT_HOLD_VIOLATING_PATHS", status_path)
    setup_wns = require_float(values, "PT_SETUP_WNS", status_path)
    hold_wns = require_float(values, "PT_HOLD_WNS", status_path)
    pt_pass = values.get("PT_RESULT") == "PASS"
    drc_violations = DRC_PATTERN.findall(read_text(constraint_path))
    return {
        "required_checks": required_checks,
        "setup_wns_ns": setup_wns,
        "hold_wns_ns": hold_wns,
        "setup_violating_paths": setup_violations,
        "hold_violating_paths": hold_violations,
        "pt_result_pass": pt_pass,
        "drc_violations": sorted(set(drc_violations)),
        "pass": pt_pass and not drc_violations,
    }


def parse_timing(workspace):
    corners = dict((corner, parse_pt_corner(workspace, corner)) for corner in PT_CORNERS)
    return {
        "corners": corners,
        "timing_converged": all(corners[corner]["pass"] for corner in PT_CORNERS),
    }


def parse_power(workspace):
    summary_path = os.path.join(workspace, "pt", "runs", "power", "power_summary.rpt")
    window_path = os.path.join(
        workspace, "postsim", "build", "power", "power_window.rpt"
    )
    if not os.path.isfile(summary_path) or not os.path.isfile(window_path):
        raise ScanError("power summary or power window is missing")
    summary = file_key_values(summary_path)
    window = file_key_values(window_path)
    if summary.get("POWER_RESULT") != "PASS":
        raise ScanError("PT power summary did not report POWER_RESULT PASS")
    cycles = require_int(window, "POWER_CYCLES", window_path)
    summary_cycles = require_int(summary, "POWER_WINDOW_CYCLES", summary_path)
    if cycles != EXPECTED_FFT16_CYCLES or summary_cycles != EXPECTED_FFT16_CYCLES:
        raise ScanError(
            "FFT16 power window must contain %d cycles, got %d/%d"
            % (EXPECTED_FFT16_CYCLES, cycles, summary_cycles)
        )
    power_mw = require_float(summary, "SOC_TOTAL_POWER_MW", summary_path)
    if power_mw <= 0.0:
        raise ScanError("SOC_TOTAL_POWER_MW must be positive")
    return {
        "power_result": "PASS",
        "power_window_start_ns": require_float(summary, "POWER_WINDOW_START_NS", summary_path),
        "power_window_end_ns": require_float(summary, "POWER_WINDOW_END_NS", summary_path),
        "power_window_duration_ns": require_float(
            summary, "POWER_WINDOW_DURATION_NS", summary_path
        ),
        "power_window_cycles": cycles,
        "soc_internal_power_mw": require_float(summary, "SOC_INTERNAL_POWER_MW", summary_path),
        "soc_switching_power_mw": require_float(
            summary, "SOC_SWITCHING_POWER_MW", summary_path
        ),
        "soc_dynamic_power_mw": require_float(summary, "SOC_DYNAMIC_POWER_MW", summary_path),
        "soc_leakage_power_mw": require_float(summary, "SOC_LEAKAGE_POWER_MW", summary_path),
        "soc_total_power_mw": power_mw,
        "soc_window_energy_nj": require_float(summary, "SOC_WINDOW_ENERGY_NJ", summary_path),
        "fft_total_power_mw": require_float(summary, "FFT_TOTAL_POWER_MW", summary_path),
        "fft_soc_power_percent": require_float(summary, "FFT_SOC_POWER_PERCENT", summary_path),
    }


def postsim_validation_failure(workspace):
    """Return a point-level gate-simulation failure, or None for tool errors."""
    run_log = os.path.join(workspace, "postsim", "build", "power", "run.log")
    if not os.path.isfile(run_log) or os.path.getsize(run_log) == 0:
        return None
    log_text = read_text(run_log)
    if "CPU+FFT16 TEST FAIL" in log_text:
        detail = "CPU+FFT16 gate-level self-check failed"
        timeout = re.search(r"ERROR:\s*timeout after\s+([0-9]+)\s+cycles", log_text)
        if timeout:
            detail += " after %s cycles" % timeout.group(1)
        return detail
    if re.search(
        r"timing (check )?violation|\*\*.*(setup|hold).*violat|"
        r"Warning:.*(setup|hold).*violat",
        log_text,
        re.IGNORECASE,
    ):
        return "SDF gate simulation reported timing-check violations"
    return None


def finalize_metrics(point):
    result = point["result"]
    period_ns = point["clock_period_ns"]
    time_ns = EXPECTED_FFT16_CYCLES * period_ns
    result["fft16_cycles"] = EXPECTED_FFT16_CYCLES
    result["fft16_time_ns"] = time_ns
    result["throughput_fft_per_s"] = 1.0e9 / time_ns
    area = result.get("core_area_um2")
    if area:
        density = result["throughput_fft_per_s"] / area
        result["compute_density_fft_per_s_um2"] = density
        result["compute_density_ratio"] = (
            BASELINE["fft16_time_ns"] * BASELINE["core_area_um2"]
        ) / (time_ns * area)
        result["density_timing_valid"] = bool(
            result.get("timing_converged")
            and result.get("postsim_pass") is not False
        )
    power_mw = result.get("soc_total_power_mw")
    if power_mw:
        power_w = power_mw / 1000.0
        result["compute_efficiency_fft_per_joule"] = result["throughput_fft_per_s"] / power_w
        result["compute_efficiency_ratio"] = (
            BASELINE["fft16_time_ns"] * BASELINE["soc_total_power_mw"]
        ) / (time_ns * power_mw)
        result["fft16_computation_energy_nj"] = power_mw * time_ns / 1000.0


def csv_row(point):
    result = point.get("result", {})
    corners = result.get("corners", {})
    wc = corners.get("wc_max", {})
    tc = corners.get("tc_min", {})
    bc = corners.get("bc_min", {})
    return {
        "point_id": point["id"],
        "status": point["status"],
        "frequency_mhz": point["frequency_mhz"],
        "clock_period_ns": point["clock_period_ns"],
        "requested_core_width_um": point["requested_core_width_um"],
        "requested_core_height_um": point["requested_core_height_um"],
        "actual_core_width_um": result.get("actual_core_width_um"),
        "actual_core_height_um": result.get("actual_core_height_um"),
        "core_area_um2": result.get("core_area_um2"),
        "design_area_um2": result.get("design_area_um2"),
        "cell_utilization_percent": result.get("cell_utilization_percent"),
        "wc_setup_wns_ns": wc.get("setup_wns_ns"),
        "tc_setup_wns_ns": tc.get("setup_wns_ns"),
        "tc_hold_wns_ns": tc.get("hold_wns_ns"),
        "bc_hold_wns_ns": bc.get("hold_wns_ns"),
        "timing_converged": result.get("timing_converged"),
        "postsim_pass": result.get("postsim_pass"),
        "fft16_cycles": result.get("fft16_cycles"),
        "fft16_time_ns": result.get("fft16_time_ns"),
        "soc_total_power_mw": result.get("soc_total_power_mw"),
        "soc_window_energy_nj": result.get("soc_window_energy_nj"),
        "compute_density_fft_per_s_um2": result.get(
            "compute_density_fft_per_s_um2"
        ),
        "compute_density_ratio": result.get("compute_density_ratio"),
        "density_timing_valid": result.get("density_timing_valid"),
        "compute_efficiency_fft_per_joule": result.get(
            "compute_efficiency_fft_per_joule"
        ),
        "compute_efficiency_ratio": result.get("compute_efficiency_ratio"),
        "postsim_error": result.get("postsim_error", ""),
        "error": point.get("error", ""),
    }


def write_csv(path, points):
    temporary = path + ".tmp.%d" % os.getpid()
    ensure_dir(os.path.dirname(path))
    if sys.version_info[0] < 3:
        handle = open(temporary, "wb")
    else:
        handle = open(temporary, "w", newline="")
    try:
        writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS)
        writer.writeheader()
        for point in points:
            row = csv_row(point)
            writer.writerow(dict((key, display_number(row.get(key))) for key in CSV_FIELDS))
    finally:
        handle.close()
    os.rename(temporary, path)


def markdown_summary(state):
    lines = [
        u"# RISC-V FFT PPA 扫描结果",
        u"",
        u"更新时间：%s" % state["updated_at"],
        u"",
        u"固定基线：3 ns，506 周期，240791.52 µm²，34.3 mW。",
        u"",
        u"| 点 | MHz | 请求核心 (µm) | 实际核心面积 (µm²) | Design Area | 利用率 | WC setup WNS | TC setup/hold WNS | BC hold WNS | 收敛 | 功耗 (mW) | 密度比 | 能效比 |",
        u"|---|---:|---:|---:|---:|---:|---:|---:|---:|:---:|---:|---:|---:|",
    ]
    powered = []
    for point in state["points"]:
        row = csv_row(point)
        converged = row["timing_converged"]
        if converged is True:
            timing_text = u"是"
        elif converged is False:
            timing_text = u"否"
        else:
            timing_text = u"—"
        tc_pair = u"%s / %s" % (
            display_number(row["tc_setup_wns_ns"], 6) or u"—",
            display_number(row["tc_hold_wns_ns"], 6) or u"—",
        )
        lines.append(
            u"| %s | %s | %s×%s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |"
            % (
                point["id"],
                display_number(row["frequency_mhz"], 9),
                display_number(row["requested_core_width_um"]),
                display_number(row["requested_core_height_um"]),
                display_number(row["core_area_um2"]) or u"—",
                display_number(row["design_area_um2"]) or u"—",
                display_number(row["cell_utilization_percent"]) or u"—",
                display_number(row["wc_setup_wns_ns"], 6) or u"—",
                tc_pair,
                display_number(row["bc_hold_wns_ns"], 6) or u"—",
                timing_text,
                display_number(row["soc_total_power_mw"]) or u"—",
                display_number(row["compute_density_ratio"], 7) or u"—",
                display_number(row["compute_efficiency_ratio"], 7) or u"—",
            )
        )
        if row["compute_efficiency_ratio"] not in (None, ""):
            powered.append(row)

    lines.extend(
        [
            u"",
            u"## 收敛点能效排名",
            u"",
            u"| 排名 | 点 | 功耗 (mW) | FFT16 时间 (ns) | 密度比 | 能效比 |",
            u"|---:|---|---:|---:|---:|---:|",
        ]
    )
    powered.sort(key=lambda value: value["compute_efficiency_ratio"], reverse=True)
    for rank, row in enumerate(powered, 1):
        lines.append(
            u"| %d | %s | %s | %s | %s | %s |"
            % (
                rank,
                row["point_id"],
                display_number(row["soc_total_power_mw"]),
                display_number(row["fft16_time_ns"]),
                display_number(row["compute_density_ratio"], 7),
                display_number(row["compute_efficiency_ratio"], 7),
            )
        )
    if not powered:
        lines.append(u"| — | 暂无已完成功耗分析的收敛点 | — | — | — | — |")
    lines.append(u"")
    return u"\n".join(lines)


def public_results(state):
    return {
        "schema_version": state["schema_version"],
        "generated_at": state["updated_at"],
        "config": state["config"],
        "baseline": dict(BASELINE),
        "points": [
            {
                "id": point["id"],
                "status": point["status"],
                "frequency_mhz": point["frequency_mhz"],
                "clock_period_ns": point["clock_period_ns"],
                "requested_core_width_um": point["requested_core_width_um"],
                "requested_core_height_um": point["requested_core_height_um"],
                "result": point.get("result", {}),
                "error": point.get("error", ""),
            }
            for point in state["points"]
        ],
    }


def archive_text_reports(workspace, destination, run_root):
    if os.path.exists(destination):
        safe_rmtree(destination, run_root)
    ensure_dir(destination)
    roots = (
        (os.path.join(workspace, "report"), "dc"),
        (os.path.join(workspace, "icc", "reports"), "icc_reports"),
        (os.path.join(workspace, "icc", "logs_zrt"), "icc_logs"),
        (os.path.join(workspace, "pt", "runs"), "pt"),
        (os.path.join(workspace, "postsim", "build", "power"), "postsim_power"),
    )
    allowed_suffixes = (
        ".rpt",
        ".log",
        ".sum",
        ".tim",
        ".con",
        ".txt",
        ".sdc",
        ".clock_tree",
        ".clock_timing",
    )
    for source_root, label in roots:
        if not os.path.isdir(source_root):
            continue
        for current_root, directory_names, file_names in os.walk(source_root):
            directory_names[:] = [name for name in directory_names if not name.endswith(".daidir")]
            for name in file_names:
                if not name.endswith(allowed_suffixes):
                    continue
                source = os.path.join(current_root, name)
                if os.path.getsize(source) > 50 * 1024 * 1024:
                    continue
                relative = os.path.relpath(source, source_root)
                target = os.path.join(destination, label, relative)
                ensure_dir(os.path.dirname(target))
                shutil.copy2(source, target)


class RunLock(object):
    def __init__(self, path):
        self.path = path
        self.acquired = False
        self.descriptor = None

    def __enter__(self):
        ensure_dir(os.path.dirname(self.path))
        payload = {
            "pid": os.getpid(),
            "hostname": socket.gethostname(),
            "created_at": utc_now(),
        }
        descriptor = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o644)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (IOError, OSError) as error:
            os.close(descriptor)
            if error.errno not in (errno.EACCES, errno.EAGAIN):
                raise
            try:
                lock = read_json(self.path)
                owner = "host %s PID %s" % (
                    lock.get("hostname", "unknown"),
                    lock.get("pid", "unknown"),
                )
            except (IOError, ValueError):
                owner = "an unknown process"
            raise ScanError("scan is already running under %s" % owner)
        try:
            os.ftruncate(descriptor, 0)
            os.lseek(descriptor, 0, os.SEEK_SET)
            os.write(descriptor, (json.dumps(payload) + "\n").encode("utf-8"))
            os.fsync(descriptor)
        except Exception:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
            os.close(descriptor)
            raise
        self.descriptor = descriptor
        self.acquired = True
        return self

    def __exit__(self, exception_type, exception, traceback):
        if self.acquired and self.descriptor is not None:
            fcntl.flock(self.descriptor, fcntl.LOCK_UN)
            os.close(self.descriptor)
            self.descriptor = None
            self.acquired = False


def scan_lock_is_held(path):
    if not os.path.isfile(path):
        return False
    descriptor = os.open(path, os.O_RDONLY)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (IOError, OSError) as error:
            if error.errno in (errno.EACCES, errno.EAGAIN):
                return True
            raise
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        return False
    finally:
        os.close(descriptor)


class Scanner(object):
    def __init__(
        self,
        repo_root,
        run_root,
        license_retry_delay_seconds=DEFAULT_LICENSE_RETRY_DELAY_SECONDS,
    ):
        self.repo_root = os.path.realpath(repo_root)
        self.run_root = os.path.realpath(run_root)
        self.workspace = os.path.join(self.run_root, "workspace")
        self.state_path = os.path.join(self.run_root, "state.json")
        self.source_files = git_source_files(self.repo_root)
        flow_prefixes = tuple(path + os.sep for path in FLOW_SOURCE_PATHS)
        self.flow_source_files = [
            path
            for path in self.source_files
            if path in FLOW_SOURCE_PATHS or path.startswith(flow_prefixes)
        ]
        self.source_hash = source_fingerprint(self.repo_root, self.flow_source_files)
        self.license_retry_delay_seconds = float(license_retry_delay_seconds)
        self.config = make_config()
        self.state = None

    def load_or_create(self):
        ensure_dir(self.run_root)
        if os.path.isfile(self.state_path):
            self.state = read_json(self.state_path)
            if self.state.get("schema_version") != SCHEMA_VERSION:
                raise ScanError("unsupported scan state schema")
            if self.state.get("config_fingerprint") != stable_hash(self.config):
                raise ScanError("scan configuration changed; choose a new --run-dir")
            if self.state.get("source_fingerprint") != self.source_hash:
                if not self._migrate_legacy_source_fingerprint():
                    raise ScanError("flow source changed; choose a new --run-dir")
        else:
            self.state = initial_state(self.config, self.source_hash)
            self.save()
        self._recover_missing_workspace()
        self.write_summaries()

    def _migrate_legacy_source_fingerprint(self):
        """Migrate schema-1 states whose hash also included scan_ppa.py.

        The isolated workspace is the old source snapshot. Migration is safe
        only when its legacy hash matches the state and all actual EDA inputs
        still match the repository; a genuine flow edit remains rejected.
        """
        stored_hash = self.state.get("source_fingerprint")
        marker_path = self._workspace_marker()
        if not stored_hash or not os.path.isfile(marker_path):
            return False
        try:
            marker = read_json(marker_path)
            legacy_workspace_hash = source_fingerprint(
                self.workspace, self.source_files
            )
            workspace_flow_hash = source_fingerprint(
                self.workspace, self.flow_source_files
            )
        except (IOError, ValueError, ScanError):
            return False
        if (
            marker.get("source_fingerprint") != stored_hash
            or legacy_workspace_hash != stored_hash
            or workspace_flow_hash != self.source_hash
        ):
            return False

        marker["source_fingerprint"] = self.source_hash
        marker["controller_fingerprint_migrated_at"] = utc_now()
        atomic_write_json(marker_path, marker)

        cache_root = os.path.join(self.run_root, "dc_cache")
        if os.path.isdir(cache_root):
            for name in os.listdir(cache_root):
                metadata_path = cache_metadata_path(os.path.join(cache_root, name))
                if not os.path.isfile(metadata_path):
                    continue
                try:
                    metadata = read_json(metadata_path)
                except (IOError, ValueError):
                    continue
                if metadata.get("source_fingerprint") == stored_hash:
                    metadata["source_fingerprint"] = self.source_hash
                    metadata["controller_fingerprint_migrated_at"] = utc_now()
                    atomic_write_json(metadata_path, metadata)

        self.state.setdefault("source_migrations", []).append(
            {
                "at": utc_now(),
                "from": stored_hash,
                "to": self.source_hash,
                "reason": "scanner controller removed from EDA flow fingerprint",
            }
        )
        self.state["source_fingerprint"] = self.source_hash
        self.save()
        print("Migrated scanner-only source fingerprint; EDA flow inputs are unchanged.")
        return True

    def save(self):
        self.state["updated_at"] = utc_now()
        atomic_write_json(self.state_path, self.state)

    def write_summaries(self):
        if self.state is None:
            return
        atomic_write_json(os.path.join(self.run_root, "results.json"), public_results(self.state))
        write_csv(os.path.join(self.run_root, "summary.csv"), self.state["points"])
        atomic_write_text(
            os.path.join(self.run_root, "summary.md"), markdown_summary(self.state)
        )

    def _point(self, point_id):
        for point in self.state["points"]:
            if point["id"] == point_id:
                return point
        raise ScanError("state references unknown point %s" % point_id)

    def _workspace_marker(self):
        return os.path.join(self.workspace, ".scan_point.json")

    def _workspace_matches(self, point):
        marker = self._workspace_marker()
        if not os.path.isfile(marker):
            return False
        try:
            value = read_json(marker)
        except (IOError, ValueError):
            return False
        return (
            value.get("point_id") == point["id"]
            and value.get("source_fingerprint") == self.source_hash
        )

    def _recover_missing_workspace(self):
        point_id = self.state.get("current_point")
        if not point_id:
            return
        point = self._point(point_id)
        if point["stages"]["prepare"]["status"] == "complete" and not self._workspace_matches(point):
            print("Current workspace is missing or mismatched; restarting this point from prepare.")
            point["stages"] = dict((name, {"status": "pending"}) for name in STAGE_NAMES)
            point["result"] = {}
            point["status"] = "pending"
            point["error"] = ""
            self.save()

    def point_environment(self, point):
        env = os.environ.copy()
        env.update(
            {
                "PROJECT_ROOT": self.workspace,
                "ICC_ROOT": os.path.join(self.workspace, "icc"),
                "PT_ROOT": os.path.join(self.workspace, "pt"),
                "PT_RUNS_DIR": os.path.join(self.workspace, "pt", "runs"),
                "PT_DATA_DIR": os.path.join(self.workspace, "icc", "results"),
                "POSTSIM_ROOT": os.path.join(self.workspace, "postsim"),
                "POSTSIM_BUILD_DIR": os.path.join(self.workspace, "postsim", "build"),
                "NETLIST": os.path.join(
                    self.workspace, "icc", "results", "soc_ahblite.output.v"
                ),
                "WC_SDF": os.path.join(
                    self.workspace, "pt", "runs", "wc_max", "my_wc_max.sdf"
                ),
                "BC_SDF": os.path.join(
                    self.workspace, "pt", "runs", "bc_min", "my_bc_min.sdf"
                ),
                "POWER_VCD": os.path.join(
                    self.workspace, "postsim", "build", "power", "tb_soc.vcd"
                ),
                "POWER_WINDOW_FILE": os.path.join(
                    self.workspace, "postsim", "build", "power", "power_window.rpt"
                ),
                "SETUP_ENV_TCL": os.path.join(self.workspace, "dc", "setup_env.tcl"),
                "SETUP_COMPILE_TCL": os.path.join(
                    self.workspace, "dc", "setup_compile.tcl"
                ),
                "CLOCK_PERIOD_NS": "%.12g" % point["clock_period_ns"],
                "ICC_CORE_WIDTH": "%.12g" % point["requested_core_width_um"],
                "ICC_CORE_HEIGHT": "%.12g" % point["requested_core_height_um"],
            }
        )
        return env

    def stage_log(self, point, stage_name):
        return os.path.join(self.run_root, "logs", point["id"], stage_name + ".log")

    def run_command(self, point, stage_name, command, cwd, env):
        log_path = self.stage_log(point, stage_name)
        ensure_dir(os.path.dirname(log_path))
        print("[%s] %s" % (point["id"], " ".join(command)))
        with io.open(log_path, "w", encoding="utf-8", errors="replace") as log_handle:
            process = subprocess.Popen(
                command,
                cwd=cwd,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
            )
            try:
                while True:
                    line = process.stdout.readline()
                    if not line:
                        if process.poll() is not None:
                            break
                        continue
                    log_line = line
                    if not isinstance(log_line, text_type):
                        log_line = log_line.decode("utf-8", "replace")
                    log_handle.write(log_line)
                    log_handle.flush()
                    sys.stdout.write(line)
                    sys.stdout.flush()
                returncode = process.wait()
            except KeyboardInterrupt:
                if process.poll() is None:
                    process.terminate()
                    process.wait()
                raise
        if returncode != 0:
            raise CommandError(command, returncode, log_path)

    def run_stage(self, point, stage_name, action):
        stage = point["stages"][stage_name]
        if stage["status"] in ("complete", "skipped"):
            return
        license_retry_count = int(stage.get("license_retry_count", 0) or 0)
        if stage["status"] in (
            "failed",
            "interrupted",
            "running",
            "waiting_license",
        ):
            previous_log = self.stage_log(point, stage_name)
            previous_error = CommandError([], -1, previous_log)
            if is_transient_license_failure(previous_error):
                archived_log = archive_failed_command_log(previous_log)
                license_retry_count += 1
                print(
                    "[%s] preserving prior transient license failure as %s"
                    % (point["id"], archived_log or previous_log)
                )
        while True:
            stage.clear()
            stage.update(
                {
                    "status": "running",
                    "started_at": utc_now(),
                    "attempt": license_retry_count + 1,
                    "license_retry_count": license_retry_count,
                }
            )
            point["status"] = "running"
            point["error"] = ""
            self.state["current_point"] = point["id"]
            self.save()
            self.write_summaries()
            try:
                action()
                break
            except KeyboardInterrupt:
                stage["status"] = "interrupted"
                stage["finished_at"] = utc_now()
                point["error"] = "interrupted during %s" % stage_name
                self.save()
                self.write_summaries()
                raise
            except CommandError as error:
                if is_transient_license_failure(error):
                    license_retry_count += 1
                    archived_log = archive_failed_command_log(error.log_path)
                    stage["status"] = "waiting_license"
                    stage["last_failure_at"] = utc_now()
                    stage["last_error"] = str(error)
                    stage["last_log"] = archived_log or error.log_path
                    stage["license_retry_count"] = license_retry_count
                    stage["retry_delay_seconds"] = self.license_retry_delay_seconds
                    stage["next_retry_at"] = time.strftime(
                        "%Y-%m-%dT%H:%M:%SZ",
                        time.gmtime(time.time() + self.license_retry_delay_seconds),
                    )
                    point["error"] = (
                        "waiting for a transient license failure to clear during %s"
                        % stage_name
                    )
                    self.save()
                    self.write_summaries()
                    print(
                        "[%s] transient license failure during %s; retry %d in %.0f s"
                        % (
                            point["id"],
                            stage_name,
                            license_retry_count,
                            self.license_retry_delay_seconds,
                        )
                    )
                    try:
                        time.sleep(self.license_retry_delay_seconds)
                    except KeyboardInterrupt:
                        stage["status"] = "interrupted"
                        stage["finished_at"] = utc_now()
                        point["error"] = "interrupted while waiting for a license"
                        self.save()
                        self.write_summaries()
                        raise
                    continue
                stage["status"] = "failed"
                stage["finished_at"] = utc_now()
                stage["error"] = str(error)
                point["status"] = "failed"
                point["error"] = "%s: %s" % (stage_name, error)
                self.save()
                self.write_summaries()
                raise
            except Exception as error:
                stage["status"] = "failed"
                stage["finished_at"] = utc_now()
                stage["error"] = str(error)
                point["status"] = "failed"
                point["error"] = "%s: %s" % (stage_name, error)
                self.save()
                self.write_summaries()
                raise
        stage["status"] = "complete"
        stage["finished_at"] = utc_now()
        self.save()
        self.write_summaries()

    def mark_stage_skipped(self, point, stage_name, reason):
        stage = point["stages"][stage_name]
        if stage["status"] == "complete":
            return
        stage.clear()
        stage.update({"status": "skipped", "reason": reason, "finished_at": utc_now()})
        self.save()

    def prepare(self, point):
        copy_source_workspace(
            self.repo_root, self.workspace, self.source_files, self.run_root
        )
        atomic_write_json(
            self._workspace_marker(),
            {
                "point_id": point["id"],
                "source_fingerprint": self.source_hash,
                "prepared_at": utc_now(),
            },
        )

    def dc(self, point):
        cache_dir = os.path.join(
            self.run_root, "dc_cache", cache_key(point["frequency_mhz"])
        )
        if valid_dc_cache(cache_dir, point, self.source_hash):
            print("[%s] restoring DC cache %s" % (point["id"], cache_dir))
            restore_dc_cache(cache_dir, self.workspace)
            return
        env = self.point_environment(point)
        self.run_command(
            point,
            "dc",
            ["bash", os.path.join(self.workspace, "dc", "compile.sh")],
            self.workspace,
            env,
        )
        required = (
            os.path.join(self.workspace, "syn_rtl", "soc_ahblite.mapped.ddc"),
            os.path.join(self.workspace, "syn_rtl", "soc_ahblite.mapped.v"),
            os.path.join(self.workspace, "sdc", "soc_ahblite.mapped.sdc"),
        )
        if not all(os.path.isfile(path) and os.path.getsize(path) > 0 for path in required):
            raise ScanError("DC completed without all required handoff files")
        create_dc_cache(
            cache_dir, self.workspace, point, self.source_hash, self.run_root
        )

    def icc(self, point):
        self.run_command(
            point,
            "icc",
            ["make", "-C", os.path.join(self.workspace, "icc"), "outputs_icc"],
            self.workspace,
            self.point_environment(point),
        )
        required = (
            os.path.join(self.workspace, "icc", "results", "soc_ahblite.output.v"),
            os.path.join(self.workspace, "icc", "results", "soc_ahblite.output.sdc"),
            os.path.join(self.workspace, "icc", "results", "soc_ahblite.output.spef.max"),
            os.path.join(self.workspace, "icc", "results", "soc_ahblite.output.spef.min"),
        )
        if not all(os.path.isfile(path) and os.path.getsize(path) > 0 for path in required):
            raise ScanError("ICC completed without all signoff handoff files")

    def area(self, point):
        point["result"].update(parse_area_reports(self.workspace))
        finalize_metrics(point)

    def pt_corner(self, point, corner):
        run_dir = os.path.join(self.workspace, "pt", "runs", corner)
        if os.path.isdir(run_dir):
            safe_rmtree(run_dir, self.run_root)
        self.run_command(
            point,
            "pt_" + corner,
            ["make", "-C", os.path.join(self.workspace, "pt"), corner],
            self.workspace,
            self.point_environment(point),
        )
        # PrimeTime can exit zero after emitting report-level errors.  Validate
        # each session inside its own restartable stage so retrying regenerates
        # that corner instead of repeatedly parsing a corrupt report later.
        parse_pt_corner(self.workspace, corner)

    def timing(self, point):
        point["result"].update(parse_timing(self.workspace))
        finalize_metrics(point)

    def power_vcd(self, point):
        build_dir = os.path.join(self.workspace, "postsim", "build", "power")
        if os.path.isdir(build_dir):
            safe_rmtree(build_dir, self.run_root)
        try:
            self.run_command(
                point,
                "power_vcd",
                ["make", "-C", os.path.join(self.workspace, "postsim"), "power_vcd"],
                self.workspace,
                self.point_environment(point),
            )
        except CommandError:
            validation_error = postsim_validation_failure(self.workspace)
            if validation_error is None:
                # License, compiler, dependency, and other infrastructure
                # errors still stop the scan and remain restartable.
                raise
            point["result"]["postsim_pass"] = False
            point["result"]["postsim_error"] = validation_error
            finalize_metrics(point)
            print(
                "[%s] point rejected by gate simulation: %s; continuing scan"
                % (point["id"], validation_error)
            )
            return
        point["result"]["postsim_pass"] = True
        point["result"].pop("postsim_error", None)
        finalize_metrics(point)

    def power_pt(self, point):
        run_dir = os.path.join(self.workspace, "pt", "runs", "power")
        if os.path.isdir(run_dir):
            safe_rmtree(run_dir, self.run_root)
        self.run_command(
            point,
            "power_pt",
            ["make", "-C", os.path.join(self.workspace, "pt"), "power"],
            self.workspace,
            self.point_environment(point),
        )
        point["result"].update(parse_power(self.workspace))
        finalize_metrics(point)

    def collect(self, point):
        destination = os.path.join(self.run_root, "points", point["id"], "reports")
        archive_text_reports(self.workspace, destination, self.run_root)
        atomic_write_json(
            os.path.join(self.run_root, "points", point["id"], "result.json"),
            {
                "id": point["id"],
                "frequency_mhz": point["frequency_mhz"],
                "clock_period_ns": point["clock_period_ns"],
                "requested_core_width_um": point["requested_core_width_um"],
                "requested_core_height_um": point["requested_core_height_um"],
                "result": point["result"],
            },
        )

    def run_point(self, point):
        print(
            "\n=== %s: %.9g MHz, core %.2f x %.2f um ==="
            % (
                point["id"],
                point["frequency_mhz"],
                point["requested_core_width_um"],
                point["requested_core_height_um"],
            )
        )
        self.run_stage(point, "prepare", lambda: self.prepare(point))
        if not self._workspace_matches(point):
            raise ScanError("prepared workspace does not match current point")
        self.run_stage(point, "dc", lambda: self.dc(point))
        self.run_stage(point, "icc", lambda: self.icc(point))
        self.run_stage(point, "area", lambda: self.area(point))
        for corner in PT_CORNERS:
            self.run_stage(
                point,
                "pt_" + corner,
                lambda selected_corner=corner: self.pt_corner(point, selected_corner),
            )
        self.run_stage(point, "timing", lambda: self.timing(point))
        if point["result"].get("timing_converged"):
            self.run_stage(point, "power_vcd", lambda: self.power_vcd(point))
            if point["result"].get("postsim_pass") is False:
                self.mark_stage_skipped(
                    point,
                    "power_pt",
                    "gate-level post-simulation self-check failed",
                )
            else:
                self.run_stage(point, "power_pt", lambda: self.power_pt(point))
        else:
            self.mark_stage_skipped(point, "power_vcd", "timing did not converge")
            self.mark_stage_skipped(point, "power_pt", "timing did not converge")
        self.run_stage(point, "collect", lambda: self.collect(point))
        point["status"] = "complete"
        point["error"] = ""
        self.state["current_point"] = None
        self.save()
        self.write_summaries()

    def skip_current(self):
        point_id = self.state.get("current_point")
        if not point_id:
            raise ScanError("there is no current failed/interrupted point to skip")
        point = self._point(point_id)
        point["status"] = "skipped"
        point["error"] = "skipped by user after stage failure"
        self.state["current_point"] = None
        self.save()
        self.write_summaries()
        print("Skipped %s" % point_id)

    def run(self):
        for point in self.state["points"]:
            if point["status"] in ("complete", "skipped"):
                continue
            self.run_point(point)
        print("\nPPA scan complete: %s" % self.run_root)


def print_matrix(config):
    points = build_points(config)
    print("Default PPA matrix: %d points" % len(points))
    print("Fixed baseline: %s" % json.dumps(BASELINE, sort_keys=True))
    for point in points:
        print(
            "%02d  %-27s  %10.6f MHz  %10.6f ns  %7.2f x %6.2f um"
            % (
                point["index"] + 1,
                point["id"],
                point["frequency_mhz"],
                point["clock_period_ns"],
                point["requested_core_width_um"],
                point["requested_core_height_um"],
            )
        )


def print_status(state, run_root):
    counts = {}
    for point in state["points"]:
        counts[point["status"]] = counts.get(point["status"], 0) + 1
    print("Run directory: %s" % run_root)
    print("Updated: %s" % state.get("updated_at"))
    lock_held = scan_lock_is_held(os.path.join(run_root, ".lock"))
    print("Scanner process: %s" % ("active" if lock_held else "not running"))
    print("Current point: %s" % (state.get("current_point") or "none"))
    print(
        "Points: %s"
        % ", ".join("%s=%d" % item for item in sorted(counts.items()))
    )
    current = state.get("current_point")
    if current:
        point = next(value for value in state["points"] if value["id"] == current)
        if not lock_held and point["status"] == "running":
            print("  note         saved running checkpoint is interrupted; rerun to resume")
        for stage_name in STAGE_NAMES:
            print("  %-12s %s" % (stage_name, point["stages"][stage_name]["status"]))


def parse_arguments(argv):
    parser = argparse.ArgumentParser(
        description="Restartable frequency/core-area DC/ICC/PT/PX scan"
    )
    parser.add_argument(
        "--run-dir",
        default=os.path.join("scan_runs", "default"),
        help="scan state/output directory (default: scan_runs/default)",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="print the 40-point matrix without writing files"
    )
    parser.add_argument("--status", action="store_true", help="show saved progress and exit")
    parser.add_argument(
        "--skip-current",
        action="store_true",
        help="mark the current failed point skipped, then continue the scan",
    )
    parser.add_argument(
        "--license-retry-delay",
        type=float,
        default=DEFAULT_LICENSE_RETRY_DELAY_SECONDS,
        metavar="SECONDS",
        help="wait before retrying transient EDA license failures (default: 60)",
    )
    return parser.parse_args(argv)


def main(argv=None):
    arguments = parse_arguments(argv if argv is not None else sys.argv[1:])
    if arguments.license_retry_delay < 0:
        print("--license-retry-delay must be non-negative", file=sys.stderr)
        return 2
    repo_root = os.path.dirname(os.path.realpath(__file__))
    if arguments.dry_run:
        print_matrix(make_config())
        return 0
    run_root = arguments.run_dir
    if not os.path.isabs(run_root):
        run_root = os.path.join(repo_root, run_root)
    state_path = os.path.join(run_root, "state.json")
    if arguments.status:
        if not os.path.isfile(state_path):
            print("No scan state exists at %s" % state_path)
            return 1
        print_status(read_json(state_path), run_root)
        return 0

    try:
        with RunLock(os.path.join(run_root, ".lock")):
            scanner = Scanner(
                repo_root,
                run_root,
                license_retry_delay_seconds=arguments.license_retry_delay,
            )
            scanner.load_or_create()
            if arguments.skip_current:
                scanner.skip_current()
            scanner.run()
    except KeyboardInterrupt:
        print("\nScan interrupted; rerun the same command to resume.", file=sys.stderr)
        return 130
    except ScanError as error:
        print("Scan stopped: %s" % error, file=sys.stderr)
        print("Rerun the same command after fixing the tool/environment issue.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
