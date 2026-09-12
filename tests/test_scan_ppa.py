# -*- coding: utf-8 -*-
from __future__ import print_function

import io
import os
import shutil
import tempfile
import unittest

import scan_ppa


def write_file(path, contents):
    directory = os.path.dirname(path)
    if not os.path.isdir(directory):
        os.makedirs(directory)
    if not isinstance(contents, scan_ppa.text_type):
        contents = contents.decode("utf-8")
    with io.open(path, "w", encoding="utf-8") as handle:
        handle.write(contents)


class ScanPpaTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="scan_ppa_test_")

    def tearDown(self):
        shutil.rmtree(self.root)

    def test_default_matrix_contains_40_unique_points_and_baseline(self):
        points = scan_ppa.build_points(scan_ppa.make_config())
        self.assertEqual(40, len(points))
        self.assertEqual(40, len(set(point["id"] for point in points)))
        baseline_points = [
            point
            for point in points
            if abs(point["clock_period_ns"] - 3.0) < 1.0e-12
            and point["requested_core_width_um"] == 430.72
            and point["requested_core_height_um"] == 560.0
        ]
        self.assertEqual(1, len(baseline_points))

    def test_area_timing_power_parsers_and_baseline_metrics(self):
        reports = os.path.join(self.root, "icc", "reports")
        write_file(
            os.path.join(reports, "metal_fill_icc.sum"),
            "Core area           : 240791.52\n"
            "Cell Utilization(non-fixed) = 72.78% (A) / (D - C)\n",
        )
        write_file(
            os.path.join(reports, "metal_fill_icc.qor"),
            "  Cell Area:            180894.538552\n"
            "  Design Area:          180894.538552\n"
            "  Core area: (40000 40000 470600 599200)\n",
        )
        write_file(
            os.path.join(reports, "place_opt_icc.placement_utilization.rpt"),
            "Physical DB scale:    1000 db_unit = 1 um\n",
        )

        requirements = {"wc_max": "setup", "tc_min": "both", "bc_min": "hold"}
        for corner in scan_ppa.PT_CORNERS:
            run_dir = os.path.join(self.root, "pt", "runs", corner)
            write_file(
                os.path.join(run_dir, "timing_status_%s.rpt" % corner),
                "PT_REQUIRED_CHECKS %s\n"
                "PT_SETUP_WNS 0.02\n"
                "PT_HOLD_WNS 0.01\n"
                "PT_SETUP_VIOLATING_PATHS 0\n"
                "PT_HOLD_VIOLATING_PATHS 0\n"
                "PT_RESULT PASS\n" % requirements[corner],
            )
            write_file(
                os.path.join(run_dir, "constraint_violators_%s.rpt" % corner),
                "No constraint violations.\n",
            )
            write_file(
                os.path.join(run_dir, "check_constraints_%s.rpt" % corner),
                "Constraints checked.\n",
            )
            write_file(os.path.join(run_dir, "pt.log"), "PrimeTime completed.\n")

        write_file(
            os.path.join(self.root, "postsim", "build", "power", "power_window.rpt"),
            "POWER_START_NS 3135.5\n"
            "POWER_END_NS 4655.0\n"
            "POWER_DURATION_NS 1519.5\n"
            "POWER_CYCLES 506\n",
        )
        write_file(
            os.path.join(self.root, "pt", "runs", "power", "power_summary.rpt"),
            "POWER_RESULT PASS\n"
            "POWER_WINDOW_START_NS 3135.5\n"
            "POWER_WINDOW_END_NS 4655.0\n"
            "POWER_WINDOW_DURATION_NS 1519.5\n"
            "POWER_WINDOW_CYCLES 506\n"
            "SOC_INTERNAL_POWER_MW 26.9\n"
            "SOC_SWITCHING_POWER_MW 6.082\n"
            "SOC_DYNAMIC_POWER_MW 32.982\n"
            "SOC_LEAKAGE_POWER_MW 1.272\n"
            "SOC_TOTAL_POWER_MW 34.3\n"
            "SOC_WINDOW_ENERGY_NJ 52.11885\n"
            "FFT_TOTAL_POWER_MW 7.159\n"
            "FFT_SOC_POWER_PERCENT 20.87172\n",
        )

        point = [
            value
            for value in scan_ppa.build_points(scan_ppa.make_config())
            if abs(value["clock_period_ns"] - 3.0) < 1.0e-12
            and value["requested_core_height_um"] == 560.0
        ][0]
        point["result"].update(scan_ppa.parse_area_reports(self.root))
        point["result"].update(scan_ppa.parse_timing(self.root))
        point["result"].update(scan_ppa.parse_power(self.root))
        scan_ppa.finalize_metrics(point)

        self.assertTrue(point["result"]["timing_converged"])
        self.assertAlmostEqual(430.6, point["result"]["actual_core_width_um"])
        self.assertAlmostEqual(559.2, point["result"]["actual_core_height_um"])
        self.assertAlmostEqual(1.0, point["result"]["compute_density_ratio"])
        self.assertAlmostEqual(1.0, point["result"]["compute_efficiency_ratio"])

    def test_power_parser_accepts_dynamic_matching_cycle_count(self):
        write_file(
            os.path.join(self.root, "postsim", "build", "power", "power_window.rpt"),
            "POWER_START_NS 100.0\n"
            "POWER_END_NS 1300.0\n"
            "POWER_DURATION_NS 1200.0\n"
            "POWER_CYCLES 400\n",
        )
        write_file(
            os.path.join(self.root, "pt", "runs", "power", "power_summary.rpt"),
            "POWER_RESULT PASS\n"
            "POWER_WINDOW_START_NS 100.0\n"
            "POWER_WINDOW_END_NS 1300.0\n"
            "POWER_WINDOW_DURATION_NS 1200.0\n"
            "POWER_WINDOW_CYCLES 400\n"
            "SOC_INTERNAL_POWER_MW 20.0\n"
            "SOC_SWITCHING_POWER_MW 5.0\n"
            "SOC_DYNAMIC_POWER_MW 25.0\n"
            "SOC_LEAKAGE_POWER_MW 1.0\n"
            "SOC_TOTAL_POWER_MW 26.0\n"
            "SOC_WINDOW_ENERGY_NJ 31.2\n"
            "FFT_TOTAL_POWER_MW 6.0\n"
            "FFT_SOC_POWER_PERCENT 23.076923\n",
        )

        result = scan_ppa.parse_power(self.root)
        self.assertEqual(400, result["fft16_cycles"])
        point = scan_ppa.build_points(scan_ppa.make_config())[0]
        point["result"].update(result)
        scan_ppa.finalize_metrics(point)
        self.assertEqual(400, point["result"]["fft16_cycles"])
        self.assertAlmostEqual(1600.0, point["result"]["fft16_time_ns"])

    def test_power_parser_rejects_cycle_mismatch(self):
        write_file(
            os.path.join(self.root, "postsim", "build", "power", "power_window.rpt"),
            "POWER_START_NS 100.0\nPOWER_END_NS 1300.0\n"
            "POWER_DURATION_NS 1200.0\nPOWER_CYCLES 400\n",
        )
        write_file(
            os.path.join(self.root, "pt", "runs", "power", "power_summary.rpt"),
            "POWER_RESULT PASS\nPOWER_WINDOW_START_NS 100.0\n"
            "POWER_WINDOW_END_NS 1300.0\nPOWER_WINDOW_DURATION_NS 1200.0\n"
            "POWER_WINDOW_CYCLES 401\nSOC_INTERNAL_POWER_MW 20.0\n"
            "SOC_SWITCHING_POWER_MW 5.0\nSOC_DYNAMIC_POWER_MW 25.0\n"
            "SOC_LEAKAGE_POWER_MW 1.0\nSOC_TOTAL_POWER_MW 26.0\n"
            "SOC_WINDOW_ENERGY_NJ 31.2\nFFT_TOTAL_POWER_MW 6.0\n"
            "FFT_SOC_POWER_PERCENT 23.076923\n",
        )
        with self.assertRaises(scan_ppa.ScanError):
            scan_ppa.parse_power(self.root)

    def test_simulation_cycle_parser_prefers_machine_metric(self):
        log_path = os.path.join(self.root, "run.log")
        write_file(
            log_path,
            "CPU execution cycles: 506\n"
            "FFT16_METRIC cycles=388 trigger1=80 done1=85 trigger2=130 "
            "done2=135 first_result=145 final_result=388\n",
        )
        self.assertEqual(388, scan_ppa.parse_simulation_cycles(log_path))

    def test_run_stage_is_idempotent_after_checkpoint(self):
        scanner = object.__new__(scan_ppa.Scanner)
        scanner.run_root = self.root
        scanner.state_path = os.path.join(self.root, "state.json")
        scanner.state = scan_ppa.initial_state(scan_ppa.make_config(), "test-source")
        point = scanner.state["points"][0]
        calls = []

        scanner.run_stage(point, "area", lambda: calls.append("called"))
        scanner.run_stage(point, "area", lambda: calls.append("called-again"))

        self.assertEqual(["called"], calls)
        self.assertEqual("complete", point["stages"]["area"]["status"])
        saved = scan_ppa.read_json(scanner.state_path)
        self.assertEqual("complete", saved["points"][0]["stages"]["area"]["status"])

    def test_run_lock_uses_kernel_lock_and_recovers_stale_file(self):
        lock_path = os.path.join(self.root, "run", ".lock")
        write_file(lock_path, '{"hostname": "icpc", "pid": 2}\n')

        with scan_ppa.RunLock(lock_path):
            lock = scan_ppa.read_json(lock_path)
            self.assertEqual(os.getpid(), lock["pid"])
            self.assertTrue(scan_ppa.scan_lock_is_held(lock_path))
            with self.assertRaises(scan_ppa.ScanError):
                with scan_ppa.RunLock(lock_path):
                    pass

        self.assertFalse(scan_ppa.scan_lock_is_held(lock_path))
        with scan_ppa.RunLock(lock_path):
            pass

    def test_failed_stage_is_retried_on_next_invocation(self):
        scanner = object.__new__(scan_ppa.Scanner)
        scanner.run_root = self.root
        scanner.state_path = os.path.join(self.root, "state.json")
        scanner.state = scan_ppa.initial_state(scan_ppa.make_config(), "test-source")
        point = scanner.state["points"][0]
        attempts = []

        def fail_once():
            attempts.append("failed")
            raise scan_ppa.ScanError("synthetic tool failure")

        with self.assertRaises(scan_ppa.ScanError):
            scanner.run_stage(point, "icc", fail_once)
        self.assertEqual("failed", point["stages"]["icc"]["status"])

        scanner.run_stage(point, "icc", lambda: attempts.append("retried"))
        self.assertEqual(["failed", "retried"], attempts)
        self.assertEqual("complete", point["stages"]["icc"]["status"])

    def test_transient_license_failure_is_retried_in_same_invocation(self):
        scanner = object.__new__(scan_ppa.Scanner)
        scanner.run_root = self.root
        scanner.state_path = os.path.join(self.root, "state.json")
        scanner.state = scan_ppa.initial_state(scan_ppa.make_config(), "test-source")
        scanner.license_retry_delay_seconds = 0.0
        point = scanner.state["points"][0]
        log_path = os.path.join(self.root, "logs", "icc.log")
        attempts = []

        def license_then_success():
            attempts.append("called")
            if len(attempts) == 1:
                write_file(
                    log_path,
                    "Information: Re-attempting to check if license server is up\n"
                    "Fatal: Galaxy-Common+Galaxy-ICC is not enabled. (DCSH-1)\n",
                )
                raise scan_ppa.CommandError(["icc_shell"], 255, log_path)

        scanner.run_stage(point, "icc", license_then_success)

        self.assertEqual(["called", "called"], attempts)
        self.assertEqual("complete", point["stages"]["icc"]["status"])
        self.assertEqual(1, point["stages"]["icc"]["license_retry_count"])
        self.assertTrue(
            os.path.isfile(os.path.join(self.root, "logs", "icc.attempt-001.log"))
        )

    def test_permanent_license_configuration_error_is_not_retried(self):
        log_path = os.path.join(self.root, "permanent-license.log")
        write_file(
            log_path,
            "License server system does not support this feature.\n"
            "Unable to obtain an ICC license.\n",
        )
        error = scan_ppa.CommandError(["icc_shell"], 255, log_path)
        self.assertFalse(scan_ppa.is_transient_license_failure(error))

    def test_scanner_creates_isolated_source_workspace(self):
        repo_root = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
        run_root = os.path.join(self.root, "run")
        scanner = scan_ppa.Scanner(repo_root, run_root)
        scanner.load_or_create()
        point = scanner.state["points"][0]
        scanner.prepare(point)

        self.assertTrue(scanner._workspace_matches(point))
        self.assertTrue(os.path.isfile(os.path.join(scanner.workspace, "dc", "compile.sh")))
        self.assertTrue(os.path.isfile(os.path.join(scanner.workspace, "scan_ppa.py")))
        self.assertFalse(os.path.exists(os.path.join(scanner.workspace, "icc", "results")))
        self.assertTrue(os.path.isfile(os.path.join(run_root, "summary.csv")))

    def test_markdown_summary_accepts_json_unicode_on_python2(self):
        state_path = os.path.join(self.root, "state.json")
        state = scan_ppa.initial_state(scan_ppa.make_config(), "test-source")
        scan_ppa.atomic_write_json(state_path, state)

        reloaded = scan_ppa.read_json(state_path)
        report = scan_ppa.markdown_summary(reloaded)

        self.assertIsInstance(report, scan_ppa.text_type)
        self.assertIn(u"扫描结果", report)
        self.assertIn(reloaded["points"][0]["id"], report)

    def test_gate_self_check_failure_is_point_level_not_tool_failure(self):
        scanner = object.__new__(scan_ppa.Scanner)
        scanner.workspace = self.root
        scanner.run_root = self.root
        point = scan_ppa.build_points(scan_ppa.make_config())[0]

        def failed_simulation(*unused_arguments):
            write_file(
                os.path.join(
                    self.root, "postsim", "build", "power", "run.log"
                ),
                "Doing SDF annotation ...... Done\n"
                "ERROR: timeout after 20000 cycles\n"
                "CPU+FFT16 TEST FAIL: timeout\n",
            )
            raise scan_ppa.CommandError(["make", "power_vcd"], 1, "test.log")

        scanner.run_command = failed_simulation
        scanner.point_environment = lambda unused_point: {}
        scanner.power_vcd(point)

        self.assertFalse(point["result"]["postsim_pass"])
        self.assertIn("20000", point["result"]["postsim_error"])

    def test_gate_tool_failure_remains_fatal_and_restartable(self):
        scanner = object.__new__(scan_ppa.Scanner)
        scanner.workspace = self.root
        scanner.run_root = self.root
        point = scan_ppa.build_points(scan_ppa.make_config())[0]

        def license_failure(*unused_arguments):
            raise scan_ppa.CommandError(["vcs"], 255, "compile.log")

        scanner.run_command = license_failure
        scanner.point_environment = lambda unused_point: {}
        with self.assertRaises(scan_ppa.CommandError):
            scanner.power_vcd(point)

    def test_data_sram_scoreboard_uses_only_stable_module_ports(self):
        repo_root = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
        tb_path = os.path.join(repo_root, "postsim", "tb", "tb_soc.sv")
        with io.open(tb_path, "r", encoding="utf-8") as handle:
            testbench = handle.read()

        self.assertNotIn("x_soc.x_data_sram.ahbl_", testbench)
        self.assertIn("x_soc.x_data_sram.i_sram_block.mem", testbench)
        self.assertNotIn("x_soc.x_data_sram.slave0_hready", testbench)
        self.assertNotIn("x_soc.x_data_sram.ahbl_", testbench)


if __name__ == "__main__":
    unittest.main()
