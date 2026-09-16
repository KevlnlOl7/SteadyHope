# -*- coding: utf-8 -*-

from pathlib import Path
import unittest

from ble_packet_reference import (
    RECORD_SIZE,
    analyze_records,
    pack_record,
    unpack_records,
)


FIXTURE_DIR = Path(__file__).parent / "fixtures"


class BlePacketReferenceTest(unittest.TestCase):
    def test_record_is_exactly_16_bytes_and_little_endian(self):
        payload = pack_record(1, 10, -16, 32, -48, 1, 0)
        self.assertEqual(len(payload), 16)
        self.assertEqual(RECORD_SIZE, 16)
        record = unpack_records(payload)[0]
        self.assertEqual(record["sequence"], 1)
        self.assertEqual(record["gyro_x_dps"], -1.0)
        self.assertEqual(record["gyro_y_dps"], 2.0)

    def test_committed_binary_fixture_decodes_and_finds_5_hz(self):
        records = unpack_records((FIXTURE_DIR / "ble_5hz_records.bin").read_bytes())
        result = analyze_records(records)
        self.assertEqual(len(records), 400)
        self.assertTrue(result["data_valid"])
        self.assertTrue(result["frequency_reliable"])
        self.assertEqual(result["dominant_frequency_hz"], 5.0)

    def test_partial_record_is_rejected(self):
        with self.assertRaises(ValueError):
            unpack_records(b"\x00" * 15)


if __name__ == "__main__":
    unittest.main()
