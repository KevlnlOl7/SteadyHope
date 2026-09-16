# -*- coding: utf-8 -*-
"""SteadyHope 16-byte BLE record的打包、解析與fixture產生器。"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct
from typing import Any, Iterable

import numpy as np

from tremor_frequency_reference import (
    analyze_tremor_frequency,
    read_input_csv,
)


RECORD_STRUCT = struct.Struct("<IIhhhBB")
RECORD_SIZE = RECORD_STRUCT.size
RAW_LSB_PER_DPS = 16.0


def _int16_raw(dps: float) -> int:
    value = int(round(float(dps) * RAW_LSB_PER_DPS))
    if not -32768 <= value <= 32767:
        raise ValueError("Gyro角速度量化後超出int16")
    return value


def pack_record(
    sequence: int,
    sample_tick_ms: int,
    gyro_x_raw: int,
    gyro_y_raw: int,
    gyro_z_raw: int,
    sensor_valid: int,
    motor_enabled: int,
) -> bytes:
    if sensor_valid not in (0, 1) or motor_enabled not in (0, 1):
        raise ValueError("sensor_valid與motor_enabled只能是0或1")
    return RECORD_STRUCT.pack(
        sequence, sample_tick_ms,
        gyro_x_raw, gyro_y_raw, gyro_z_raw,
        sensor_valid, motor_enabled,
    )


def unpack_records(payload: bytes) -> list[dict[str, int | float]]:
    if len(payload) % RECORD_SIZE != 0:
        raise ValueError(
            f"payload長度{len(payload)}不是{RECORD_SIZE} bytes的整數倍"
        )
    records = []
    for offset in range(0, len(payload), RECORD_SIZE):
        values = RECORD_STRUCT.unpack_from(payload, offset)
        sequence, tick, x_raw, y_raw, z_raw, valid, motor = values
        if valid not in (0, 1) or motor not in (0, 1):
            raise ValueError(f"offset={offset}的0/1欄位無效")
        records.append({
            "sequence": sequence,
            "sample_tick_ms": tick,
            "gyro_x_raw": x_raw,
            "gyro_y_raw": y_raw,
            "gyro_z_raw": z_raw,
            "gyro_x_dps": x_raw / RAW_LSB_PER_DPS,
            "gyro_y_dps": y_raw / RAW_LSB_PER_DPS,
            "gyro_z_dps": z_raw / RAW_LSB_PER_DPS,
            "sensor_valid": valid,
            "motor_enabled": motor,
        })
    return records


def records_from_frequency_csv(path: Path) -> list[dict[str, int | float]]:
    data = read_input_csv(path)
    records = []
    for index in range(len(data["sequence"])):
        records.append({
            "sequence": int(data["sequence"][index]),
            "sample_tick_ms": int(round(float(data["sample_tick_ms"][index]))),
            "gyro_x_raw": _int16_raw(data["gyro_x_dps"][index]),
            "gyro_y_raw": _int16_raw(data["gyro_y_dps"][index]),
            "gyro_z_raw": _int16_raw(data["gyro_z_dps"][index]),
            "sensor_valid": int(data["sensor_valid"][index]),
            "motor_enabled": int(data["motor_enabled"][index]),
        })
    return records


def pack_records(records: Iterable[dict[str, Any]]) -> bytes:
    return b"".join(pack_record(
        int(record["sequence"]),
        int(record["sample_tick_ms"]),
        int(record["gyro_x_raw"]),
        int(record["gyro_y_raw"]),
        int(record["gyro_z_raw"]),
        int(record["sensor_valid"]),
        int(record["motor_enabled"]),
    ) for record in records)


def analyze_records(records: list[dict[str, int | float]]) -> dict[str, Any]:
    gyro = np.asarray([
        [record["gyro_x_dps"], record["gyro_y_dps"], record["gyro_z_dps"]]
        for record in records
    ], dtype=float)
    return analyze_tremor_frequency(
        gyro,
        sequence=np.asarray([record["sequence"] for record in records]),
        sample_tick_ms=np.asarray([
            record["sample_tick_ms"] for record in records
        ]),
        sensor_valid=np.asarray([
            record["sensor_valid"] for record in records
        ]),
    )


def write_fixture(input_csv: Path, output_bin: Path, output_json: Path) -> None:
    source_records = records_from_frequency_csv(input_csv)
    output_bin.parent.mkdir(parents=True, exist_ok=True)
    output_bin.write_bytes(pack_records(source_records))
    decoded = unpack_records(output_bin.read_bytes())
    result = analyze_records(decoded)
    summary = {
        "schema": "little-endian <IIhhhBB",
        "record_size_bytes": RECORD_SIZE,
        "record_count": len(decoded),
        "payload_size_bytes": output_bin.stat().st_size,
        "first_record": decoded[0],
        "last_record": decoded[-1],
        "data_valid": result["data_valid"],
        "frequency_reliable": result["frequency_reliable"],
        "dominant_frequency_hz": result["dominant_frequency_hz"],
        "tremor_band_power_4_6_dps2": result["tremor_band_power_4_6_dps2"],
        "tremor_band_rms_4_6_dps": result["tremor_band_rms_4_6_dps"],
    }
    output_json.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-csv", type=Path, required=True)
    parser.add_argument("--output-bin", type=Path, required=True)
    parser.add_argument("--output-json", type=Path, required=True)
    args = parser.parse_args()
    write_fixture(args.input_csv, args.output_bin, args.output_json)
    print(f"wrote BLE fixture: {args.output_bin}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
