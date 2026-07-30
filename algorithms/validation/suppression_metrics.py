# -*- coding: utf-8 -*-
"""比較獨立IMU的Motor OFF／ON三軸4–6 Hz power與TPSR。"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
import statistics
from typing import Any

import numpy as np

from tremor_frequency_reference import analyze_tremor_frequency


WINDOW_SAMPLES = 400
STEP_SAMPLES = 50
RAW_LSB_PER_DPS = 16.0


def read_gyro_csv(path: Path) -> np.ndarray:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        fields = set(reader.fieldnames or [])
        dps_columns = {"gyro_x_dps", "gyro_y_dps", "gyro_z_dps"}
        raw_columns = {"gyro_x_raw", "gyro_y_raw", "gyro_z_raw"}
        if dps_columns <= fields:
            mode = "dps"
        elif raw_columns <= fields:
            mode = "raw"
        else:
            raise ValueError("需要三軸gyro_*_dps或gyro_*_raw欄位")

        rows = []
        for line_number, source in enumerate(reader, start=2):
            try:
                if mode == "dps":
                    values = [float(source[f"gyro_{axis}_dps"]) for axis in "xyz"]
                else:
                    values = [
                        int(source[f"gyro_{axis}_raw"]) / RAW_LSB_PER_DPS
                        for axis in "xyz"
                    ]
                if not all(math.isfinite(value) for value in values):
                    raise ValueError("含NaN或Infinity")
                rows.append(values)
            except ValueError as error:
                raise ValueError(f"第{line_number}列格式錯誤：{error}") from error
    return np.asarray(rows, dtype=float)


def summarize_gyro(gyro_xyz_dps: np.ndarray) -> dict[str, Any]:
    gyro = np.asarray(gyro_xyz_dps, dtype=float)
    if gyro.ndim != 2 or gyro.shape[1] != 3:
        raise ValueError("gyro必須是shape [樣本數, 3]")
    if len(gyro) < WINDOW_SAMPLES:
        raise ValueError("至少需要400筆、4秒資料")

    total_powers = []
    axis_powers = {"x": [], "y": [], "z": []}
    for start in range(0, len(gyro) - WINDOW_SAMPLES + 1, STEP_SAMPLES):
        window = gyro[start:start + WINDOW_SAMPLES]
        result = analyze_tremor_frequency(window)
        if not result["data_valid"]:
            continue
        total_powers.append(float(result["tremor_band_power_4_6_dps2"]))
        for axis in "xyz":
            axis_powers[axis].append(float(result["axis_power_4_6_dps2"][axis]))
    if not total_powers:
        raise ValueError("沒有有效的4秒分析視窗")

    total_median = statistics.median(total_powers)
    return {
        "window_count": len(total_powers),
        "median_power_4_6_dps2": total_median,
        "median_rms_4_6_dps": math.sqrt(max(total_median, 0.0)),
        "axis_median_power_4_6_dps2": {
            axis: statistics.median(values) for axis, values in axis_powers.items()
        },
    }


def _reduction_percent(off_value: float, on_value: float) -> float | None:
    if off_value <= 1.0e-12:
        return None
    return 100.0 * (off_value - on_value) / off_value


def compare_off_on(
    motor_off_gyro: np.ndarray, motor_on_gyro: np.ndarray
) -> dict[str, Any]:
    off = summarize_gyro(motor_off_gyro)
    on = summarize_gyro(motor_on_gyro)
    off_power = float(off["median_power_4_6_dps2"])
    on_power = float(on["median_power_4_6_dps2"])
    off_rms = float(off["median_rms_4_6_dps"])
    on_rms = float(on["median_rms_4_6_dps"])
    axis_reduction = {}
    increased_axes = []
    for axis in "xyz":
        axis_off = float(off["axis_median_power_4_6_dps2"][axis])
        axis_on = float(on["axis_median_power_4_6_dps2"][axis])
        axis_reduction[axis] = _reduction_percent(axis_off, axis_on)
        if axis_on > axis_off * 1.10 and axis_on - axis_off > 1.0e-6:
            increased_axes.append(axis)

    return {
        "motor_off": off,
        "motor_on": on,
        "tpsr_power_percent": _reduction_percent(off_power, on_power),
        "rms_amplitude_reduction_percent": _reduction_percent(off_rms, on_rms),
        "axis_power_reduction_percent": axis_reduction,
        "axis_transfer_warning": bool(increased_axes),
        "axes_with_more_power": increased_axes,
        "interpretation": (
            "正值代表4–6 Hz下降；負值代表Motor ON反而增加。"
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--motor-off", type=Path, required=True)
    parser.add_argument("--motor-on", type=Path, required=True)
    parser.add_argument("--output-json", type=Path)
    args = parser.parse_args()
    try:
        result = compare_off_on(
            read_gyro_csv(args.motor_off), read_gyro_csv(args.motor_on)
        )
    except (OSError, ValueError) as error:
        parser.error(str(error))
    output = json.dumps(result, ensure_ascii=False, indent=2)
    print(output)
    if args.output_json:
        args.output_json.parent.mkdir(parents=True, exist_ok=True)
        args.output_json.write_text(output + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
