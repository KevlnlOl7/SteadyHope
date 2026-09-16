# -*- coding: utf-8 -*-

import unittest

import numpy as np

from suppression_metrics import compare_off_on


def signal(x_amplitude, y_amplitude=0.0, seconds=8.0):
    t = np.arange(round(seconds * 100)) / 100.0
    return np.column_stack((
        x_amplitude * np.sin(2.0 * np.pi * 5.0 * t),
        y_amplitude * np.sin(2.0 * np.pi * 5.0 * t + 0.4),
        np.zeros_like(t),
    ))


class SuppressionMetricsTest(unittest.TestCase):
    def test_half_amplitude_is_75_percent_power_reduction(self):
        result = compare_off_on(signal(10.0), signal(5.0))
        self.assertAlmostEqual(result["tpsr_power_percent"], 75.0, places=2)
        self.assertAlmostEqual(
            result["rms_amplitude_reduction_percent"], 50.0, places=2
        )

    def test_three_axis_total_detects_axis_transfer(self):
        result = compare_off_on(signal(10.0, 1.0), signal(4.0, 6.0))
        self.assertTrue(result["axis_transfer_warning"])
        self.assertIn("y", result["axes_with_more_power"])


if __name__ == "__main__":
    unittest.main()
