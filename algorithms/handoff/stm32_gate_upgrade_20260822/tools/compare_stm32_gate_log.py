# -*- coding: utf-8 -*-
"""Strictly compare a motor-off STM32 gate trace with the golden trace."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from typing import Any


REQUIRED_COLUMNS = (
    "test_case_id",
    "sample_index",
    "sample_tick_ms",
    "gyro_x_raw_lsb",
    "tremor_envelope",
    "voluntary_envelope",
    "tremor_ratio",
    "on_count",
    "off_count",
    "gate_enabled",
    "gate_config_valid",
    "gate_last_fault",
    "actuation_authority",
)
FLOAT_COLUMNS = (
    "tremor_envelope",
    "voluntary_envelope",
    "tremor_ratio",
)
INTEGER_COMPARISONS = (
    "gyro_x_raw_lsb",
    "on_count",
    "off_count",
    "gate_enabled",
)


def _finite_float(value: str, name: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"{name} must be finite")
    return parsed


def _binary(value: str, name: str) -> int:
    parsed = int(value)
    if parsed not in (0, 1):
        raise ValueError(f"{name} must be 0 or 1")
    return parsed


def read_actual(path: Path) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        fields = set(reader.fieldnames or [])
        missing = [name for name in REQUIRED_COLUMNS if name not in fields]
        if missing:
            raise ValueError(
                "missing canonical columns: " + ", ".join(missing)
            )
        rows: list[dict[str, Any]] = []
        for line_number, source in enumerate(reader, start=2):
            try:
                row = {
                    "test_case_id": source["test_case_id"].strip(),
                    "sample_index": int(source["sample_index"]),
                    "sample_tick_ms": _finite_float(
                        source["sample_tick_ms"], "sample_tick_ms"
                    ),
                    "gyro_x_raw_lsb": int(source["gyro_x_raw_lsb"]),
                    "tremor_envelope": _finite_float(
                        source["tremor_envelope"], "tremor_envelope"
                    ),
                    "voluntary_envelope": _finite_float(
                        source["voluntary_envelope"],
                        "voluntary_envelope",
                    ),
                    "tremor_ratio": _finite_float(
                        source["tremor_ratio"], "tremor_ratio"
                    ),
                    "on_count": int(source["on_count"]),
                    "off_count": int(source["off_count"]),
                    "gate_enabled": _binary(
                        source["gate_enabled"], "gate_enabled"
                    ),
                    "gate_config_valid": _binary(
                        source["gate_config_valid"], "gate_config_valid"
                    ),
                    "gate_last_fault": int(source["gate_last_fault"]),
                    "actuation_authority": _binary(
                        source["actuation_authority"],
                        "actuation_authority",
                    ),
                }
                if not row["test_case_id"]:
                    raise ValueError("test_case_id is empty")
                rows.append(row)
            except (KeyError, ValueError) as error:
                raise ValueError(f"line {line_number}: {error}") from error
    if not rows:
        raise ValueError("STM32 log has no rows")
    return rows


def read_expected(path: Path) -> dict[tuple[str, int], dict[str, Any]]:
    rows: dict[tuple[str, int], dict[str, Any]] = {}
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        for line_number, source in enumerate(csv.DictReader(stream), start=2):
            key = (source["test_case_id"], int(source["sample_index"]))
            if key in rows:
                raise ValueError(
                    f"duplicate expected row at line {line_number}: {key}"
                )
            rows[key] = {
                "sample_tick_ms": float(source["sample_tick_ms"]),
                "gyro_x_raw_lsb": int(source["gyro_x_raw_lsb"]),
                "tremor_envelope": float(source["tremor_envelope"]),
                "voluntary_envelope": float(source["voluntary_envelope"]),
                "tremor_ratio": float(source["tremor_ratio"]),
                "on_count": int(source["on_count"]),
                "off_count": int(source["off_count"]),
                "gate_enabled": int(source["enabled"]),
            }
    if not rows:
        raise ValueError("expected trace has no rows")
    return rows


def compare(
    actual_rows: list[dict[str, Any]],
    expected_rows: dict[tuple[str, int], dict[str, Any]],
    *,
    float_tolerance: float,
    tick_tolerance_ms: float,
) -> dict[str, Any]:
    actual: dict[tuple[str, int], dict[str, Any]] = {}
    duplicate_rows = 0
    for row in actual_rows:
        key = (str(row["test_case_id"]), int(row["sample_index"]))
        if key in actual:
            duplicate_rows += 1
        actual[key] = row

    missing_rows = len(set(expected_rows) - set(actual))
    unexpected_rows = len(set(actual) - set(expected_rows))
    tick_mismatches = 0
    integer_mismatches = {name: 0 for name in INTEGER_COMPARISONS}
    float_mismatches = {name: 0 for name in FLOAT_COLUMNS}
    max_abs_difference = {name: 0.0 for name in FLOAT_COLUMNS}
    config_invalid_rows = 0
    gate_fault_rows = 0
    authority_violation_rows = 0

    for key in set(actual) & set(expected_rows):
        observed = actual[key]
        reference = expected_rows[key]
        if abs(
            float(observed["sample_tick_ms"])
            - float(reference["sample_tick_ms"])
        ) > tick_tolerance_ms:
            tick_mismatches += 1
        for name in INTEGER_COMPARISONS:
            if int(observed[name]) != int(reference[name]):
                integer_mismatches[name] += 1
        for name in FLOAT_COLUMNS:
            difference = abs(float(observed[name]) - float(reference[name]))
            max_abs_difference[name] = max(
                max_abs_difference[name], difference
            )
            if difference > float_tolerance:
                float_mismatches[name] += 1
        if int(observed["gate_config_valid"]) != 1:
            config_invalid_rows += 1
        if int(observed["gate_last_fault"]) != 0:
            gate_fault_rows += 1
        if int(observed["actuation_authority"]) != 0:
            authority_violation_rows += 1

    mismatch_count = (
        duplicate_rows
        + missing_rows
        + unexpected_rows
        + tick_mismatches
        + sum(integer_mismatches.values())
        + sum(float_mismatches.values())
        + config_invalid_rows
        + gate_fault_rows
        + authority_violation_rows
    )
    return {
        "schema_version": 1,
        "pass": mismatch_count == 0,
        "scope": "motor-off STM32 gate equivalence only",
        "expected_rows": len(expected_rows),
        "actual_rows": len(actual_rows),
        "duplicate_rows": duplicate_rows,
        "missing_rows": missing_rows,
        "unexpected_rows": unexpected_rows,
        "tick_mismatches": tick_mismatches,
        "integer_mismatches": integer_mismatches,
        "float_mismatches": float_mismatches,
        "max_abs_float_difference": max_abs_difference,
        "config_invalid_rows": config_invalid_rows,
        "gate_fault_rows": gate_fault_rows,
        "authority_violation_rows": authority_violation_rows,
        "mismatch_count": mismatch_count,
        "limitations": [
            "Passing proves pointwise gate equivalence, not motor safety.",
            "sample_tick_ms is a logical test tick; verify physical 100 Hz separately.",
            "The synthetic vectors are not clinical accuracy evidence.",
        ],
    }


def default_expected() -> Path:
    return Path(__file__).resolve().parents[1] / "expected" / "expected_trace.csv"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--expected", type=Path, default=default_expected())
    parser.add_argument("--output-json", type=Path)
    parser.add_argument("--float-tolerance", type=float, default=5.0e-4)
    parser.add_argument("--tick-tolerance-ms", type=float, default=0.1)
    args = parser.parse_args()

    try:
        actual = read_actual(args.input)
        expected = read_expected(args.expected)
        result = compare(
            actual,
            expected,
            float_tolerance=args.float_tolerance,
            tick_tolerance_ms=args.tick_tolerance_ms,
        )
    except (OSError, ValueError) as error:
        parser.error(str(error))

    rendered = json.dumps(result, ensure_ascii=False, indent=2)
    print(rendered)
    if args.output_json is not None:
        args.output_json.parent.mkdir(parents=True, exist_ok=True)
        args.output_json.write_text(rendered + "\n", encoding="utf-8")
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
