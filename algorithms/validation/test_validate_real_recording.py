# -*- coding: utf-8 -*-

import unittest

from validate_real_recording import validate_rows


def make_rows(sample_count=200, *, activity_label="rest", scored=1):
    rows = []
    for index in range(sample_count):
        raw_x = index % 5 - 2
        rows.append({
            "session_id": "S01",
            "segment_id": "SEG01",
            "activity_label": activity_label,
            "expected_gate": 0,
            "scored": scored,
            "sequence": index,
            "sample_tick_ms": index * 10,
            "gyro_x_raw": raw_x,
            "gyro_y_raw": 0,
            "gyro_z_raw": 0,
            "gyro_x_dps": raw_x / 16.0,
            "gyro_y_dps": 0.0,
            "gyro_z_dps": 0.0,
            "tremor_envelope": 0.1,
            "voluntary_envelope": 0.2,
            "tremor_ratio": 1.0 / 3.0,
            "enabled": 0,
            "sensor_valid": 1,
        })
    return rows


class ValidateRealRecordingTest(unittest.TestCase):
    def test_valid_recording_passes(self):
        result = validate_rows(make_rows())
        self.assertTrue(result["pass"])
        self.assertEqual(result["sample_count"], 200)
        self.assertEqual(result["bad_tick_count"], 0)

    def test_exploratory_mixed_segment_can_be_unscored(self):
        result = validate_rows(make_rows(activity_label="mixed", scored=0))
        self.assertTrue(result["pass"])
        self.assertEqual(result["segments"][0]["scored"], 0)

    def test_gap_bad_tick_invalid_sensor_and_scale_are_detected(self):
        rows = make_rows()
        rows[100]["sequence"] = 102
        rows[100]["sample_tick_ms"] = 1015
        rows[100]["sensor_valid"] = 0
        rows[100]["gyro_x_dps"] = 99.0
        result = validate_rows(rows)
        self.assertFalse(result["pass"])
        self.assertGreater(result["sequence_gap_count"], 0)
        self.assertGreater(result["bad_tick_count"], 0)
        self.assertEqual(result["invalid_sensor_count"], 1)
        self.assertEqual(result["raw_scale_mismatches"], 1)


if __name__ == "__main__":
    unittest.main()
