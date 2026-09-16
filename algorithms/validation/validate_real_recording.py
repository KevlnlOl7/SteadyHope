# -*- coding: utf-8 -*-
"""驗收第一輪100 Hz實機三軸Gyro紀錄的格式、時序與基本品質。"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from typing import Any


ALLOWED_ACTIVITY_LABELS = {
    "rest",
    "posture_hold",
    "voluntary_slow",
    "voluntary_normal",
    "voluntary_fast",
    "cup_hold",
    "simulated_tremor",
    "mixed",
}

REQUIRED_FIELDS = {
    "session_id", "segment_id", "activity_label", "expected_gate", "scored",
    "sequence", "sample_tick_ms",
    "gyro_x_raw", "gyro_y_raw", "gyro_z_raw",
    "gyro_x_dps", "gyro_y_dps", "gyro_z_dps",
    "tremor_envelope", "voluntary_envelope", "tremor_ratio",
    "enabled", "sensor_valid",
}


def parse_bool(value: str, field: str) -> int:
    normalized = value.strip().lower()
    if normalized in {"1", "true", "on", "yes"}:
        return 1
    if normalized in {"0", "false", "off", "no"}:
        return 0
    raise ValueError(f"{field}必須是0或1")


def read_recording(path: Path) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        fields = set(reader.fieldnames or [])
        missing = sorted(REQUIRED_FIELDS - fields)
        if missing:
            raise ValueError(f"缺少必要欄位：{', '.join(missing)}")

        rows: list[dict[str, Any]] = []
        for line_number, source in enumerate(reader, start=2):
            try:
                row: dict[str, Any] = {
                    "session_id": source["session_id"].strip(),
                    "segment_id": source["segment_id"].strip(),
                    "activity_label": source["activity_label"].strip(),
                    "expected_gate": parse_bool(
                        source["expected_gate"], "expected_gate"
                    ),
                    "scored": parse_bool(source["scored"], "scored"),
                    "sequence": int(source["sequence"]),
                    "sample_tick_ms": int(source["sample_tick_ms"]),
                    "enabled": parse_bool(source["enabled"], "enabled"),
                    "sensor_valid": parse_bool(
                        source["sensor_valid"], "sensor_valid"
                    ),
                }
                for axis in "xyz":
                    row[f"gyro_{axis}_raw"] = int(source[f"gyro_{axis}_raw"])
                    row[f"gyro_{axis}_dps"] = float(source[f"gyro_{axis}_dps"])
                for field in (
                    "tremor_envelope", "voluntary_envelope", "tremor_ratio"
                ):
                    row[field] = float(source[field])
                if not row["session_id"] or not row["segment_id"]:
                    raise ValueError("session_id與segment_id不可空白")
                rows.append(row)
            except (KeyError, ValueError) as error:
                raise ValueError(f"第{line_number}列格式錯誤：{error}") from error
    if not rows:
        raise ValueError("CSV沒有資料列")
    return rows


def _uint32_delta(current: int, previous: int) -> int:
    return (current - previous) & 0xFFFFFFFF


def validate_rows(rows: list[dict[str, Any]]) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    raw_scale_mismatches = 0
    bad_tick_count = 0
    sequence_gap_count = 0
    invalid_sensor_count = 0

    for index, row in enumerate(rows):
        label = str(row["activity_label"])
        if label not in ALLOWED_ACTIVITY_LABELS:
            errors.append(f"第{index + 2}列activity_label不支援：{label}")
        if not 0.0 <= float(row["tremor_ratio"]) <= 1.0:
            errors.append(f"第{index + 2}列tremor_ratio不在0至1")
        if float(row["tremor_envelope"]) < 0.0:
            errors.append(f"第{index + 2}列tremor_envelope為負值")
        if float(row["voluntary_envelope"]) < 0.0:
            errors.append(f"第{index + 2}列voluntary_envelope為負值")
        for axis in "xyz":
            raw = int(row[f"gyro_{axis}_raw"])
            dps = float(row[f"gyro_{axis}_dps"])
            if not -32768 <= raw <= 32767:
                errors.append(f"第{index + 2}列gyro_{axis}_raw超出int16")
            if not math.isfinite(dps):
                errors.append(f"第{index + 2}列gyro_{axis}_dps不是有限值")
            elif abs(dps - raw / 16.0) > 1.0e-3:
                raw_scale_mismatches += 1
        if int(row["sensor_valid"]) == 0:
            invalid_sensor_count += 1

        if index == 0 or row["session_id"] != rows[index - 1]["session_id"]:
            continue
        previous = rows[index - 1]
        if int(row["sequence"]) != int(previous["sequence"]) + 1:
            sequence_gap_count += 1
        tick_delta = _uint32_delta(
            int(row["sample_tick_ms"]), int(previous["sample_tick_ms"])
        )
        if not 8 <= tick_delta <= 12:
            bad_tick_count += 1

    segment_summaries: list[dict[str, Any]] = []
    segment_keys: list[tuple[str, str]] = []
    for row in rows:
        key = (str(row["session_id"]), str(row["segment_id"]))
        if key not in segment_keys:
            segment_keys.append(key)
    for session_id, segment_id in segment_keys:
        group = [
            row for row in rows
            if row["session_id"] == session_id and row["segment_id"] == segment_id
        ]
        metadata = {
            (
                row["activity_label"], int(row["expected_gate"]), int(row["scored"])
            )
            for row in group
        }
        if len(metadata) != 1:
            errors.append(f"{session_id}/{segment_id}的標籤或計分設定不一致")
        activity_label, expected_gate, scored = next(iter(metadata))
        duration_ms = (
            _uint32_delta(
                int(group[-1]["sample_tick_ms"]),
                int(group[0]["sample_tick_ms"]),
            ) + 10
        )
        enabled_count = sum(int(row["enabled"]) for row in group)
        segment_summaries.append({
            "session_id": session_id,
            "segment_id": segment_id,
            "activity_label": activity_label,
            "expected_gate": expected_gate,
            "scored": scored,
            "sample_count": len(group),
            "duration_ms": duration_ms,
            "enabled_fraction": enabled_count / len(group),
            "invalid_sensor_samples": sum(
                int(row["sensor_valid"]) == 0 for row in group
            ),
        })
        if len(group) < 100:
            warnings.append(f"{session_id}/{segment_id}少於1秒資料")

    if sequence_gap_count:
        errors.append(f"sequence不連續共{sequence_gap_count}處")
    if bad_tick_count:
        errors.append(f"取樣間隔不在8至12 ms共{bad_tick_count}處")
    if invalid_sensor_count:
        errors.append(f"sensor_valid=0共{invalid_sensor_count}筆")
    if raw_scale_mismatches:
        errors.append(f"raw/16與dps不一致共{raw_scale_mismatches}個軸向值")

    return {
        "pass": not errors,
        "scope": "Engineering recording quality only; not a clinical diagnosis.",
        "sample_count": len(rows),
        "session_count": len({row["session_id"] for row in rows}),
        "segment_count": len(segment_summaries),
        "sequence_gap_count": sequence_gap_count,
        "bad_tick_count": bad_tick_count,
        "invalid_sensor_count": invalid_sensor_count,
        "raw_scale_mismatches": raw_scale_mismatches,
        "errors": errors,
        "warnings": warnings,
        "segments": segment_summaries,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-json", type=Path)
    args = parser.parse_args()
    try:
        result = validate_rows(read_recording(args.input))
    except ValueError as error:
        result = {
            "pass": False,
            "scope": "Engineering recording quality only; not a clinical diagnosis.",
            "errors": [str(error)],
        }
    output = json.dumps(result, ensure_ascii=False, indent=2)
    print(output)
    if args.output_json is not None:
        args.output_json.write_text(output + "\n", encoding="utf-8")
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
