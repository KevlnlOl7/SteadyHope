# -*- coding: utf-8 -*-
"""固定頻率 gating 測試向量的基本驗證。"""

import unittest

from generate_gating_frequency_vectors import (
    EXPECTED_SHOULD_ENABLE,
    FREQUENCIES_HZ,
    FS_HZ,
    RAW_LSB_PER_DPS,
    REST_BEFORE_SECONDS,
    SAMPLE_COUNT,
    TONE_SECONDS,
    make_vector,
    run_reference,
)


class GatingFrequencyVectorTest(unittest.TestCase):
    def test_vector_shape_and_rest_segments(self):
        before = REST_BEFORE_SECONDS * FS_HZ
        tone_end = before + TONE_SECONDS * FS_HZ
        for frequency in FREQUENCIES_HZ:
            vector = make_vector(frequency)
            self.assertEqual(len(vector), SAMPLE_COUNT)
            self.assertTrue(all(value == 0 for value in vector[:before]))
            self.assertTrue(all(value == 0 for value in vector[tone_end:]))

    def test_peak_amplitude_is_bno055_int16_scale(self):
        for frequency in FREQUENCIES_HZ:
            vector = make_vector(frequency)
            peak_dps = max(abs(value) for value in vector) / RAW_LSB_PER_DPS
            self.assertAlmostEqual(peak_dps, 15.0, places=4)

    def test_expected_frequency_classes(self):
        expected = dict(zip(FREQUENCIES_HZ, EXPECTED_SHOULD_ENABLE, strict=True))
        self.assertEqual([frequency for frequency, enabled in expected.items() if enabled],
                         [4, 5, 6])

    def test_reference_outputs_match_expected_classes(self):
        vectors = {frequency: make_vector(frequency) for frequency in FREQUENCIES_HZ}
        traces = run_reference(vectors)
        expected = dict(zip(FREQUENCIES_HZ, EXPECTED_SHOULD_ENABLE, strict=True))

        for frequency, should_enable in expected.items():
            enabled = [int(row["enabled"]) for row in traces[frequency]]
            self.assertEqual(any(enabled), bool(should_enable), frequency)
            self.assertEqual(enabled[-1], 0, frequency)

    def test_frequency_sweep_is_continuous_one_to_eight_hz(self):
        self.assertEqual(FREQUENCIES_HZ, tuple(range(1, 9)))


if __name__ == "__main__":
    unittest.main()
