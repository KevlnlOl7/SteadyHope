# -*- coding: utf-8 -*-
"""STM32 gating CSV驗收工具測試。"""

import csv
from pathlib import Path
import unittest

from analyze_stm32_gating_log import (
    analyze_rows,
    read_expected_trace,
    read_stm32_log,
)


FIXTURE_DIR = (
    Path(__file__).resolve().parents[1]
    / "handoff" / "test_vectors" / "gating_frequency"
)


class Stm32GatingLogTest(unittest.TestCase):
    def setUp(self):
        self.expected = read_expected_trace(FIXTURE_DIR / "expected_trace.csv")

    @staticmethod
    def _rows_for_frequency(expected, frequency):
        return [
            {
                "frequency_hz": frequency,
                "sample_index": index,
                "sample_tick_ms": index * 10,
                "gyro_x_dps": values["gyro_x_dps"],
                "tremor_envelope": values["tremor_envelope"],
                "voluntary_envelope": values["voluntary_envelope"],
                "tremor_ratio": values["tremor_ratio"],
                "enabled": values["enabled"],
            }
            for (current_frequency, index), values in expected.items()
            if current_frequency == frequency
        ]

    def test_golden_rows_pass(self):
        rows = self._rows_for_frequency(self.expected, 5)
        result = analyze_rows(rows, self.expected)
        self.assertTrue(result["pass"])
        self.assertEqual(result["frequencies"][0]["enabled_mismatches"], 0)

    def test_one_wrong_enabled_fails(self):
        rows = self._rows_for_frequency(self.expected, 5)
        rows[200]["enabled"] = 1 - rows[200]["enabled"]
        result = analyze_rows(rows, self.expected)
        self.assertFalse(result["pass"])
        self.assertEqual(result["frequencies"][0]["enabled_mismatches"], 1)

    def test_stm32_alias_columns_are_accepted(self):
        source_rows = self._rows_for_frequency(self.expected, 2)[:3]
        path = Path(__file__).parent / ".test_stm32_gating_log.csv"
        try:
            with path.open("w", encoding="utf-8", newline="") as stream:
                fieldnames = [
                    "test_frequency_hz", "test_sample_index", "sample_tick_ms",
                    "selectedGyroInputDps", "bandpass_tremor_env",
                    "bandpass_voluntary_env", "bandpass_tremor_ratio",
                    "bandpass_gate_enabled",
                ]
                writer = csv.DictWriter(stream, fieldnames=fieldnames)
                writer.writeheader()
                for row in source_rows:
                    writer.writerow({
                        "test_frequency_hz": row["frequency_hz"],
                        "test_sample_index": row["sample_index"],
                        "sample_tick_ms": row["sample_tick_ms"],
                        "selectedGyroInputDps": row["gyro_x_dps"],
                        "bandpass_tremor_env": row["tremor_envelope"],
                        "bandpass_voluntary_env": row["voluntary_envelope"],
                        "bandpass_tremor_ratio": row["tremor_ratio"],
                        "bandpass_gate_enabled": row["enabled"],
                    })
            parsed = read_stm32_log(path)
        finally:
            path.unlink(missing_ok=True)
        self.assertEqual(len(parsed), 3)
        self.assertEqual(parsed[0]["frequency_hz"], 2)


if __name__ == "__main__":
    unittest.main()
