# -*- coding: utf-8 -*-
"""Generate the STM32-ready 1-8 Hz x seven-amplitude V2 gating package."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

from tremor_gate_reference import TremorGateReference


FS_HZ = 100
FREQUENCIES_HZ = tuple(range(1, 9))
AMPLITUDES_DPS = (2, 4, 6, 8, 10, 15, 20)
REST_BEFORE_SECONDS = 1
TONE_SECONDS = 4
REST_AFTER_SECONDS = 2
SAMPLE_COUNT = FS_HZ * (
    REST_BEFORE_SECONDS + TONE_SECONDS + REST_AFTER_SECONDS
)
TONE_START_SAMPLE = REST_BEFORE_SECONDS * FS_HZ
TONE_END_SAMPLE = (REST_BEFORE_SECONDS + TONE_SECONDS) * FS_HZ
RAW_LSB_PER_DPS = 16


def case_id(frequency_hz: int, amplitude_dps: int) -> str:
    return f"f{frequency_hz:02d}_a{amplitude_dps:02d}"


def test_cases() -> list[tuple[int, int]]:
    return [
        (frequency_hz, amplitude_dps)
        for frequency_hz in FREQUENCIES_HZ
        for amplitude_dps in AMPLITUDES_DPS
    ]


def make_vector(frequency_hz: int, amplitude_dps: int) -> list[int]:
    """Return one 700-sample BNO055 GyroX raw int16 vector."""
    samples: list[int] = []
    for sample_index in range(SAMPLE_COUNT):
        if TONE_START_SAMPLE <= sample_index < TONE_END_SAMPLE:
            tone_time = (sample_index - TONE_START_SAMPLE) / FS_HZ
            gyro_x_dps = amplitude_dps * math.sin(
                2.0 * math.pi * frequency_hz * tone_time
            )
        else:
            gyro_x_dps = 0.0
        raw = int(round(gyro_x_dps * RAW_LSB_PER_DPS))
        if not -32768 <= raw <= 32767:
            raise ValueError("test vector exceeds int16 range")
        samples.append(raw)
    return samples


def run_reference(
    vectors: dict[tuple[int, int], list[int]],
) -> dict[tuple[int, int], list[dict[str, float | int | str]]]:
    traces: dict[tuple[int, int], list[dict[str, float | int | str]]] = {}
    for vector_index, (frequency_hz, amplitude_dps) in enumerate(test_cases()):
        gate = TremorGateReference()
        rows: list[dict[str, float | int | str]] = []
        for sample_index, raw in enumerate(vectors[(frequency_hz, amplitude_dps)]):
            gyro_x_dps = raw / RAW_LSB_PER_DPS
            gate.update(gyro_x_dps)
            row: dict[str, float | int | str] = {
                "vector_index": vector_index,
                "test_case_id": case_id(frequency_hz, amplitude_dps),
                "frequency_hz": frequency_hz,
                "amplitude_peak_dps": amplitude_dps,
                "sample_index": sample_index,
                "sample_tick_ms": sample_index * 10,
                "gyro_x_raw_lsb": raw,
                "gyro_x_dps": gyro_x_dps,
                "segment": (
                    "rest_before"
                    if sample_index < TONE_START_SAMPLE
                    else "tone"
                    if sample_index < TONE_END_SAMPLE
                    else "rest_after"
                ),
            }
            row.update(gate.snapshot())
            rows.append(row)
        traces[(frequency_hz, amplitude_dps)] = rows
    return traces


def summarize(
    traces: dict[tuple[int, int], list[dict[str, float | int | str]]],
) -> list[dict[str, float | int | str]]:
    summaries: list[dict[str, float | int | str]] = []
    for vector_index, (frequency_hz, amplitude_dps) in enumerate(test_cases()):
        rows = traces[(frequency_hz, amplitude_dps)]
        tone_rows = rows[TONE_START_SAMPLE:TONE_END_SAMPLE]
        first_tone_enabled = next(
            (
                int(row["sample_index"])
                for row in tone_rows
                if int(row["enabled"])
            ),
            None,
        )
        enabled_count = sum(int(row["enabled"]) for row in tone_rows)
        first_release = next(
            (
                int(row["sample_index"])
                for row in rows[TONE_END_SAMPLE:]
                if not int(row["enabled"])
            ),
            None,
        )
        summaries.append({
            "vector_index": vector_index,
            "test_case_id": case_id(frequency_hz, amplitude_dps),
            "frequency_hz": frequency_hz,
            "amplitude_peak_dps": amplitude_dps,
            "in_target_band": int(4 <= frequency_hz <= 6),
            "reference_did_enable_during_tone": int(enabled_count > 0),
            "first_enabled_sample_index": (
                "never" if first_tone_enabled is None else first_tone_enabled
            ),
            "delay_from_tone_start_ms": (
                "never"
                if first_tone_enabled is None
                else (first_tone_enabled - TONE_START_SAMPLE) * 10
            ),
            "release_delay_ms": (
                "not_applicable"
                if not enabled_count or first_release is None
                else (first_release - TONE_END_SAMPLE) * 10
            ),
            "enabled_samples_during_400_sample_tone": enabled_count,
            "enabled_fraction_during_tone": enabled_count / TONE_SECONDS / FS_HZ,
            "final_enabled": int(rows[-1]["enabled"]),
        })
    return summaries


def _format_c_array(values: list[int], indent: str = "        ") -> str:
    lines: list[str] = []
    for start in range(0, len(values), 16):
        chunk = values[start:start + 16]
        suffix = "," if start + 16 < len(values) else ""
        lines.append(indent + ", ".join(str(value) for value in chunk) + suffix)
    return "\n".join(lines)


def write_header(
    path: Path,
    vectors: dict[tuple[int, int], list[int]],
    traces: dict[tuple[int, int], list[dict[str, float | int | str]]],
    summaries: list[dict[str, float | int | str]],
) -> None:
    cases = test_cases()
    frequencies = ", ".join(str(frequency) for frequency, _ in cases)
    amplitudes = ", ".join(str(amplitude) for _, amplitude in cases)
    in_target = ", ".join(
        str(int(4 <= frequency <= 6)) for frequency, _ in cases
    )
    did_enable = ", ".join(
        str(int(row["reference_did_enable_during_tone"])) for row in summaries
    )
    raw_rows: list[str] = []
    enabled_rows: list[str] = []
    for key in cases:
        raw_rows.append("    {\n" + _format_c_array(vectors[key]) + "\n    }")
        enabled = [int(row["enabled"]) for row in traces[key]]
        enabled_rows.append("    {\n" + _format_c_array(enabled) + "\n    }")

    contents = f"""/* Auto-generated by generate_gating_amplitude_sweep_vectors.py.
 * Synthetic algorithm-injection data only; not human tremor data.
 * Include this header from exactly one STM32 test translation unit.
 */
