# -*- coding: utf-8 -*-
"""比較STM32固定頻率gating紀錄與PC golden trace。

最小必要欄位：frequency_hz、sample_index、gyro_x_dps、enabled。
欄位可使用文件中列出的STM32變數別名；其他內部量會輸出最大差異供debug。
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from typing import Any


ALIASES = {
    "frequency_hz": ("frequency_hz", "test_frequency_hz"),
    "sample_index": ("sample_index", "test_sample_index", "sequence"),
    "sample_tick_ms": ("sample_tick_ms", "tick_ms", "timestamp_ms"),
    "gyro_x_dps": (
        "gyro_x_dps", "selectedGyroInputDps", "raw_gyro_dps"
    ),
    "tremor_envelope": (
        "tremor_envelope", "bandpass_tremor_env", "gate_env_t"
    ),
    "voluntary_envelope": (
        "voluntary_envelope", "bandpass_voluntary_env", "gate_env_v"
    ),
    "tremor_ratio": (
        "tremor_ratio", "bandpass_tremor_ratio", "gate_ratio"
    ),
    "enabled": (
        "enabled", "bandpass_gate_enabled", "motor_enabled"
    ),
    "tremor_estimate": ("tremor_estimate", "tremorEstimate"),
    "pwm_percent": ("pwm_percent", "pwm_duty", "motor_pwm_percent"),
    "motor_direction": ("motor_direction", "motorDirection", "direction"),
}

REQUIRED = ("frequency_hz", "sample_index", "gyro_x_dps", "enabled")
OPTIONAL_COMPARE = ("tremor_envelope", "voluntary_envelope", "tremor_ratio")


def _column_map(fieldnames: list[str] | None) -> dict[str, str]:
    available = set(fieldnames or [])
    mapping: dict[str, str] = {}
    for canonical, choices in ALIASES.items():
        selected = next((choice for choice in choices if choice in available), None)
        if selected is not None:
            mapping[canonical] = selected
    missing = [name for name in REQUIRED if name not in mapping]
    if missing:
        raise ValueError(f"缺少必要欄位：{', '.join(missing)}")
    return mapping


def _parse_bool(value: str) -> int:
    normalized = value.strip().lower()
    if normalized in {"1", "true", "on", "yes"}:
        return 1
    if normalized in {"0", "false", "off", "no"}:
        return 0
    try:
        return 1 if int(float(normalized)) != 0 else 0
    except ValueError as error:
        raise ValueError(f"無法解析0/1欄位：{value!r}") from error


def read_stm32_log(path: Path) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        mapping = _column_map(reader.fieldnames)
        rows: list[dict[str, Any]] = []
        for line_number, source in enumerate(reader, start=2):
            try:
                row: dict[str, Any] = {
                    "frequency_hz": int(float(source[mapping["frequency_hz"]])),
                    "sample_index": int(float(source[mapping["sample_index"]])),
                    "gyro_x_dps": float(source[mapping["gyro_x_dps"]]),
                    "enabled": _parse_bool(source[mapping["enabled"]]),
                }
                for name in (
                    "sample_tick_ms", *OPTIONAL_COMPARE,
                    "tremor_estimate", "pwm_percent",
                ):
                    if name in mapping and source[mapping[name]].strip() != "":
                        row[name] = float(source[mapping[name]])
                if "motor_direction" in mapping:
                    row["motor_direction"] = source[mapping["motor_direction"]].strip()
                if not math.isfinite(row["gyro_x_dps"]):
                    raise ValueError("gyro_x_dps不是有限值")
                rows.append(row)
            except (KeyError, ValueError) as error:
                raise ValueError(f"第{line_number}列格式錯誤：{error}") from error
    if not rows:
        raise ValueError("紀錄檔沒有資料")
    return rows


def read_expected_trace(path: Path) -> dict[tuple[int, int], dict[str, float | int]]:
    expected: dict[tuple[int, int], dict[str, float | int]] = {}
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        for source in csv.DictReader(stream):
            frequency = int(source["frequency_hz"])
            sample_index = int(source["sample_index"])
            expected[(frequency, sample_index)] = {
                "gyro_x_dps": float(source["gyro_x_dps"]),
                "tremor_envelope": float(source["tremor_envelope"]),
                "voluntary_envelope": float(source["voluntary_envelope"]),
                "tremor_ratio": float(source["tremor_ratio"]),
                "enabled": int(source["enabled"]),
            }
    return expected


def analyze_rows(
    rows: list[dict[str, Any]],
    expected: dict[tuple[int, int], dict[str, float | int]],
) -> dict[str, Any]:
    frequencies = sorted({int(row["frequency_hz"]) for row in rows})
    summaries: list[dict[str, Any]] = []
    overall_pass = True

    for frequency in frequencies:
        group = [row for row in rows if int(row["frequency_hz"]) == frequency]
        group.sort(key=lambda row: int(row["sample_index"]))
        errors: list[str] = []
        indices = [int(row["sample_index"]) for row in group]
        if len(indices) != len(set(indices)):
            errors.append("sample_index有重複")
        if indices and indices != list(range(indices[0], indices[-1] + 1)):
            errors.append("sample_index不連續")

        ticks = [float(row["sample_tick_ms"]) for row in group if "sample_tick_ms" in row]
        if ticks and len(ticks) == len(group):
            bad_tick_count = sum(
                not 8.0 <= current - previous <= 12.0
                for previous, current in zip(ticks, ticks[1:])
            )
            if bad_tick_count:
                errors.append(f"有{bad_tick_count}個取樣間隔不在8–12 ms")

        missing_golden = 0
        gyro_mismatches = 0
        enabled_mismatches = 0
        first_enabled: int | None = None
        max_differences = {name: 0.0 for name in OPTIONAL_COMPARE}
        optional_counts = {name: 0 for name in OPTIONAL_COMPARE}

        for row in group:
            index = int(row["sample_index"])
            reference = expected.get((frequency, index))
            if reference is None:
                missing_golden += 1
                continue
            if abs(float(row["gyro_x_dps"]) - float(reference["gyro_x_dps"])) > 1.0e-6:
                gyro_mismatches += 1
            if int(row["enabled"]) != int(reference["enabled"]):
                enabled_mismatches += 1
            if first_enabled is None and int(row["enabled"]) != 0:
                first_enabled = index
            for name in OPTIONAL_COMPARE:
                if name in row:
                    optional_counts[name] += 1
                    max_differences[name] = max(
                        max_differences[name],
                        abs(float(row[name]) - float(reference[name])),
                    )

        if missing_golden:
            errors.append(f"有{missing_golden}筆找不到golden資料")
        if gyro_mismatches:
            errors.append(f"Gyro輸入有{gyro_mismatches}筆與測試向量不同")
        if enabled_mismatches:
            errors.append(f"enabled有{enabled_mismatches}筆不一致")

        summary = {
            "frequency_hz": frequency,
            "sample_count": len(group),
            "first_enabled_sample": first_enabled,
            "first_enabled_ms_from_start": (
                None if first_enabled is None else first_enabled * 10
            ),
            "enabled_samples": sum(int(row["enabled"]) for row in group),
            "enabled_mismatches": enabled_mismatches,
            "gyro_input_mismatches": gyro_mismatches,
            "max_abs_internal_differences": {
                name: max_differences[name]
                for name in OPTIONAL_COMPARE
                if optional_counts[name]
            },
            "errors": errors,
            "pass": not errors,
        }
        summaries.append(summary)
        overall_pass = overall_pass and summary["pass"]

    return {"pass": overall_pass, "frequencies": summaries}


def default_expected_trace() -> Path:
    return (
        Path(__file__).resolve().parents[1]
        / "handoff" / "test_vectors" / "gating_frequency"
        / "expected_trace.csv"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="STM32輸出的CSV")
    parser.add_argument(
        "--expected-trace", type=Path, default=default_expected_trace(),
        help="PC golden trace CSV",
    )
    parser.add_argument("--output-json", type=Path, help="另存完整驗收結果")
    args = parser.parse_args()

    try:
        rows = read_stm32_log(args.input)
        expected = read_expected_trace(args.expected_trace)
        result = analyze_rows(rows, expected)
    except (OSError, ValueError) as error:
        parser.error(str(error))

    output = json.dumps(result, ensure_ascii=False, indent=2)
    print(output)
    if args.output_json is not None:
        args.output_json.parent.mkdir(parents=True, exist_ok=True)
        args.output_json.write_text(output + "\n", encoding="utf-8")
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
