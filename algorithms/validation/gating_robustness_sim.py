# -*- coding: utf-8 -*-
"""產生V2 gating的離線robustness simulation結果。

涵蓋振幅、2 Hz自主動作＋5 Hz震顫、實際取樣率偏差、timer取樣間隔誤差與感測器掉拍。
所有結果皆為合成訊號工程測試，不是患者資料或實機成效。
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any, Callable

import numpy as np

from tremor_gate_reference import TremorGateReference


NOMINAL_FS_HZ = 100.0
RAW_LSB_PER_DPS = 16.0
TONE_START_SECONDS = 1.0
TONE_END_SECONDS = 5.0
TOTAL_SECONDS = 7.0
AMPLITUDES_DPS = (2.0, 4.0, 6.0, 8.0, 10.0, 15.0, 20.0)


def quantize_bno055_dps(value: np.ndarray | float) -> np.ndarray:
    values = np.asarray(value, dtype=float)
    return np.rint(values * RAW_LSB_PER_DPS) / RAW_LSB_PER_DPS


def uniform_times(actual_fs_hz: float = NOMINAL_FS_HZ) -> np.ndarray:
    sample_count = round(TOTAL_SECONDS * actual_fs_hz)
    return np.arange(sample_count, dtype=float) / actual_fs_hz


def jittered_times(max_jitter_ms: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    sample_count = round(TOTAL_SECONDS * NOMINAL_FS_HZ)
    intervals_ms = np.full(sample_count - 1, 10.0)
    if max_jitter_ms > 0.0:
        intervals_ms += rng.uniform(
            -max_jitter_ms, max_jitter_ms, size=sample_count - 1
        )
    return np.concatenate(([0.0], np.cumsum(intervals_ms) / 1000.0))


def make_tone(
    times_seconds: np.ndarray,
    frequency_hz: float,
    amplitude_dps: float,
) -> tuple[np.ndarray, np.ndarray]:
    tone_mask = (
        (times_seconds >= TONE_START_SECONDS)
        & (times_seconds < TONE_END_SECONDS)
    )
    signal = np.zeros_like(times_seconds)
    tone_time = times_seconds[tone_mask] - TONE_START_SECONDS
    signal[tone_mask] = amplitude_dps * np.sin(
        2.0 * np.pi * frequency_hz * tone_time
    )
    return quantize_bno055_dps(signal), tone_mask


def make_mixed_signal(
    times_seconds: np.ndarray,
    voluntary_amplitude_dps: float,
    tremor_amplitude_dps: float,
) -> tuple[np.ndarray, np.ndarray]:
    tone_mask = (
        (times_seconds >= TONE_START_SECONDS)
        & (times_seconds < TONE_END_SECONDS)
    )
    signal = np.zeros_like(times_seconds)
    tone_time = times_seconds[tone_mask] - TONE_START_SECONDS
    signal[tone_mask] = (
        voluntary_amplitude_dps * np.sin(2.0 * np.pi * 2.0 * tone_time)
        + tremor_amplitude_dps * np.sin(
            2.0 * np.pi * 5.0 * tone_time + 0.7
        )
    )
    return quantize_bno055_dps(signal), tone_mask


def _first_index(mask: np.ndarray) -> int | None:
    hits = np.flatnonzero(mask)
    return None if hits.size == 0 else int(hits[0])


def _longest_false_run(values: np.ndarray) -> int:
    longest = 0
    current = 0
    for value in values:
        if not bool(value):
            current += 1
            longest = max(longest, current)
        else:
            current = 0
    return longest


def run_gate(
    signal_dps: np.ndarray,
    times_seconds: np.ndarray,
    tone_mask: np.ndarray,
    *,
    drop_mask: np.ndarray | None = None,
    dropout_policy: str = "none",
) -> dict[str, float | int | None]:
    gate = TremorGateReference()
    enabled = np.zeros(len(signal_dps), dtype=int)
    ratios = np.zeros(len(signal_dps), dtype=float)
    previous_value = 0.0
    drops = (
        np.zeros(len(signal_dps), dtype=bool)
        if drop_mask is None else np.asarray(drop_mask, dtype=bool)
    )

    for index, source_value in enumerate(signal_dps):
        value = float(source_value)
        if drops[index]:
            if dropout_policy == "hold_last":
                value = previous_value
                enabled[index] = gate.update(value)
            elif dropout_policy == "zero_fill":
                enabled[index] = gate.update(0.0)
            elif dropout_policy == "nan_fail_safe":
                enabled[index] = gate.update(float("nan"))
            elif dropout_policy == "skip_update":
                enabled[index] = gate.enabled
            else:
                raise ValueError(f"未知dropout policy：{dropout_policy}")
        else:
            previous_value = value
            enabled[index] = gate.update(value)
        ratios[index] = gate.tremor_ratio

    first_tone_index = _first_index(tone_mask)
    first_enabled_index = _first_index((enabled != 0) & tone_mask)
    if first_tone_index is None or first_enabled_index is None:
        delay_ms = None
    else:
        delay_ms = 1000.0 * (
            times_seconds[first_enabled_index] - times_seconds[first_tone_index]
        )

    after_tone = times_seconds >= TONE_END_SECONDS
    first_release_index = _first_index((enabled == 0) & after_tone)
    was_enabled = bool(np.any((enabled != 0) & tone_mask))
    release_ms = (
        None if not was_enabled or first_release_index is None
        else 1000.0 * (times_seconds[first_release_index] - TONE_END_SECONDS)
    )
    tone_count = int(np.count_nonzero(tone_mask))
    tone_enabled = int(np.count_nonzero((enabled != 0) & tone_mask))

    return {
        "sample_count": len(signal_dps),
        "drop_count": int(np.count_nonzero(drops)),
        "first_enabled_delay_ms": delay_ms,
        "release_delay_ms": release_ms,
        "enabled_samples_during_tone": tone_enabled,
        "tone_sample_count": tone_count,
        "enabled_fraction_during_tone": (
            tone_enabled / tone_count if tone_count else 0.0
        ),
        "longest_disabled_run_during_tone_samples": _longest_false_run(
            enabled[tone_mask]
        ),
        "max_tremor_ratio_during_tone": (
            float(np.max(ratios[tone_mask])) if tone_count else 0.0
        ),
        "final_enabled": int(enabled[-1]),
    }


def amplitude_sweep() -> list[dict[str, Any]]:
    times = uniform_times()
    rows = []
    for frequency_hz in range(1, 9):
        for amplitude_dps in AMPLITUDES_DPS:
            signal, tone_mask = make_tone(times, frequency_hz, amplitude_dps)
            row = {
                "frequency_hz": frequency_hz,
                "amplitude_peak_dps": amplitude_dps,
                "in_target_band": int(4 <= frequency_hz <= 6),
            }
            row.update(run_gate(signal, times, tone_mask))
            rows.append(row)
    return rows


def mixed_signal_sweep() -> list[dict[str, Any]]:
    times = uniform_times()
    voluntary_values = (0.0, 10.0, 20.0, 30.0, 40.0)
    tremor_values = (0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 15.0, 20.0)
    rows = []
    for voluntary_dps in voluntary_values:
        for tremor_dps in tremor_values:
            signal, tone_mask = make_mixed_signal(
                times, voluntary_dps, tremor_dps
            )
            row = {
                "voluntary_2hz_peak_dps": voluntary_dps,
                "tremor_5hz_peak_dps": tremor_dps,
            }
            row.update(run_gate(signal, times, tone_mask))
            rows.append(row)
    return rows


def sample_rate_sweep() -> list[dict[str, Any]]:
    rows = []
    for actual_fs_hz in (95.0, 100.0, 105.0):
        times = uniform_times(actual_fs_hz)
        for frequency_hz in (4.0, 5.0, 6.0):
            signal, tone_mask = make_tone(times, frequency_hz, 15.0)
            row = {
                "actual_sample_rate_hz": actual_fs_hz,
                "filter_design_sample_rate_hz": NOMINAL_FS_HZ,
                "physical_frequency_hz": frequency_hz,
            }
            row.update(run_gate(signal, times, tone_mask))
            rows.append(row)
    return rows


def jitter_sweep() -> list[dict[str, Any]]:
    rows = []
    for max_jitter_ms in (0.0, 1.0, 2.0, 4.0):
        for trial in range(5):
            times = jittered_times(max_jitter_ms, seed=20260730 + trial)
            signal, tone_mask = make_tone(times, 5.0, 15.0)
            intervals_ms = np.diff(times) * 1000.0
            row = {
                "max_requested_jitter_ms": max_jitter_ms,
                "trial": trial,
                "min_interval_ms": float(np.min(intervals_ms)),
                "max_interval_ms": float(np.max(intervals_ms)),
                "mean_interval_ms": float(np.mean(intervals_ms)),
            }
            row.update(run_gate(signal, times, tone_mask))
            rows.append(row)
    return rows


def _dropout_masks(sample_count: int) -> dict[str, np.ndarray]:
    masks = {"none": np.zeros(sample_count, dtype=bool)}
    periodic = np.zeros(sample_count, dtype=bool)
    periodic[125:500:50] = True
    masks["periodic_2pct"] = periodic
    rng = np.random.default_rng(20260730)
    random_mask = np.zeros(sample_count, dtype=bool)
    tone_indices = np.arange(100, 500)
    random_mask[rng.choice(tone_indices, size=20, replace=False)] = True
    masks["random_5pct"] = random_mask
    burst = np.zeros(sample_count, dtype=bool)
    burst[250:270] = True
    masks["burst_200ms"] = burst
    return masks


def dropout_sweep() -> list[dict[str, Any]]:
    times = uniform_times()
    signal, tone_mask = make_tone(times, 5.0, 15.0)
    policies = ("hold_last", "zero_fill", "nan_fail_safe", "skip_update")
    rows = []
    for pattern, mask in _dropout_masks(len(signal)).items():
        selected_policies = ("hold_last",) if pattern == "none" else policies
        for policy in selected_policies:
            row = {"dropout_pattern": pattern, "dropout_policy": policy}
            row.update(run_gate(
                signal, times, tone_mask,
                drop_mask=mask,
                dropout_policy=policy,
            ))
            rows.append(row)
    return rows


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream, fieldnames=list(rows[0]), lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(rows)


def generate(output_dir: Path) -> None:
    generators: dict[str, Callable[[], list[dict[str, Any]]]] = {
        "amplitude_sweep.csv": amplitude_sweep,
        "mixed_2hz_5hz_sweep.csv": mixed_signal_sweep,
        "sample_rate_sweep.csv": sample_rate_sweep,
        "jitter_sweep.csv": jitter_sweep,
        "dropout_sweep.csv": dropout_sweep,
    }
    counts = {}
    for filename, generator in generators.items():
        rows = generator()
        _write_csv(output_dir / filename, rows)
        counts[filename] = len(rows)
    manifest = {
        "schema_version": 1,
        "generated_by": "algorithms/validation/gating_robustness_sim.py",
        "nominal_filter_sample_rate_hz": NOMINAL_FS_HZ,
        "bno055_raw_lsb_per_dps": RAW_LSB_PER_DPS,
        "scope": "Synthetic engineering simulation only; not human or patient data.",
        "files_and_row_counts": counts,
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    default_output = (
        Path(__file__).resolve().parents[1]
        / "handoff" / "test_vectors" / "gating_robustness"
    )
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=default_output)
    args = parser.parse_args()
    generate(args.output_dir)
    print(f"generated robustness results in {args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