#ifndef STEADYHOPE_GATING_AMPLITUDE_SWEEP_VECTORS_H
#define STEADYHOPE_GATING_AMPLITUDE_SWEEP_VECTORS_H

#include <stdint.h>

#define GATING_SWEEP_VECTOR_COUNT {len(cases)}U
#define GATING_SWEEP_SAMPLE_COUNT {SAMPLE_COUNT}U
#define GATING_SWEEP_FS_HZ {FS_HZ}U
#define GATING_SWEEP_RAW_LSB_PER_DPS {RAW_LSB_PER_DPS}.0
#define GATING_SWEEP_TONE_START_SAMPLE {TONE_START_SAMPLE}U
#define GATING_SWEEP_TONE_END_SAMPLE {TONE_END_SAMPLE}U

static const uint8_t
GATING_SWEEP_FREQUENCY_HZ[GATING_SWEEP_VECTOR_COUNT] = {{
    {frequencies}
}};

static const uint8_t
GATING_SWEEP_AMPLITUDE_DPS[GATING_SWEEP_VECTOR_COUNT] = {{
    {amplitudes}
}};

static const uint8_t
GATING_SWEEP_IN_TARGET_BAND[GATING_SWEEP_VECTOR_COUNT] = {{
    {in_target}
}};

static const uint8_t
GATING_SWEEP_REFERENCE_DID_ENABLE[GATING_SWEEP_VECTOR_COUNT] = {{
    {did_enable}
}};

