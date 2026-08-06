# -*- coding: utf-8 -*-

import unittest

from generate_gating_7hz_boundary_vectors import (
    AMPLITUDES_DPS,
    FS_HZ,
    RAW_LSB_PER_DPS,
    REST_BEFORE_SECONDS,
    SAMPLE_COUNT,
    TONE_SECONDS,
    make_vector,
    run_reference,
    summarize,
)


class Gating7HzBoundaryVectorTest(unittest.TestCase):
    def test_vectors_have_expected_shape_scale_and_rest(self):
        tone_start = REST_BEFORE_SECONDS * FS_HZ
        tone_end = tone_start + TONE_SECONDS * FS_HZ
        for amplitude_dps in AMPLITUDES_DPS:
            vector = make_vector(amplitude_dps)
            self.assertEqual(len(vector), SAMPLE_COUNT)
            self.assertTrue(all(value == 0 for value in vector[:tone_start]))
            self.assertTrue(all(value == 0 for value in vector[tone_end:]))
            peak = max(abs(value) for value in vector) / RAW_LSB_PER_DPS
            self.assertAlmostEqual(peak, amplitude_dps, delta=1.0 / RAW_LSB_PER_DPS)

    def test_current_reference_exposes_known_20_dps_activation(self):
        vectors = {
            amplitude_dps: make_vector(amplitude_dps)
            for amplitude_dps in AMPLITUDES_DPS
        }
        summaries = {
            float(row["amplitude_peak_dps"]): row
            for row in summarize(run_reference(vectors))
        }
        self.assertEqual(summaries[10.0]["reference_did_enable"], 0)
        self.assertEqual(summaries[15.0]["reference_did_enable"], 0)
        self.assertEqual(summaries[20.0]["reference_did_enable"], 1)
        self.assertEqual(summaries[20.0]["delay_from_tone_start_ms"], 390)
        self.assertEqual(
            summaries[20.0]["enabled_samples_during_400_sample_tone"], 361
        )

    def test_all_cases_are_outside_design_pass_band_and_finish_off(self):
        vectors = {
            amplitude_dps: make_vector(amplitude_dps)
            for amplitude_dps in AMPLITUDES_DPS
        }
        for row in summarize(run_reference(vectors)):
            self.assertEqual(row["design_should_enable"], 0)
            self.assertEqual(row["final_enabled"], 0)


if __name__ == "__main__":
    unittest.main()
