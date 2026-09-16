# -*- coding: utf-8 -*-

import csv
from pathlib import Path
import unittest

from validate_real_recording import ALLOWED_ACTIVITY_LABELS, REQUIRED_FIELDS


ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / "handoff" / "templates"


class RecordingTemplateTest(unittest.TestCase):
    def test_sample_template_contains_validator_schema(self):
        with (TEMPLATES / "real_recording_template.csv").open(
            encoding="utf-8", newline=""
        ) as stream:
            reader = csv.DictReader(stream)
            self.assertTrue(REQUIRED_FIELDS.issubset(set(reader.fieldnames or [])))

    def test_segment_plan_uses_allowed_labels_and_explicit_scoring(self):
        with (TEMPLATES / "recording_segment_plan.csv").open(
            encoding="utf-8", newline=""
        ) as stream:
            rows = list(csv.DictReader(stream))
        self.assertTrue(rows)
        self.assertTrue(all(
            row["activity_label"] in ALLOWED_ACTIVITY_LABELS for row in rows
        ))
        self.assertTrue(all(row["expected_gate"] in {"0", "1"} for row in rows))
        self.assertTrue(all(row["scored"] in {"0", "1"} for row in rows))
        simulated_targets = {
            row["target_frequency_hz"]
            for row in rows
            if row["plan_id"] in {"SIM4", "SIM5", "SIM6"}
        }
        self.assertEqual(simulated_targets, {"4", "5", "6"})
        mixed = next(row for row in rows if row["plan_id"] == "MIX")
        self.assertEqual(mixed["scored"], "0")

    def test_session_manifest_has_reproducibility_metadata(self):
        with (TEMPLATES / "recording_session_manifest_template.csv").open(
            encoding="utf-8", newline=""
        ) as stream:
            fields = set(csv.DictReader(stream).fieldnames or [])
        required = {
            "session_id", "subject_code", "recorded_at_utc",
            "firmware_version", "algorithm_version", "gate_config_id",
            "imu_mount_location", "imu_axis_x_direction",
            "imu_axis_y_direction", "imu_axis_z_direction", "motor_state",
        }
        self.assertTrue(required.issubset(fields))


if __name__ == "__main__":
    unittest.main()