static const int16_t
GATING_SWEEP_GYRO_X_RAW_LSB[GATING_SWEEP_VECTOR_COUNT][GATING_SWEEP_SAMPLE_COUNT] = {{
{',\n'.join(raw_rows)}
}};

static const uint8_t
GATING_SWEEP_EXPECTED_ENABLED[GATING_SWEEP_VECTOR_COUNT][GATING_SWEEP_SAMPLE_COUNT] = {{
{',\n'.join(enabled_rows)}
}};

#endif
"""
    path.write_text(contents, encoding="utf-8", newline="\n")


def write_trace_csv(
    path: Path,
    traces: dict[tuple[int, int], list[dict[str, float | int | str]]],
) -> None:
    fieldnames = [
        "vector_index", "test_case_id", "frequency_hz", "amplitude_peak_dps",
        "sample_index", "sample_tick_ms", "gyro_x_raw_lsb", "gyro_x_dps",
        "segment", "expected_enabled",
    ]
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        for key in test_cases():
            for source_row in traces[key]:
                writer.writerow({
                    "vector_index": source_row["vector_index"],
                    "test_case_id": source_row["test_case_id"],
                    "frequency_hz": source_row["frequency_hz"],
                    "amplitude_peak_dps": source_row["amplitude_peak_dps"],
                    "sample_index": source_row["sample_index"],
                    "sample_tick_ms": source_row["sample_tick_ms"],
                    "gyro_x_raw_lsb": source_row["gyro_x_raw_lsb"],
                    "gyro_x_dps": f"{float(source_row['gyro_x_dps']):.4f}",
                    "segment": source_row["segment"],
                    "expected_enabled": source_row["enabled"],
                })


def write_expected_results(
    path: Path, summaries: list[dict[str, float | int | str]],
) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream, fieldnames=list(summaries[0]), lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(summaries)


def write_manifest(
    path: Path, summaries: list[dict[str, float | int | str]],
) -> None:
    payload = {
        "schema_version": 1,
        "generated_by": "algorithms/validation/generate_gating_amplitude_sweep_vectors.py",
        "sample_rate_hz": FS_HZ,
        "frequencies_hz": list(FREQUENCIES_HZ),
        "amplitudes_peak_dps": list(AMPLITUDES_DPS),
        "raw_lsb_per_dps": RAW_LSB_PER_DPS,
        "sample_count_per_vector": SAMPLE_COUNT,
        "vector_count": len(test_cases()),
        "total_sample_count": len(test_cases()) * SAMPLE_COUNT,
        "scope": "Synthetic algorithm-injection test only; not human tremor data.",
        "cases": summaries,
    }
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def generate(output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    vectors = {
        key: make_vector(*key)
        for key in test_cases()
    }
    traces = run_reference(vectors)
    summaries = summarize(traces)
    write_header(
        output_dir / "gating_amplitude_sweep_vectors.h",
        vectors,
        traces,
        summaries,
    )
    write_trace_csv(output_dir / "test_vectors.csv", traces)
    write_expected_results(output_dir / "expected_results.csv", summaries)
    write_manifest(output_dir / "manifest.json", summaries)


def main() -> None:
    default_output = (
        Path(__file__).resolve().parents[1]
        / "handoff" / "test_vectors" / "gating_amplitude_sweep"
    )
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=default_output)
    args = parser.parse_args()
    generate(args.output_dir)
    print(
        f"generated {len(test_cases())} vectors x {SAMPLE_COUNT} samples "
        f"in {args.output_dir}"
    )


if __name__ == "__main__":
    main()
