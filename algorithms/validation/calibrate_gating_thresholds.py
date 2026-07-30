# -*- coding: utf-8 -*-
"""用已標註的100 Hz GyroX紀錄離線比較V2 gating門檻。

必要欄位：gyro_x_dps、expected_gate。若有session_id，切換session時會重設gate。
健康受試者的模擬抖動標籤只能用於工程校調，不是Parkinson's disease臨床標籤。
"""

from __future__ import annotations

import argparse
import csv
import itertools
import json
import math
from pathlib import Path
import statistics
from typing import Any, Iterable

from tremor_gate_reference import GateConfig, TremorGateReference


def read_labeled_csv(path: Path) -> list[dict[str, Any]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        fields = set(reader.fieldnames or [])
        missing = {"gyro_x_dps", "expected_gate"} - fields
        if missing:
            raise ValueError(f"缺少必要欄位：{', '.join(sorted(missing))}")
        rows: list[dict[str, Any]] = []
        for line_number, source in enumerate(reader, start=2):
            try:
                gyro = float(source["gyro_x_dps"])
                expected = int(float(source["expected_gate"]))
                if not math.isfinite(gyro) or expected not in (0, 1):
                    raise ValueError("gyro必須為有限值，expected_gate只能是0或1")
                rows.append({
                    "gyro_x_dps": gyro,
                    "expected_gate": expected,
                    "session_id": source.get("session_id", "default") or "default",
                    "segment_id": source.get("segment_id", "") or "",
                })
            except ValueError as error:
                raise ValueError(f"第{line_number}列格式錯誤：{error}") from error
    if not rows:
        raise ValueError("CSV沒有資料")
    return rows


def _transition_delays(
    expected: list[int], actual: list[int], sessions: list[str]
) -> tuple[list[int], list[int]]:
    onset_delays: list[int] = []
    release_delays: list[int] = []
    for index in range(1, len(expected)):
        if sessions[index] != sessions[index - 1]:
            continue
        target = expected[index]
        if target == expected[index - 1]:
            continue
        end = index + 1
        while end < len(expected):
            if sessions[end] != sessions[index] or expected[end] != target:
                break
            end += 1
        hit = next((position for position in range(index, end)
                    if actual[position] == target), None)
        if hit is not None:
            delay = hit - index
            (onset_delays if target else release_delays).append(delay)
    return onset_delays, release_delays


def evaluate_config(
    rows: list[dict[str, Any]], config: GateConfig,
    *, transition_grace_samples: int = 75,
) -> dict[str, Any]:
    gate = TremorGateReference(config)
    actual: list[int] = []
    expected = [int(row["expected_gate"]) for row in rows]
    sessions = [str(row["session_id"]) for row in rows]
    previous_session: str | None = None

    for row, session in zip(rows, sessions):
        if session != previous_session:
            gate.reset()
            previous_session = session
        actual.append(gate.update(float(row["gyro_x_dps"])))

    scored = [True] * len(rows)
    for index in range(1, len(rows)):
        if sessions[index] == sessions[index - 1] and expected[index] != expected[index - 1]:
            end = min(len(rows), index + transition_grace_samples)
            for ignored in range(index, end):
                if sessions[ignored] != sessions[index]:
                    break
                scored[ignored] = False

    pairs = [
        (a, e) for a, e, include in zip(actual, expected, scored) if include
    ]
    tp = sum(a == 1 and e == 1 for a, e in pairs)
    tn = sum(a == 0 and e == 0 for a, e in pairs)
    fp = sum(a == 1 and e == 0 for a, e in pairs)
    fn = sum(a == 0 and e == 1 for a, e in pairs)
    sensitivity = tp / (tp + fn) if tp + fn else None
    specificity = tn / (tn + fp) if tn + fp else None
    fpr = fp / (tn + fp) if tn + fp else None
    balanced = (
        (sensitivity + specificity) / 2.0
        if sensitivity is not None and specificity is not None else None
    )
    onset, release = _transition_delays(expected, actual, sessions)
    target_pass = (
        sensitivity is not None and specificity is not None
        and sensitivity >= 0.90 and fpr is not None and fpr <= 0.02
    )

    return {
        "config": {
            "amp_on": config.amp_on,
            "amp_off": config.amp_off,
            "ratio_on": config.ratio_on,
            "ratio_off": config.ratio_off,
            "envelope_decay": config.envelope_decay,
            "samples_on": config.samples_on,
            "samples_off": config.samples_off,
        },
        "sample_count": len(rows),
        "scored_sample_count": len(pairs),
        "transition_grace_ms": transition_grace_samples * 10,
        "confusion": {"tp": tp, "tn": tn, "fp": fp, "fn": fn},
        "sensitivity": sensitivity,
        "specificity": specificity,
        "false_positive_rate": fpr,
        "balanced_accuracy": balanced,
        "median_onset_delay_ms": (
            None if not onset else statistics.median(onset) * 10.0
        ),
        "median_release_delay_ms": (
            None if not release else statistics.median(release) * 10.0
        ),
        "meets_engineering_target": target_pass,
    }


def make_configs(
    amp_on_values: Iterable[float] = (3.0, 4.5, 6.0, 7.5, 9.0),
    amp_off_values: Iterable[float] = (1.5, 3.0, 4.5),
    ratio_on_values: Iterable[float] = (0.45, 0.55, 0.65),
    ratio_off_values: Iterable[float] = (0.35, 0.45, 0.55),
) -> list[GateConfig]:
    configs = []
    for amp_on, amp_off, ratio_on, ratio_off in itertools.product(
        amp_on_values, amp_off_values, ratio_on_values, ratio_off_values
    ):
        if amp_off >= amp_on or ratio_off >= ratio_on:
            continue
        configs.append(GateConfig(
            amp_on=amp_on,
            amp_off=amp_off,
            ratio_on=ratio_on,
            ratio_off=ratio_off,
        ))
    return configs


def sweep(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    results = [evaluate_config(rows, config) for config in make_configs()]

    def ranking(result: dict[str, Any]) -> tuple[float, float, float, float]:
        balanced = result["balanced_accuracy"] or -1.0
        sensitivity = result["sensitivity"] or -1.0
        fpr = result["false_positive_rate"]
        onset = result["median_onset_delay_ms"]
        return (
            1.0 if result["meets_engineering_target"] else 0.0,
            balanced,
            sensitivity - (fpr if fpr is not None else 1.0),
            -(onset if onset is not None else 1.0e9),
        )

    return sorted(results, key=ranking, reverse=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-json", type=Path)
    parser.add_argument("--top", type=int, default=10)
    args = parser.parse_args()
    try:
        rows = read_labeled_csv(args.input)
    except (OSError, ValueError) as error:
        parser.error(str(error))

    results = sweep(rows)
    payload = {
        "warning": (
            "門檻只能代表這批資料；健康者模擬抖動不可宣稱為PD驗證。"
            "切換後750 ms不納入分類率，切換延遲另列。"
        ),
        "default_config": evaluate_config(rows, GateConfig()),
        "top_candidates": results[:max(1, args.top)],
    }
    output = json.dumps(payload, ensure_ascii=False, indent=2)
    print(output)
    if args.output_json:
        args.output_json.parent.mkdir(parents=True, exist_ok=True)
        args.output_json.write_text(output + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
