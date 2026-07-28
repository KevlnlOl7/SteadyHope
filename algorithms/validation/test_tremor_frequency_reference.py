# -*- coding: utf-8 -*-
"""tremor_frequency_reference.py 的自動測試。"""

import unittest
from pathlib import Path

import numpy as np

from tremor_frequency_reference import (
    EXPECTED_SAMPLES,
    FS_HZ,
    analyze_tremor_frequency,
    make_example_5hz,
    make_example_noisy_5hz,
    write_frequency_explain_plot,
    write_hann_window_explain_plot,
    write_report_plot,
    write_single_axis_report_plot,
)


def analyze_example(data):
    gyro = np.column_stack((
        data["gyro_x_dps"],
        data["gyro_y_dps"],
        data["gyro_z_dps"],
    ))
    return analyze_tremor_frequency(
        gyro,
        sample_tick_ms=data["sample_tick_ms"],
        sequence=data["sequence"],
        sensor_valid=data["sensor_valid"],
    )


class TremorFrequencyReferenceTest(unittest.TestCase):
    def test_example_reports_5_hz(self):
        result = analyze_example(make_example_5hz())

        self.assertTrue(result["data_valid"])
        self.assertTrue(result["frequency_reliable"])
        self.assertEqual(result["dominant_frequency_hz"], 5.0)
        self.assertEqual(result["frequency_resolution_hz"], 0.25)
        self.assertGreater(result["tremor_band_power_4_6_dps2"], 1.0)

    def test_pure_2_hz_motion_does_not_claim_tremor_frequency(self):
        t = np.arange(EXPECTED_SAMPLES) / FS_HZ
        gyro = np.column_stack((
            20.0 * np.sin(2.0 * np.pi * 2.0 * t),
            8.0 * np.sin(2.0 * np.pi * 2.0 * t + 0.4),
            np.zeros_like(t),
        ))
        result = analyze_tremor_frequency(gyro)

        self.assertTrue(result["data_valid"])
        self.assertFalse(result["frequency_reliable"])
        self.assertIsNone(result["dominant_frequency_hz"])

    def test_noisy_example_still_finds_about_5_hz(self):
        result = analyze_example(make_example_noisy_5hz())

        self.assertTrue(result["data_valid"])
        self.assertTrue(result["frequency_reliable"])
        self.assertGreaterEqual(result["dominant_frequency_hz"], 4.5)
        self.assertLessEqual(result["dominant_frequency_hz"], 5.5)

    def test_missing_sequence_is_rejected(self):
        data = make_example_5hz()
        data["sequence"][200:] += 1
        result = analyze_example(data)

        self.assertFalse(result["data_valid"])
        self.assertFalse(result["frequency_reliable"])
        self.assertTrue(any("掉包" in reason for reason in result["data_reasons"]))

    def test_nonfinite_sample_is_rejected(self):
        data = make_example_5hz()
        data["gyro_x_dps"][10] = np.nan
        result = analyze_example(data)

        self.assertFalse(result["data_valid"])
        self.assertFalse(result["frequency_reliable"])

    def test_report_plot_is_a_png(self):
        data = make_example_5hz()
        result = analyze_example(data)
        path = Path(__file__).parent / ".test_tremor_5hz_plot.png"
        try:
            write_report_plot(data, result, path)
            self.assertGreater(path.stat().st_size, 10_000)
            self.assertEqual(path.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
        finally:
            path.unlink(missing_ok=True)

    def test_explain_plot_is_a_png(self):
        data = make_example_5hz()
        result = analyze_example(data)
        path = Path(__file__).parent / ".test_tremor_5hz_explain.png"
        try:
            write_frequency_explain_plot(data, result, path)
            self.assertGreater(path.stat().st_size, 10_000)
            self.assertEqual(path.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
        finally:
            path.unlink(missing_ok=True)

    def test_single_axis_report_plot_is_a_png(self):
        data = make_example_noisy_5hz()
        result = analyze_example(data)
        path = Path(__file__).parent / ".test_tremor_noisy_5hz_plot.png"
        try:
            write_single_axis_report_plot(data, result, path)
            self.assertGreater(path.stat().st_size, 10_000)
            self.assertEqual(path.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
        finally:
            path.unlink(missing_ok=True)

    def test_hann_window_explain_plot_is_a_png(self):
        path = Path(__file__).parent / ".test_hann_window_explain.png"
        try:
            write_hann_window_explain_plot(path)
            self.assertGreater(path.stat().st_size, 10_000)
            self.assertEqual(path.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
        finally:
            path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
