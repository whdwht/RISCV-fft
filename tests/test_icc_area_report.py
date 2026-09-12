# -*- coding: utf-8 -*-
from __future__ import print_function

import io
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICC_DIR = os.path.join(REPO_ROOT, "icc")
if ICC_DIR not in sys.path:
    sys.path.insert(0, ICC_DIR)

import summarize_area


def write_file(path, contents):
    directory = os.path.dirname(path)
    if not os.path.isdir(directory):
        os.makedirs(directory)
    if not isinstance(contents, summarize_area.text_type):
        contents = contents.decode("utf-8")
    with io.open(path, "w", encoding="utf-8") as handle:
        handle.write(contents)


HIERARCHY_REPORT = u"""ICC_AREA_SOURCE_CEL metal_fill_icc
Combinational area:              35.000000
Buf/Inv area:                    5.000000
Noncombinational area:           25.000000
Macro/Black Box area:            40.000000
Total cell area:                100.000000

Hierarchical area distribution
------------------------------
soc_ahblite                     100.0000 100.0  1.0 1.0 0.0 soc_ahblite
u_fft8_top                       20.0000  20.0  1.0 1.0 0.0 fft
x_data_fabric                     2.0000   2.0  1.0 1.0 0.0 fabric
x_data_sram                      20.0000  20.0  1.0 1.0 0.0 dsram
x_isram_ahbl                     20.0000  20.0  1.0 1.0 0.0 isram
x_rom_ahbl                        5.0000   5.0  1.0 1.0 0.0 rom
x_sub_system                     25.0000  25.0  1.0 1.0 0.0 cpu
x_sub_system/x_core              24.0000  24.0  1.0 1.0 0.0 core
x_sub_system/x_core/gen_regfile_ff_register_file_i 10.0 10.0 6.0 4.0 0.0 regfile
x_sub_system/x_core/ex_block_i 6.0 6.0 1.0 0.0 0.0 execute
x_sub_system/x_core/ex_block_i/alu_i 5.0 5.0 5.0 0.0 0.0 alu
x_sub_system/x_core/cs_registers_i 3.0 3.0 1.0 2.0 0.0 csr
x_sub_system/x_core/if_stage_i 2.0 2.0 1.0 1.0 0.0 fetch
x_sub_system/x_core/id_stage_i 1.0 1.0 1.0 0.0 0.0 decode
x_sub_system/x_core/load_store_unit_i 1.0 1.0 1.0 0.0 0.0 lsu
"""

QOR_REPORT = u"""  Cell Area:            100.000000
  Design Area:          100.000000
"""

PHYSICAL_REPORT = u"""TOTAL LEAF CELLS          120      120.00 unit:250
  NORMAL CELLS            100      100.00 unit:208
  PHYSONLY CELLS           20       20.00 unit:42
Core area           : 150.0
Cell Utilization(non-fixed) = 66.67% (A) / (D - C)
"""


class IccAreaReportTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="icc_area_report_test_")
        self.paths = summarize_area.report_paths(self.root)
        write_file(self.paths["hierarchy"], HIERARCHY_REPORT)
        write_file(self.paths["qor"], QOR_REPORT)
        write_file(self.paths["physical"], PHYSICAL_REPORT)

    def tearDown(self):
        shutil.rmtree(self.root)

    def test_top_level_categories_and_residual_close(self):
        data = summarize_area.collect_area_data(
            self.paths["hierarchy"], self.paths["qor"], self.paths["physical"]
        )
        self.assertEqual(7, len(data["records"]))
        by_key = dict((row["category_key"], row) for row in data["records"])
        self.assertAlmostEqual(25.0, by_key["cpu_subsystem"]["area_um2"])
        self.assertAlmostEqual(20.0, by_key["fft8_accelerator"]["share_percent"])
        self.assertAlmostEqual(8.0, by_key["other_top_level"]["area_um2"])
        self.assertAlmostEqual(
            data["total_cell_area_um2"],
            sum(row["area_um2"] for row in data["records"]),
        )
        self.assertAlmostEqual(
            100.0, sum(row["share_percent"] for row in data["records"])
        )

    def test_rejects_wrong_source_missing_duplicate_and_excess_area(self):
        cases = (
            HIERARCHY_REPORT.replace("metal_fill_icc", "route_opt_icc", 1),
            HIERARCHY_REPORT.replace(
                "x_rom_ahbl                        5.0000   5.0  1.0 1.0 0.0 rom\n",
                "",
            ),
            HIERARCHY_REPORT + "x_data_fabric 2.0000 2.0 1.0 1.0 0.0 duplicate\n",
            HIERARCHY_REPORT.replace(
                "x_sub_system                     25.0000",
                "x_sub_system                     40.0000",
            ),
            HIERARCHY_REPORT.replace(
                "x_rom_ahbl                        5.0000",
                "x_rom_ahbl                       -5.0000",
            ),
        )
        for contents in cases:
            write_file(self.paths["hierarchy"], contents)
            with self.assertRaises(summarize_area.AreaReportError):
                summarize_area.collect_area_data(
                    self.paths["hierarchy"],
                    self.paths["qor"],
                    self.paths["physical"],
                )

    def test_rejects_qor_and_physical_closure_mismatches(self):
        write_file(self.paths["qor"], QOR_REPORT.replace("100.000000", "99.000000", 1))
        with self.assertRaises(summarize_area.AreaReportError):
            summarize_area.collect_area_data(
                self.paths["hierarchy"], self.paths["qor"], self.paths["physical"]
            )
        write_file(self.paths["qor"], QOR_REPORT)
        write_file(self.paths["physical"], PHYSICAL_REPORT.replace("120.00", "121.00"))
        with self.assertRaises(summarize_area.AreaReportError):
            summarize_area.collect_area_data(
                self.paths["hierarchy"], self.paths["qor"], self.paths["physical"]
            )

    def test_circuit_categories_share_module_denominator_without_double_counting(self):
        data = summarize_area.collect_area_data(
            self.paths["hierarchy"], self.paths["qor"], self.paths["physical"]
        )
        rows = data["circuit_records"]
        self.assertEqual(["combinational", "sequential", "macro_black_box"],
                         [row["category_key"] for row in rows])
        self.assertEqual([35.0, 25.0, 40.0], [row["area_um2"] for row in rows])
        self.assertAlmostEqual(100.0, sum(row["share_percent"] for row in rows))
        self.assertAlmostEqual(sum(row["area_um2"] for row in data["records"]),
                               sum(row["area_um2"] for row in rows))

    def test_zero_category_scientific_notation_and_rounding(self):
        report = HIERARCHY_REPORT.replace("35.000000", "+6.0e1")
        report = report.replace("25.000000", "0.0e0").replace("40.000000", "4.000001E+1")
        write_file(self.paths["hierarchy"], report)
        data = summarize_area.collect_area_data(
            self.paths["hierarchy"], self.paths["qor"], self.paths["physical"]
        )
        self.assertEqual(0.0, data["circuit_records"][1]["share_percent"])
        self.assertAlmostEqual(60.0, data["circuit_records"][0]["area_um2"])
        try:
            summarize_area._load_cairo()
        except summarize_area.AreaReportError:
            return
        summarize_area.generate_reports(self.root)
        self.assertTrue(os.path.isfile(self.paths["circuit_png"]))

    def test_rejects_missing_duplicate_invalid_and_mismatched_circuit_fields(self):
        field_line = "Combinational area:              35.000000\n"
        cases = [HIERARCHY_REPORT.replace(field_line, ""),
                 HIERARCHY_REPORT + field_line]
        for invalid in ("-1.0", "NaN", "inf", "1e999", "undefined", "36.0"):
            cases.append(HIERARCHY_REPORT.replace("35.000000", invalid))
        cases.append(HIERARCHY_REPORT.replace("100.000000", "0.0"))
        cases.append(HIERARCHY_REPORT.replace("100.000000", "1e999"))
        cases.append(HIERARCHY_REPORT.replace("x_sub_system                     25.0000",
                                              "x_sub_system                     1e999"))
        for report in cases:
            write_file(self.paths["hierarchy"], report)
            with self.assertRaises(summarize_area.AreaReportError):
                summarize_area.collect_area_data(
                    self.paths["hierarchy"], self.paths["qor"], self.paths["physical"]
                )

    def test_invalid_input_preserves_previous_outputs(self):
        for key in ("csv", "circuit_csv", "cpu_csv", "markdown", "png", "circuit_png", "cpu_png"):
            write_file(self.paths[key], "previous output")
        write_file(self.paths["hierarchy"], HIERARCHY_REPORT.replace("35.000000", "36.0"))
        self.assertEqual(1, summarize_area.main(["--project-root", self.root]))
        for key in ("csv", "circuit_csv", "cpu_csv", "markdown", "png", "circuit_png", "cpu_png"):
            with io.open(self.paths[key], encoding="utf-8") as handle:
                self.assertEqual("previous output", handle.read())

    def test_missing_final_design_does_not_start_implementation(self):
        process = subprocess.Popen([
            "make", "-s", "-C", ICC_DIR, "area_report",
            "MARKERS_DIR=" + os.path.join(self.root, "missing_markers"),
            "MW_DESIGN_LIBRARY=" + os.path.join(self.root, "missing_library"),
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = process.communicate()
        self.assertNotEqual(0, process.returncode)
        self.assertIn(b"area_report does not rebuild the design", stderr)
        self.assertFalse(os.path.exists(os.path.join(self.root, "missing_markers")))
        self.assertFalse(os.path.exists(os.path.join(self.root, "missing_library")))

    def test_cpu_breakdown_uses_subsystem_denominator_without_descendant_overlap(self):
        data = summarize_area.parse_hierarchy_report(self.paths["hierarchy"])
        rows = data["cpu_records"]
        self.assertEqual(25.0, data["cpu_total_cell_area_um2"])
        self.assertEqual(7, len(rows))
        self.assertEqual([10.0, 6.0, 3.0, 2.0, 1.0, 1.0, 2.0],
                         [row["area_um2"] for row in rows])
        self.assertAlmostEqual(40.0, rows[0]["share_percent"])
        self.assertAlmostEqual(100.0, sum(row["share_percent"] for row in rows))

    def test_rejects_incomplete_or_inconsistent_cpu_hierarchy(self):
        lsu_line = "x_sub_system/x_core/load_store_unit_i 1.0 1.0 1.0 0.0 0.0 lsu\n"
        cases = [HIERARCHY_REPORT.replace(lsu_line, ""), HIERARCHY_REPORT + lsu_line,
                 HIERARCHY_REPORT.replace("24.0000  24.0", "26.0000  24.0"),
                 HIERARCHY_REPORT.replace("24.0000  24.0", "22.0000  24.0")]
        for value in ("-1.0", "1e999", "NaN", "0.0"):
            cases.append(HIERARCHY_REPORT.replace("25.0000  25.0", value + "  25.0"))
        for report in cases:
            write_file(self.paths["hierarchy"], report)
            with self.assertRaises(summarize_area.AreaReportError):
                summarize_area.parse_hierarchy_report(self.paths["hierarchy"])

    def test_generates_csv_markdown_and_png(self):
        try:
            summarize_area._load_cairo()
        except summarize_area.AreaReportError:
            self.skipTest("PyCairo is unavailable")
        paths = summarize_area.generate_reports(self.root)
        for key in ("csv", "circuit_csv", "cpu_csv", "markdown", "png", "circuit_png", "cpu_png"):
            self.assertTrue(os.path.isfile(paths[key]))
            self.assertGreater(os.path.getsize(paths[key]), 0)
        csv_text = io.open(paths["csv"], "r", encoding="utf-8").read()
        markdown = io.open(paths["markdown"], "r", encoding="utf-8").read()
        self.assertEqual(8, len(csv_text.strip().splitlines()))
        self.assertIn(u"其他顶层逻辑", csv_text)
        self.assertIn(u"Physical-only cell area", markdown)
        self.assertIn(u"按电路性质划分", markdown)
        self.assertIn(u"icc_area_by_circuit.png", markdown)
        self.assertIn(u"icc_cpu_area_breakdown.png", markdown)
        with io.open(paths["cpu_csv"], encoding="utf-8") as handle:
            cpu_csv = handle.read().strip().splitlines()
        self.assertEqual(8, len(cpu_csv))
        self.assertIn("10.000000,40.000000", cpu_csv[1])
        with io.open(paths["circuit_csv"], encoding="utf-8") as handle:
            circuit_csv = handle.read().strip().splitlines()
        self.assertEqual(4, len(circuit_csv))
        self.assertEqual("category_key,category,area_um2,share_percent", circuit_csv[0])
        for key in ("png", "circuit_png", "cpu_png"):
            with open(paths[key], "rb") as handle:
                header = handle.read(24)
            self.assertEqual(b"\x89PNG\r\n\x1a\n", header[:8])
            self.assertEqual((900, 720), struct.unpack(">II", header[16:24]))


if __name__ == "__main__":
    unittest.main()
