# -*- coding: utf-8 -*-

import csv
import json
import unittest
from pathlib import Path

from generate_gating_amplitude_sweep_vectors import (
    AMPLITUDES_DPS,
    FREQUENCIES_HZ,
    FS_HZ,
    RAW_LSB_PER_DPS,
    SAMPLE_COUNT,
    TONE_END_SAMPLE,
    TONE_START_SAMPLE,
    generate,
    make_vector,
    run_reference,
    summarize,
    test_cases,
)


class GatingAmplitudeSweepVectorTest(unittest.TestCase):
    def test_matrix_contains_all_56_unique_cases(self):
        cases = test_cases()
        self.assertEqual(len(cases), 8 * 7)
        self.assertEqual(len(set(cases)), len(cases))
        self.assertEqual(
            cases,
            [
                (frequency, amplitude)
                for frequency in FREQUENCIES_HZ
                for amplitude in AMPLITUDES_DPS
            ],
        )

    def test_vectors_have_expected_shape_scale_and_rest(self):
        for frequency_hz, amplitude_dps in test_cases():
            vector = make_vector(frequency_hz, amplitude_dps)
            self.assertEqual(len(vector), SAMPLE_COUNT)
            self.assertTrue(all(value == 0 for value in vector[:TONE_START_SAMPLE]))
            self.assertTrue(all(value == 0 for value in vector[TONE_END_SAMPLE:]))
            peak = max(abs(value) for value in vector) / RAW_LSB_PER_DPS
            self.assertAlmostEqual(
                peak, amplitude_dps, delta=1.0 / RAW_LSB_PER_DPS
            )

    def test_current_reference_activation_boundary_is_explicit(self):
        vectors = {key: make_vector(*key) for key in test_cases()}
        active = {
            (int(row["frequency_hz"]), int(row["amplitude_peak_dps"])): (
                int(row["first_enabled_sample_index"]),
                int(row["delay_from_tone_start_ms"]),
                int(row["enabled_samples_during_400_sample_tone"]),
                int(row["release_delay_ms"]),
            )
            for row in summarize(run_reference(vectors))
            if int(row["reference_did_enable_during_tone"])
        }
        self.assertEqual(
            active,
            {
                (4, 15): (167, 670, 333, 560),
                (4, 20): (155, 550, 345, 620),
                (5, 10): (162, 620, 338, 460),
                (5, 15): (152, 520, 348, 520),
                (5, 20): (143, 430, 357, 570),
                (6, 15): (149, 490, 351, 520),
                (6, 20): (140, 400, 360, 570),
                (7, 20): (139, 390, 361, 490),
            },
        )

    def test_committed_csv_and_manifest_are_complete(self):
        output_dir = (
            Path(__file__).resolve().parents[1]
            / "handoff" / "test_vectors" / "gating_amplitude_sweep"
        )
        generate(output_dir)
        with (output_dir / "test_vectors.csv").open(
            encoding="utf-8", newline=""
        ) as stream:
            trace_rows = list(csv.DictReader(stream))
        with (output_dir / "expected_results.csv").open(
            encoding="utf-8", newline=""
        ) as stream:
            result_rows = list(csv.DictReader(stream))
        manifest = json.loads(
            (output_dir / "manifest.json").read_text(encoding="utf-8")
        )
        self.assertEqual(len(trace_rows), 56 * SAMPLE_COUNT)
        self.assertEqual(len(result_rows), 56)
        self.assertEqual(manifest["total_sample_count"], 56 * SAMPLE_COUNT)
        self.assertEqual(manifest["sample_rate_hz"], FS_HZ)
        self.assertTrue(
            (output_dir / "gating_amplitude_sweep_vectors.h").is_file()
        )


if __name__ == "__main__":
    unittest.main()
