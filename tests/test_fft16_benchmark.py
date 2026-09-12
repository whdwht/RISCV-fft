# -*- coding: utf-8 -*-
from __future__ import print_function

import imp
import os
import shutil
import struct
import subprocess
import tempfile
import unittest


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
benchmark = imp.load_source(
    "fft16_benchmark",
    os.path.join(REPO_ROOT, "sim_16", "fft16_benchmark.py"),
)


def phase_metric_line():
    return (
        u"FFT16_PHASE_METRIC first_even_input=40 first_odd_input=110 "
        u"bin0_done=175 bin1_done=210 bin2_done=240 bin3_done=275 "
        u"bin4_done=300 bin5_done=330 bin6_done=360 bin7_done=390\n"
    )


def detailed_run():
    return {
        "id": "optimized_O3", "label": "C opt -O3",
        "variant": "optimized", "status": "PASS", "opt_level": "O3",
        "image_bytes": 1000, "cycles": 390, "trigger1": 80,
        "done1": 84, "trigger2": 140, "done2": 144,
        "first_result": 155, "final_result": 390,
        "soc_internal_power_mw": 23.0,
        "soc_switching_power_mw": 6.0,
        "soc_leakage_power_mw": 1.0,
        "soc_total_power_mw": 30.0, "soc_window_energy_nj": 35.2,
        "soc_internal_energy_nj": 27.0,
        "soc_switching_energy_nj": 7.0,
        "soc_leakage_energy_nj": 1.2,
        "soc_cpu_subsystem_power_mw": 17.0,
        "soc_cpu_subsystem_energy_nj": 20.0,
        "fft_total_power_mw": 6.0, "fft_window_energy_nj": 7.0,
        "soc_instruction_sram_power_mw": 3.4,
        "soc_instruction_sram_energy_nj": 4.0,
        "soc_data_sram_power_mw": 1.3, "soc_data_sram_energy_nj": 1.5,
        "soc_rom_power_mw": 0.4, "soc_rom_energy_nj": 0.5,
        "soc_data_fabric_power_mw": 0.2, "soc_data_fabric_energy_nj": 0.2,
        "soc_other_power_mw": 1.7, "soc_other_energy_nj": 2.0,
        "power_metrics": {
            "cycles": 390, "first_even_input": 40, "trigger1": 80,
            "done1": 84, "first_odd_input": 110, "trigger2": 140,
            "done2": 144, "first_result": 155,
            "bin0_done": 175, "bin1_done": 210, "bin2_done": 240,
            "bin3_done": 275, "bin4_done": 300, "bin5_done": 330,
            "bin6_done": 360, "bin7_done": 390, "final_result": 390,
        },
    }


