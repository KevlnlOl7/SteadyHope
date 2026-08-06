# -*- coding: utf-8 -*-

import math
import unittest

from calibrate_gating_thresholds import evaluate_config, make_configs, sweep
from tremor_gate_reference import GateConfig


def synthetic_rows():
    rows = []
    segments = [
        (2.0, 4.0, 0),
        (5.0, 4.0, 1),
        (0.0, 2.0, 0),
    ]
    index = 0
    for frequency, seconds, label in segments:
        for _ in range(round(seconds * 100)):
            value = 0.0 if frequency == 0.0 else 15.0 * math.sin(
                2.0 * math.pi * frequency * index / 100.0
            )
            rows.append({
                "gyro_x_dps": value,
                "expected_gate": label,
                "session_id": "test",
                "segment_id": str(label),
            })
            index += 1
    return rows


class CalibrateGatingThresholdsTest(unittest.TestCase):
    def test_default_config_separates_two_and_five_hz(self):
        result = evaluate_config(synthetic_rows(), GateConfig())
        self.assertGreater(result["specificity"], 0.95)
        self.assertGreater(result["sensitivity"], 0.80)

    def test_grid_obeys_hysteresis_order(self):
        configs = make_configs()
        self.assertTrue(configs)
        self.assertTrue(all(config.amp_off < config.amp_on for config in configs))
        self.assertTrue(all(config.ratio_off < config.ratio_on for config in configs))

    def test_sweep_returns_ranked_candidates(self):
        results = sweep(synthetic_rows())
        self.assertTrue(results)
        self.assertGreaterEqual(
            results[0]["balanced_accuracy"],
            results[-1]["balanced_accuracy"],
        )

    def test_unscored_exploratory_rows_are_excluded(self):
        rows = synthetic_rows()
        for row in rows[:100]:
            row["scored"] = 0
        result = evaluate_config(rows, GateConfig())
        self.assertEqual(result["scored_sample_count"], len(rows) - 100 - 150)


if __name__ == "__main__":
    unittest.main()
