# -*- coding: utf-8 -*-

import unittest

from gating_robustness_sim import (
    amplitude_sweep,
    dropout_sweep,
    jitter_sweep,
    mixed_signal_sweep,
    sample_rate_sweep,
)


class GatingRobustnessSimTest(unittest.TestCase):
    def test_amplitude_matrix_is_complete(self):
        rows = amplitude_sweep()
        self.assertEqual(len(rows), 8 * 7)
        five_hz_15 = next(
            row for row in rows
            if row["frequency_hz"] == 5 and row["amplitude_peak_dps"] == 15.0
        )
        self.assertGreater(five_hz_15["enabled_fraction_during_tone"], 0.85)

    def test_out_of_band_activation_is_explicitly_tracked(self):
        rows = amplitude_sweep()
        out_of_band = [row for row in rows if not row["in_target_band"]]
        activations = {
            (row["frequency_hz"], row["amplitude_peak_dps"])
            for row in out_of_band
            if row["enabled_samples_during_tone"] != 0
        }
        self.assertEqual(activations, {(7, 20.0)})
        self.assertTrue(all(
            row["enabled_samples_during_tone"] == 0
            for row in out_of_band
            if row["amplitude_peak_dps"] <= 15.0
        ))

    def test_mixed_sweep_contains_known_difficult_case(self):
        rows = mixed_signal_sweep()
        self.assertEqual(len(rows), 5 * 8)
        pure_tremor = next(
            row for row in rows
            if row["voluntary_2hz_peak_dps"] == 0.0
            and row["tremor_5hz_peak_dps"] == 15.0
        )
        self.assertGreater(pure_tremor["enabled_fraction_during_tone"], 0.85)

    def test_sample_rate_and_jitter_matrices_are_complete(self):
        self.assertEqual(len(sample_rate_sweep()), 9)
        self.assertEqual(len(jitter_sweep()), 20)

    def test_dropout_fail_safe_case_is_present(self):
        rows = dropout_sweep()
        case = next(
            row for row in rows
            if row["dropout_pattern"] == "burst_200ms"
            and row["dropout_policy"] == "nan_fail_safe"
        )
        self.assertEqual(case["drop_count"], 20)
        self.assertLess(case["enabled_fraction_during_tone"], 1.0)


if __name__ == "__main__":
    unittest.main()