class Fft16BenchmarkTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="fft16_benchmark_test_")

    def tearDown(self):
        shutil.rmtree(self.root)

    def test_metric_parser(self):
        path = os.path.join(self.root, "run.log")
        benchmark.atomic_write_text(
            path,
            u"CPU+FFT16 TEST PASS: 16 complex results matched the reference\n"
            u"FFT16_METRIC cycles=390 trigger1=80 done1=84 trigger2=140 "
            u"done2=144 first_result=155 final_result=390\n" +
            phase_metric_line(),
        )
        metrics = benchmark.parse_simulation_log(path)
        self.assertEqual(390, metrics["cycles"])
        self.assertEqual(144, metrics["done2"])
        self.assertEqual(360, metrics["bin6_done"])

    def test_metric_parser_rejects_non_monotonic_detail(self):
        path = os.path.join(self.root, "run.log")
        benchmark.atomic_write_text(
            path,
            u"CPU+FFT16 TEST PASS: 16 complex results matched the reference\n"
            u"FFT16_METRIC cycles=390 trigger1=80 done1=84 trigger2=140 "
            u"done2=144 first_result=155 final_result=390\n"
            u"FFT16_PHASE_METRIC first_even_input=40 first_odd_input=110 "
            u"bin0_done=175 bin1_done=210 bin2_done=205 bin3_done=275 "
            u"bin4_done=300 bin5_done=330 bin6_done=360 bin7_done=390\n",
        )
        with self.assertRaises(benchmark.BenchmarkError):
            benchmark.parse_simulation_log(path)

    def test_best_selection_uses_cycles_size_then_defined_tie_order(self):
        rows = [
            {"opt_level": "O1", "cycles": 400, "image_bytes": 600},
            {"opt_level": "O2", "cycles": 390, "image_bytes": 700},
            {"opt_level": "O3", "cycles": 390, "image_bytes": 700},
            {"opt_level": "Os", "cycles": 390, "image_bytes": 680},
        ]
        self.assertEqual("Os", benchmark.choose_best(rows)["opt_level"])
        rows[-1]["image_bytes"] = 700
        self.assertEqual("O3", benchmark.choose_best(rows)["opt_level"])

    def test_derived_metrics_use_dynamic_cycles(self):
        row = benchmark.derived_metrics({
            "cycles": 400,
            "trigger1": 80,
            "done1": 84,
            "trigger2": 140,
            "done2": 144,
            "soc_total_power_mw": 30.0,
            "soc_window_energy_nj": 36.1,
        })
        self.assertEqual(1200.0, row["latency_ns"])
        self.assertEqual(4, row["fft1_wait_cycles"])
        self.assertEqual(256, row["post_fft2_cycles"])
        self.assertAlmostEqual(36.0, row["nominal_energy_nj"])
        self.assertAlmostEqual(16.0 / (400 * 3.0e-9),
                               row["system_performance_points_per_second"])
        self.assertAlmostEqual(
            (16.0 / (36.1e-9)) / 1.0e6,
            row["compute_efficiency_points_per_joule"] / 1.0e6,
        )
        self.assertNotIn("compute_efficiency_fft_per_joule", row)

    def test_compute_efficiency_uses_vcd_window_energy(self):
        first = benchmark.derived_metrics({
            "cycles": 400, "soc_total_power_mw": 30.0,
            "soc_window_energy_nj": 36.1,
        })
        second = benchmark.derived_metrics({
            "cycles": 400, "soc_total_power_mw": 60.0,
            "soc_window_energy_nj": 36.1,
        })
        self.assertEqual(first["compute_efficiency_points_per_joule"],
                         second["compute_efficiency_points_per_joule"])
        self.assertAlmostEqual(
            16.0e9 / 36.1,
            first["compute_efficiency_points_per_joule"],
        )

    def test_power_summarizer_extracts_hierarchy_and_closes_energy(self):
        run_dir = os.path.join(self.root, "power")
        os.makedirs(run_dir)
        window = os.path.join(self.root, "power_window.rpt")
        benchmark.atomic_write_text(
            window,
            u"POWER_START_NS 0\nPOWER_END_NS 1200\n"
            u"POWER_DURATION_NS 1200\nPOWER_CYCLES 400\n",
        )
        soc_report = (
            u"Dynamic Power Units = 1 W\nLeakage Power Units = 1 W\n"
            u"Cell Internal Power = 0.020 W\nNet Switching Power = 0.009 W\n"
            u"Cell Leakage Power = 0.001 W\nTotal Power = 0.030 W\n"
        )
        fft_report = (
            u"Dynamic Power Units = 1 W\nLeakage Power Units = 1 W\n"
            u"Cell Internal Power = 0.0045 W\nNet Switching Power = 0.001 W\n"
            u"Cell Leakage Power = 0.0005 W\nTotal Power = 0.006 W\n"
        )
        hierarchy_report = u"\n".join((
            u"  x_data_sram (data) 0 0 0 0 0 0 0 0.001 3.3",
            u"  x_rom_ahbl (rom) 0 0 0 0 0 0 0 0.0003 1.0",
            u"  x_data_fabric (fabric) 0 0 0 0 0 0 0 0.0002 0.7",
            u"  x_isram_ahbl (isram) 0 0 0 0 0 0 0 0.003 10.0",
            u"  u_fft8_top (fft) 0 0 0 0 0 0 0 0.006 20.0",
            u"  x_sub_system (cpu) 0 0 0 0 0 0 0 0.018 60.0",
            u"",
        ))
        for name, content in (
                ("power_vcd.rpt", soc_report),
                ("power_fft8.rpt", fft_report),
                ("power_vcd_hier.rpt", hierarchy_report),
                ("pt.log", u"PrimeTime completed\n")):
            benchmark.atomic_write_text(os.path.join(run_dir, name), content)
        subprocess.check_output([
            "bash", os.path.join(REPO_ROOT, "pt", "summarize_power.sh"),
            run_dir, window,
        ], stderr=subprocess.STDOUT)
        parsed = benchmark.parse_power_summary(
            os.path.join(run_dir, "power_summary.rpt")
        )
        self.assertAlmostEqual(36.0, parsed["soc_window_energy_nj"])
        self.assertAlmostEqual(21.6, parsed["soc_cpu_subsystem_energy_nj"])
        self.assertAlmostEqual(1.8, parsed["soc_other_energy_nj"])

    def test_special_twiddle_reductions_match_generic_q10_math(self):
        cosine = (1024, 946, 724, 392, 0, -392, -724, -946)
        sine = (0, 392, 724, 946, 1024, 946, 724, 392)
        values = (-32768, -12001, -1, 0, 1, 17003, 32767)
        for real in values:
            for imag in values:
                for k in (0, 2, 4, 6):
                    generic_real = (cosine[k] * real + sine[k] * imag) >> 10
                    generic_imag = (cosine[k] * imag - sine[k] * real) >> 10
                    if k == 0:
                        reduced = (real, imag)
                    elif k == 2:
                        reduced = (724 * (real + imag) >> 10,
                                   724 * (imag - real) >> 10)
                    elif k == 4:
                        reduced = (imag, -real)
                    else:
                        reduced = (724 * (imag - real) >> 10,
                                   -724 * (imag + real) >> 10)
                    self.assertEqual((generic_real, generic_imag), reduced)

    def test_detailed_breakdowns_close_to_measured_totals(self):
        row = detailed_run()
        phases, twiddles = benchmark.cycle_breakdowns(row)
        hierarchy, energy_types = benchmark.energy_breakdowns(row)
        self.assertEqual(390, sum(value for unused, unused2, value in phases))
        self.assertEqual(246, sum(value for unused, unused2, value in twiddles))
        self.assertAlmostEqual(35.2, sum(value[3] for value in hierarchy))
        self.assertAlmostEqual(35.2, sum(value[3] for value in energy_types))

    def test_headless_renderer_writes_valid_png(self):
        try:
            benchmark._load_cairo()
        except benchmark.BenchmarkError:
            self.skipTest("PyCairo is not installed")
        rows = [benchmark.derived_metrics(benchmark.BASELINE)]
        rows.append(benchmark.derived_metrics({
            "id": "c_optimized_O3", "label": "C opt -O3",
            "status": "PASS", "opt_level": "O3", "cycles": 390,
            "trigger1": 80, "done1": 84, "trigger2": 140,
            "done2": 144, "first_result": 155, "final_result": 390,
            "soc_total_power_mw": 30.0, "soc_window_energy_nj": 35.2,
        }))
        summary = os.path.join(self.root, "summary.png")
        breakdown = os.path.join(self.root, "breakdown.png")
        state = {"updated_at": "2026-09-11T00:00:00Z", "error": ""}
        benchmark.render_summary_png(summary, rows, state)
        benchmark.render_breakdown_png(breakdown, rows, state)
        for path in (summary, breakdown):
            with open(path, "rb") as handle:
                header = handle.read(24)
            self.assertEqual(b"\x89PNG\r\n\x1a\n", header[:8])
            width, height = struct.unpack(">II", header[16:24])
            self.assertGreaterEqual(width, 1000)
            self.assertGreaterEqual(height, 700)

    def test_report_bundle_contains_csv_markdown_and_png(self):
        try:
            benchmark._load_cairo()
        except benchmark.BenchmarkError:
            self.skipTest("PyCairo is not installed")
        state = {
            "updated_at": "2026-09-11T00:00:00Z",
            "error": "",
            "selected": {"optimized": "optimized_O3"},
            "report_order": ["optimized_O3"],
            "runs": {"optimized_O3": detailed_run()},
        }
        paths = benchmark.write_reports(self.root, state)
        self.assertEqual(7, len(paths))
        for path in paths:
            self.assertTrue(os.path.getsize(path) > 0)
        csv_text = benchmark.read_text(paths[0])
        self.assertIn("asm_legacy", csv_text)
        self.assertIn("optimized_O3", csv_text)
        self.assertIn("system_performance_points_per_second", csv_text)
        self.assertIn("compute_efficiency_points_per_joule", csv_text)
        self.assertNotIn("compute_efficiency_fft_per_joule", csv_text)
        markdown = benchmark.read_text(paths[1])
        self.assertIn(u"FFT16 软件优化结果", markdown)
        self.assertIn(u"当前最优方案周期细分", markdown)
        detail_csv = benchmark.read_text(paths[4])
        self.assertIn("energy_by_hierarchy,cpu_subsystem", detail_csv)
        self.assertIn("post_fft2_cycles,general_odd_k", detail_csv)


if __name__ == "__main__":
    unittest.main()
