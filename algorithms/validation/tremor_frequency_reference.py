# -*- coding: utf-8 -*-
"""SteadyHope App 用三軸 Gyro FFT／PSD 震顫頻率參考實作。

用途
----
輸入 4 秒、100 Hz 的 GyroX/Y/Z（共 400 筆，單位 deg/s），輸出：

1. 3–7 Hz 內的主要震顫候選頻率。
2. 4–6 Hz 頻帶強度。
3. 可供 App 畫圖的三軸合計 PSD。
4. 資料是否完整，以及主要頻率是否有足夠證據。

本程式不使用 eHWFLC-KF 的 freqEstimate，也不控制馬達。它是 App 顯示與
BLE 格式對接的參考版本。詳細規格見 handoff/TREMOR_FREQUENCY.md。

演算法採用單一 4 秒 Hann window 的 one-sided PSD。這保留 0.25 Hz 的 FFT
頻率間距，也容易在 Swift 重現。研究方法依據（4 秒、逐軸 PSD、三軸相加、
3–7 Hz peak）見：
https://www.nature.com/articles/s41531-025-01056-2

執行範例
--------
產生固定的 5 Hz 測試資料：
    python tremor_frequency_reference.py --write-example fixtures/tremor_5hz.csv

分析 CSV：
    python tremor_frequency_reference.py --input fixtures/tremor_5hz.csv

產生報告用 PNG：
    python tremor_frequency_reference.py --input fixtures/tremor_5hz.csv \
        --plot fixtures/tremor_5hz_plot.png

產生「頻率怎麼算」教學圖：
    python tremor_frequency_reference.py --input fixtures/tremor_5hz.csv \
        --explain-plot fixtures/tremor_5hz_explain.png
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from typing import Any

import numpy as np


FS_HZ = 100.0
WINDOW_SECONDS = 4.0
EXPECTED_SAMPLES = int(FS_HZ * WINDOW_SECONDS)

# 這三個是 prototype 的「畫面可信度」門檻，不是臨床診斷門檻。
# 後續要用實機與真實配戴資料校調。
MIN_VECTOR_RMS_DPS = 0.20
MIN_TREMOR_BAND_FRACTION = 0.30
MIN_PEAK_CONCENTRATION = 0.45


def _band_power(psd: np.ndarray, frequencies: np.ndarray,
                low_hz: float, high_hz: float) -> float:
    """以 PSD bins 加總得到頻帶 power，單位為 (deg/s)^2。"""
    mask = (frequencies >= low_hz) & (frequencies <= high_hz)
    if not np.any(mask):
        return 0.0
    df_hz = float(frequencies[1] - frequencies[0])
    return float(np.sum(psd[mask]) * df_hz)


def _one_sided_psd(gyro_xyz_dps: np.ndarray,
                   fs_hz: float) -> tuple[np.ndarray, np.ndarray]:
    """逐軸去平均、套 Hann window，計算 one-sided PSD。

    回傳
    ----
    frequencies:
        shape [n_frequency_bins]，單位 Hz。
    axis_psd:
        shape [n_frequency_bins, 3]，單位 (deg/s)^2/Hz。
    """
    centered = gyro_xyz_dps - np.mean(gyro_xyz_dps, axis=0, keepdims=True)
    window = np.hanning(centered.shape[0])
    spectrum = np.fft.rfft(centered * window[:, None], axis=0)
    axis_psd = (np.abs(spectrum) ** 2) / (fs_hz * np.sum(window ** 2))

    # 將雙邊頻譜的負頻率 power 合併到正頻率。DC 與 Nyquist 不加倍。
    if centered.shape[0] % 2 == 0:
        axis_psd[1:-1, :] *= 2.0
    else:
        axis_psd[1:, :] *= 2.0

    frequencies = np.fft.rfftfreq(centered.shape[0], d=1.0 / fs_hz)
    return frequencies, axis_psd


def analyze_tremor_frequency(
    gyro_xyz_dps: np.ndarray,
    *,
    fs_hz: float = FS_HZ,
    sample_tick_ms: np.ndarray | None = None,
    sequence: np.ndarray | None = None,
    sensor_valid: np.ndarray | None = None,
) -> dict[str, Any]:
    """分析一個固定 4 秒視窗。

    `dominant_frequency_hz` 只有在資料完整且週期證據足夠時才有數值。
    `candidate_frequency_hz` 永遠保留 3–7 Hz 內最高 PSD bin，供 debug 使用；
    App 不應在 `frequency_reliable == false` 時把 candidate 顯示給使用者。
    """
    gyro = np.asarray(gyro_xyz_dps, dtype=float)
    data_reasons: list[str] = []

    if gyro.ndim != 2 or gyro.shape[1:] != (3,):
        raise ValueError("gyro_xyz_dps 必須是 shape [樣本數, 3] 的陣列")
    if gyro.shape[0] != EXPECTED_SAMPLES:
        data_reasons.append(
            f"sample_count={gyro.shape[0]}，需要 {EXPECTED_SAMPLES} 筆"
        )
    if not np.all(np.isfinite(gyro)):
        data_reasons.append("GyroX/Y/Z 含 NaN 或 Infinity")

    n = gyro.shape[0]
    if sample_tick_ms is not None:
        timestamps = np.asarray(sample_tick_ms, dtype=float)
        if timestamps.shape != (n,) or not np.all(np.isfinite(timestamps)):
            data_reasons.append("sample_tick_ms 長度不符或含無效值")
        elif n >= 2:
            dt_ms = np.diff(timestamps)
            # 100 Hz 理論間隔 10 ms；容許 timer/紀錄造成的小幅誤差。
            if np.any(dt_ms <= 0.0) or np.max(np.abs(dt_ms - 10.0)) > 2.0:
                data_reasons.append("sample_tick_ms 不連續，疑似掉包或取樣率不穩")

    if sequence is not None:
        seq = np.asarray(sequence)
        if seq.shape != (n,):
            data_reasons.append("sequence 長度不符")
        elif n >= 2 and np.any(np.diff(seq.astype(np.int64)) != 1):
            data_reasons.append("sequence 不連續，BLE 資料可能掉包")

    if sensor_valid is not None:
        valid = np.asarray(sensor_valid)
        if valid.shape != (n,):
            data_reasons.append("sensor_valid 長度不符")
        elif not np.all(valid.astype(bool)):
            data_reasons.append("視窗內含 sensor_valid=0 的感測器資料")

    data_valid = len(data_reasons) == 0
    if not data_valid:
        return {
            "data_valid": False,
            "data_quality": "invalid",
            "data_reasons": data_reasons,
            "frequency_reliable": False,
            "frequency_reasons": ["資料不完整，因此不估算主要頻率"],
            "dominant_frequency_hz": None,
            "candidate_frequency_hz": None,
            "tremor_band_power_4_6_dps2": None,
            "tremor_band_rms_4_6_dps": None,
            "frequency_resolution_hz": fs_hz / max(n, 1),
            "frequencies_hz": [],
            "psd_sum_dps2_per_hz": [],
        }

    frequencies, axis_psd = _one_sided_psd(gyro, fs_hz)
    summed_psd = np.sum(axis_psd, axis=1)

    peak_mask = (frequencies >= 3.0) & (frequencies <= 7.0)
    peak_indices = np.flatnonzero(peak_mask)
    peak_index = int(peak_indices[np.argmax(summed_psd[peak_mask])])
    candidate_hz = float(frequencies[peak_index])

    power_0_5_15 = _band_power(summed_psd, frequencies, 0.5, 15.0)
    power_3_7 = _band_power(summed_psd, frequencies, 3.0, 7.0)
    power_4_6 = _band_power(summed_psd, frequencies, 4.0, 6.0)
    peak_power = _band_power(
        summed_psd, frequencies, candidate_hz - 0.5, candidate_hz + 0.5
    )

    centered = gyro - np.mean(gyro, axis=0, keepdims=True)
    vector_rms_dps = float(np.sqrt(np.mean(np.sum(centered ** 2, axis=1))))
    tremor_band_fraction = power_3_7 / (power_0_5_15 + 1.0e-12)
    peak_concentration = peak_power / (power_3_7 + 1.0e-12)

    frequency_reasons: list[str] = []
    if vector_rms_dps < MIN_VECTOR_RMS_DPS:
        frequency_reasons.append("整體 Gyro 訊號太小")
    if tremor_band_fraction < MIN_TREMOR_BAND_FRACTION:
        frequency_reasons.append("3–7 Hz 在 0.5–15 Hz 中所占比例不足")
    if peak_concentration < MIN_PEAK_CONCENTRATION:
        frequency_reasons.append("3–7 Hz 能量分散，沒有清楚的主要尖峰")

    frequency_reliable = len(frequency_reasons) == 0
    if frequency_reliable:
        frequency_reasons.append("3–7 Hz 內有足夠集中的週期訊號")

    axis_power_4_6 = [
        _band_power(axis_psd[:, axis], frequencies, 4.0, 6.0)
        for axis in range(3)
    ]

    return {
        "data_valid": True,
        "data_quality": "ok",
        "data_reasons": ["400 筆資料完整，時間與封包欄位通過檢查"],
        "frequency_reliable": frequency_reliable,
        "frequency_reasons": frequency_reasons,
        "dominant_frequency_hz": candidate_hz if frequency_reliable else None,
        "candidate_frequency_hz": candidate_hz,
        "tremor_band_power_4_6_dps2": power_4_6,
        "tremor_band_rms_4_6_dps": math.sqrt(max(power_4_6, 0.0)),
        "axis_power_4_6_dps2": {
            "x": axis_power_4_6[0],
            "y": axis_power_4_6[1],
            "z": axis_power_4_6[2],
        },
        "vector_rms_dps": vector_rms_dps,
        "tremor_band_fraction_3_7": tremor_band_fraction,
        "peak_concentration": peak_concentration,
        "frequency_resolution_hz": float(frequencies[1] - frequencies[0]),
        "frequencies_hz": frequencies.tolist(),
        "psd_sum_dps2_per_hz": summed_psd.tolist(),
    }


def make_example_5hz() -> dict[str, np.ndarray]:
    """建立可重現、無亂數的 4 秒三軸 5 Hz 測試資料。"""
    n = EXPECTED_SAMPLES
    t = np.arange(n) / FS_HZ
    return {
        "sequence": np.arange(n, dtype=int),
        "sample_tick_ms": np.arange(n, dtype=float) * 10.0,
        "gyro_x_dps": 10.0 * np.sin(2.0 * np.pi * 5.0 * t)
        + 0.20 * np.sin(2.0 * np.pi * 11.0 * t),
        "gyro_y_dps": 6.0 * np.sin(2.0 * np.pi * 5.0 * t + 0.8)
        + 0.15 * np.sin(2.0 * np.pi * 13.0 * t),
        "gyro_z_dps": 3.0 * np.sin(2.0 * np.pi * 5.0 * t + 1.6)
        + 1.0 * np.sin(2.0 * np.pi * 2.0 * t),
        "sensor_valid": np.ones(n, dtype=int),
        "motor_enabled": np.zeros(n, dtype=int),
    }


def make_example_noisy_5hz() -> dict[str, np.ndarray]:
    """建立較接近實測外觀、但仍含約 5 Hz 主成分的固定測試資料。

    刻意加入：
    - 4.6–5.4 Hz 間的緩慢頻率飄動。
    - 振幅隨時間改變。
    - 約 2 Hz 的自主動作。
    - GyroX 白雜訊與兩次短暫動作。

    Y、Z 固定為 0，讓圖與目前單軸 prototype 一致。這仍是合成資料，
    只用來驗證單軸 PSD 面對非完美正弦波時的行為。
    """
    n = EXPECTED_SAMPLES
    t = np.arange(n) / FS_HZ
    rng = np.random.default_rng(20260723)

    instantaneous_hz = (
        5.0
        + 0.32 * np.sin(2.0 * np.pi * 0.35 * t)
        + 0.10 * np.sin(2.0 * np.pi * 1.10 * t)
    )
    phase = 2.0 * np.pi * np.cumsum(instantaneous_hz) / FS_HZ
    amplitude = (
        7.5
        + 2.2 * np.sin(2.0 * np.pi * 0.25 * t)
        + 0.8 * np.sin(2.0 * np.pi * 0.80 * t)
    )

    # reach/stop 類型的短暫動作，不具有固定週期。
    transient_1 = 10.0 * np.exp(-0.5 * ((t - 1.55) / 0.07) ** 2)
    transient_2 = -8.0 * np.exp(-0.5 * ((t - 3.10) / 0.09) ** 2)

    gyro_x = (
        amplitude * np.sin(phase)
        + 4.0 * np.sin(2.0 * np.pi * 2.0 * t)
        + transient_1
        + transient_2
        + rng.normal(0.0, 1.4, n)
    )
    return {
        "sequence": np.arange(n, dtype=int),
        "sample_tick_ms": np.arange(n, dtype=float) * 10.0,
        "gyro_x_dps": gyro_x,
        "gyro_y_dps": np.zeros(n),
        "gyro_z_dps": np.zeros(n),
        "sensor_valid": np.ones(n, dtype=int),
        "motor_enabled": np.zeros(n, dtype=int),
    }


CSV_COLUMNS = [
    "sequence",
    "sample_tick_ms",
    "gyro_x_dps",
    "gyro_y_dps",
    "gyro_z_dps",
    "sensor_valid",
    "motor_enabled",
]


def _write_data_csv(data: dict[str, np.ndarray], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        for index in range(EXPECTED_SAMPLES):
            writer.writerow({
                column: data[column][index]
                for column in CSV_COLUMNS
            })


def write_example_csv(path: Path) -> None:
    _write_data_csv(make_example_5hz(), path)


def write_noisy_example_csv(path: Path) -> None:
    _write_data_csv(make_example_noisy_5hz(), path)


def read_input_csv(path: Path) -> dict[str, np.ndarray]:
    with path.open("r", newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    missing = [column for column in CSV_COLUMNS if column not in (rows[0] if rows else {})]
    if missing:
        raise ValueError(f"CSV 缺少欄位：{', '.join(missing)}")
    return {
        "sequence": np.asarray([int(row["sequence"]) for row in rows]),
        "sample_tick_ms": np.asarray([float(row["sample_tick_ms"]) for row in rows]),
        "gyro_x_dps": np.asarray([float(row["gyro_x_dps"]) for row in rows]),
        "gyro_y_dps": np.asarray([float(row["gyro_y_dps"]) for row in rows]),
        "gyro_z_dps": np.asarray([float(row["gyro_z_dps"]) for row in rows]),
        "sensor_valid": np.asarray([int(row["sensor_valid"]) for row in rows]),
        "motor_enabled": np.asarray([int(row["motor_enabled"]) for row in rows]),
    }


def _report_font(size: int, bold: bool = False):
    """尋找支援中文的字型；找不到時退回 Pillow 預設字型。"""
    from PIL import ImageFont

    candidates = [
        Path("C:/Windows/Fonts/msjhbd.ttc" if bold else "C:/Windows/Fonts/msjh.ttc"),
        Path("/System/Library/Fonts/PingFang.ttc"),
        Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def write_report_plot(data: dict[str, np.ndarray],
                      result: dict[str, Any],
                      path: Path) -> None:
    """輸出含三軸波形與三軸合計 PSD 的答辯用 PNG。"""
    from PIL import Image, ImageDraw

    if not result["data_valid"]:
        raise ValueError("輸入資料無效，無法產生分析圖")

    width, height = 1400, 920
    image = Image.new("RGB", (width, height), "#ffffff")
    draw = ImageDraw.Draw(image)
    title_font = _report_font(32, bold=True)
    heading_font = _report_font(22, bold=True)
    label_font = _report_font(17)
    small_font = _report_font(14)

    ink = "#1f2937"
    muted = "#596579"
    grid = "#d9dee7"
    axis_color = "#6b7280"
    series = {"X": "#d1495b", "Y": "#00798c", "Z": "#5b4b8a"}

    def draw_vertical_label(text: str, x: int, center_y: int) -> None:
        bbox = label_font.getbbox(text)
        text_width = bbox[2] - bbox[0] + 8
        text_height = bbox[3] - bbox[1] + 8
        layer = Image.new("RGBA", (text_width, text_height), (255, 255, 255, 0))
        layer_draw = ImageDraw.Draw(layer)
        layer_draw.text((4, 4 - bbox[1]), text, fill=ink, font=label_font)
        rotated = layer.rotate(90, expand=True)
        image.paste(rotated, (x, center_y - rotated.height // 2), rotated)

    if result["frequency_reliable"]:
        status = (
            f"主要頻率：{result['dominant_frequency_hz']:.2f} Hz    "
            f"4–6 Hz 強度：{result['tremor_band_rms_4_6_dps']:.2f} deg/s    "
            "判斷：頻率可信"
        )
        status_color = "#166534"
    else:
        status = "主要頻率：--    判斷：目前沒有清楚的主要震顫頻率"
        status_color = "#9a3412"
    draw.text((72, 78), status, fill=status_color, font=label_font)

    left, right = 105, 1335
    raw_top, raw_bottom = 145, 470
    psd_top, psd_bottom = 565, 850

    timestamp_s = (np.asarray(data["sample_tick_ms"], dtype=float)
                   - float(data["sample_tick_ms"][0])) / 1000.0
    raw_axes = {
        "X": np.asarray(data["gyro_x_dps"], dtype=float),
        "Y": np.asarray(data["gyro_y_dps"], dtype=float),
        "Z": np.asarray(data["gyro_z_dps"], dtype=float),
    }
    active_axes = {
        name: values
        for name, values in raw_axes.items()
        if float(np.max(np.abs(values))) > 1.0e-9
    }
    if not active_axes:
        active_axes = {"X": raw_axes["X"]}
    single_axis = len(active_axes) == 1
    plot_name = "GyroX 單軸" if single_axis and "X" in active_axes else "三軸 Gyro"
    draw.text(
        (70, 28),
        f"SteadyHope {plot_name}與 PSD 震顫頻率分析",
        fill=ink,
        font=title_font,
    )

    # ---------- 原始角速度 ----------
    draw.text((left, 112), f"最近 4 秒{plot_name}角速度",
              fill=ink, font=heading_font)
    raw_abs_max = max(float(np.max(np.abs(values))) for values in raw_axes.values())
    raw_limit = max(1.0, raw_abs_max * 1.12)

    def raw_x(value: float) -> float:
        return left + (value / WINDOW_SECONDS) * (right - left)

    def raw_y(value: float) -> float:
        return raw_top + ((raw_limit - value) / (2.0 * raw_limit)) * (raw_bottom - raw_top)

    for second in range(0, 5):
        x = raw_x(float(second))
        draw.line((x, raw_top, x, raw_bottom), fill=grid, width=1)
        draw.text((x - 8, raw_bottom + 8), str(second), fill=muted, font=small_font)
    for fraction in (-1.0, -0.5, 0.0, 0.5, 1.0):
        value = fraction * raw_limit
        y = raw_y(value)
        draw.line((left, y, right, y), fill=grid, width=1)
        draw.text((left - 10, y), f"{value:.1f}", fill=muted,
                  font=small_font, anchor="rm")
    draw.rectangle((left, raw_top, right, raw_bottom), outline=axis_color, width=2)
    draw.text((left + 560, raw_bottom + 35), "時間 (s)", fill=ink, font=label_font)
    draw_vertical_label("角速度 (deg/s)", 7, (raw_top + raw_bottom) // 2)

    legend_x = right - 185
    for index, (name, values) in enumerate(active_axes.items()):
        points = [
            (raw_x(float(t)), raw_y(float(value)))
            for t, value in zip(timestamp_s, values)
        ]
        draw.line(points, fill=series[name], width=3)
        legend_y = raw_top + 18 + index * 28
        draw.line((legend_x, legend_y + 8, legend_x + 30, legend_y + 8),
                  fill=series[name], width=4)
        draw.text((legend_x + 38, legend_y), f"Gyro{name}",
                  fill=ink, font=small_font)

    # ---------- PSD ----------
    psd_heading = (
        "GyroX 單軸 PSD（各頻率的震動強度）"
        if single_axis and "X" in active_axes
        else "三軸合計 PSD（各頻率的震動強度）"
    )
    draw.text((left, 525), psd_heading,
              fill=ink, font=heading_font)
    frequencies = np.asarray(result["frequencies_hz"], dtype=float)
    psd = np.asarray(result["psd_sum_dps2_per_hz"], dtype=float)
    visible = (frequencies >= 0.0) & (frequencies <= 15.0)
    visible_f = frequencies[visible]
    visible_psd = psd[visible]
    psd_max = max(1.0e-9, float(np.max(visible_psd)) * 1.12)

    def psd_x(value: float) -> float:
        return left + (value / 15.0) * (right - left)

    def psd_y(value: float) -> float:
        return psd_bottom - (value / psd_max) * (psd_bottom - psd_top)

    # 淺色範圍先畫，4–6 Hz 使用較明顯的第二層。
    draw.rectangle(
        (psd_x(3.0), psd_top, psd_x(7.0), psd_bottom),
        fill="#edf6ff",
    )
    draw.rectangle(
        (psd_x(4.0), psd_top, psd_x(6.0), psd_bottom),
        fill="#ffe9d6",
    )
    for hz in range(0, 16):
        x = psd_x(float(hz))
        draw.line((x, psd_top, x, psd_bottom), fill=grid, width=1)
        if hz % 2 == 0:
            draw.text((x - 8, psd_bottom + 8), str(hz),
                      fill=muted, font=small_font)
    for fraction in (0.0, 0.25, 0.5, 0.75, 1.0):
        value = fraction * psd_max
        y = psd_y(value)
        draw.line((left, y, right, y), fill=grid, width=1)
        draw.text((left - 10, y), f"{value:.1f}", fill=muted,
                  font=small_font, anchor="rm")
    draw.rectangle((left, psd_top, right, psd_bottom), outline=axis_color, width=2)

    # FFT 是每 0.25 Hz 一格的離散結果；用柱狀表示，避免看起來像連續山坡。
    bar_half_width = max(
        2.0,
        (psd_x(float(frequencies[1])) - psd_x(float(frequencies[0]))) * 0.36,
    )
    for freq, value in zip(visible_f, visible_psd):
        x = psd_x(float(freq))
        draw.rectangle(
            (x - bar_half_width, psd_y(float(value)),
             x + bar_half_width, psd_bottom),
            fill="#1d4ed8",
        )

    peak_hz = float(result["candidate_frequency_hz"])
    peak_index = int(np.argmin(np.abs(frequencies - peak_hz)))
    peak_x = psd_x(peak_hz)
    peak_y = psd_y(float(psd[peak_index]))
    draw.line((peak_x, psd_top, peak_x, psd_bottom),
              fill="#b91c1c", width=2)
    draw.ellipse((peak_x - 6, peak_y - 6, peak_x + 6, peak_y + 6),
                 fill="#b91c1c")
    draw.text(
        (min(peak_x + 12, right - 160), max(psd_top + 8, peak_y - 32)),
        f"peak {peak_hz:.2f} Hz",
        fill="#991b1b",
        font=label_font,
    )
    draw.text((left + 560, psd_bottom + 35), "頻率 (Hz)",
              fill=ink, font=label_font)
    draw_vertical_label("PSD ((deg/s)²/Hz)", 7, (psd_top + psd_bottom) // 2)
    draw.text((psd_x(3.0) + 8, psd_top + 8), "3–7 Hz 搜尋範圍",
              fill="#1e3a5f", font=small_font)
    draw.text((psd_x(4.0) + 8, psd_top + 32), "4–6 Hz 專題頻帶",
              fill="#8a3c00", font=small_font)
    draw.text((right - 195, psd_bottom - 25), "每根柱 = 0.25 Hz",
              fill=muted, font=small_font)

    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG")


def write_single_axis_report_plot(data: dict[str, np.ndarray],
                                  result: dict[str, Any],
                                  path: Path) -> None:
    """輸出強調「同一段 GyroX 如何得到頻率」的單軸報告圖。"""
    from PIL import Image, ImageDraw

    if not result["data_valid"]:
        raise ValueError("輸入資料無效，無法產生單軸分析圖")

    width, height = 1400, 940
    image = Image.new("RGB", (width, height), "#ffffff")
    draw = ImageDraw.Draw(image)
    title_font = _report_font(31, bold=True)
    heading_font = _report_font(22, bold=True)
    result_font = _report_font(27, bold=True)
    label_font = _report_font(17)
    small_font = _report_font(14)

    ink = "#1f2937"
    muted = "#596579"
    grid = "#d9dee7"
    axis_color = "#6b7280"
    red = "#d1495b"
    blue = "#1d4ed8"
    peak_hz = float(result["candidate_frequency_hz"])

    draw.text((70, 25), "GyroX 單軸：上方波形如何算出下方頻率",
              fill=ink, font=title_font)
    draw.text(
        (72, 72),
        f"輸出：主要震顫頻率 = {peak_hz:.2f} Hz",
        fill="#166534" if result["frequency_reliable"] else "#9a3412",
        font=result_font,
    )
    draw.text(
        (720, 80),
        "輸入為同一批 400 筆 GyroX（100 Hz、共 4 秒）",
        fill=muted,
        font=label_font,
    )

    left, right = 105, 1335
    raw_top, raw_bottom = 155, 410

    # ---------- ① 同一批 GyroX ----------
    draw.text((left, 118), "① 輸入：400筆 GyroX 角速度",
              fill=ink, font=heading_font)
    timestamp_s = (np.asarray(data["sample_tick_ms"], dtype=float)
                   - float(data["sample_tick_ms"][0])) / 1000.0
    gyro_x = np.asarray(data["gyro_x_dps"], dtype=float)
    raw_limit = max(1.0, float(np.max(np.abs(gyro_x))) * 1.12)

    def raw_x(value: float) -> float:
        return left + (value / WINDOW_SECONDS) * (right - left)

    def raw_y(value: float) -> float:
        return raw_top + ((raw_limit - value) / (2.0 * raw_limit)) * (
            raw_bottom - raw_top
        )

    for second in range(5):
        x = raw_x(float(second))
        draw.line((x, raw_top, x, raw_bottom), fill=grid, width=1)
        draw.text((x, raw_bottom + 9), str(second),
                  fill=muted, font=small_font, anchor="ma")
    for fraction in (-1.0, -0.5, 0.0, 0.5, 1.0):
        value = fraction * raw_limit
        y = raw_y(value)
        draw.line((left, y, right, y), fill=grid, width=1)
        draw.text((left - 10, y), f"{value:.1f}",
                  fill=muted, font=small_font, anchor="rm")
    draw.rectangle((left, raw_top, right, raw_bottom),
                   outline=axis_color, width=2)
    draw.line(
        [(raw_x(float(t)), raw_y(float(value)))
         for t, value in zip(timestamp_s, gyro_x)],
        fill=red,
        width=3,
    )
    draw.text((left + 575, raw_bottom + 34), "時間 (s)",
              fill=ink, font=label_font)
    draw.text((18, (raw_top + raw_bottom) // 2 - 10),
              "GyroX", fill=ink, font=label_font)
    draw.text((18, (raw_top + raw_bottom) // 2 + 17),
              "(deg/s)", fill=muted, font=small_font)

    # 中間直接標示上下圖使用同一批資料。
    process_y = 488
    draw.line((250, process_y, 1140, process_y), fill="#64748b", width=3)
    draw.polygon(
        [(1140, process_y), (1124, process_y - 8), (1124, process_y + 8)],
        fill="#64748b",
    )
    process_text = "同一批400筆 GyroX → FFT換成各頻率的震動強度 → 在3–7 Hz找最高柱"
    text_bbox = draw.textbbox((0, 0), process_text, font=label_font)
    text_width = text_bbox[2] - text_bbox[0]
    draw.rectangle(
        (700 - text_width / 2 - 12, process_y - 18,
         700 + text_width / 2 + 12, process_y + 18),
        fill="#ffffff",
    )
    draw.text((700, process_y), process_text,
              fill=ink, font=label_font, anchor="mm")

    # ---------- ② 只放 3–7 Hz，並把頻率逐筆列出 ----------
    chart_left, chart_right = 105, 950
    psd_top, psd_bottom = 585, 855
    table_left = 1015
    draw.text((chart_left, 535), "② 輸出：3–7 Hz各頻率的震動強度",
              fill=ink, font=heading_font)

    frequencies = np.asarray(result["frequencies_hz"], dtype=float)
    psd = np.asarray(result["psd_sum_dps2_per_hz"], dtype=float)
    search = (frequencies >= 3.0) & (frequencies <= 7.0)
    search_f = frequencies[search]
    search_psd = psd[search]
    psd_max = max(1.0e-9, float(np.max(search_psd)) * 1.15)

    def psd_x(value: float) -> float:
        return chart_left + ((value - 3.0) / 4.0) * (chart_right - chart_left)

    def psd_y(value: float) -> float:
        return psd_bottom - (value / psd_max) * (psd_bottom - psd_top)

    draw.rectangle((psd_x(4.0), psd_top, psd_x(6.0), psd_bottom),
                   fill="#fff0df")
    for half_hz in np.arange(3.0, 7.01, 0.5):
        x = psd_x(float(half_hz))
        draw.line((x, psd_top, x, psd_bottom), fill=grid, width=1)
        draw.text((x, psd_bottom + 8), f"{half_hz:.1f}",
                  fill=muted, font=small_font, anchor="ma")
    for fraction in (0.0, 0.5, 1.0):
        value = fraction * psd_max
        y = psd_y(value)
        draw.line((chart_left, y, chart_right, y), fill=grid, width=1)
        draw.text((chart_left - 10, y), f"{value:.1f}",
                  fill=muted, font=small_font, anchor="rm")
    draw.rectangle((chart_left, psd_top, chart_right, psd_bottom),
                   outline=axis_color, width=2)

    bin_width_px = psd_x(3.25) - psd_x(3.0)
    bar_half_width = bin_width_px * 0.34
    for freq, value in zip(search_f, search_psd):
        x = psd_x(float(freq))
        fill = "#b91c1c" if math.isclose(float(freq), peak_hz) else blue
        draw.rectangle(
            (x - bar_half_width, psd_y(float(value)),
             x + bar_half_width, psd_bottom),
            fill=fill,
        )
    peak_index = int(np.argmin(np.abs(frequencies - peak_hz)))
    draw.text(
        (psd_x(peak_hz), max(psd_top + 8, psd_y(float(psd[peak_index])) - 28)),
        f"最高：{peak_hz:.2f} Hz",
        fill="#991b1b",
        font=label_font,
        anchor="ma",
    )
    draw.text((chart_left + 360, psd_bottom + 42), "頻率 (Hz)",
              fill=ink, font=label_font)
    draw.text((13, (psd_top + psd_bottom) // 2),
              "震動強度\n(PSD)", fill=ink, font=label_font, spacing=3)

    # 頻率單獨列出：最高點前後各兩格，每格 0.25 Hz。
    draw.text((table_left, 535), "最高點附近的頻率列表",
              fill=ink, font=heading_font)
    draw.text((table_left, 574), "頻率 (Hz)", fill=muted, font=small_font)
    draw.text((table_left + 145, 574), "震動強度", fill=muted, font=small_font)
    nearby = np.flatnonzero(
        (frequencies >= peak_hz - 0.5) & (frequencies <= peak_hz + 0.5)
    )
    row_height = 46
    for row, index in enumerate(nearby):
        y = 610 + row * row_height
        is_peak = index == peak_index
        if is_peak:
            draw.rectangle((table_left - 10, y - 7, 1325, y + 33),
                           fill="#fee2e2")
        draw.text((table_left, y), f"{frequencies[index]:.2f}",
                  fill="#991b1b" if is_peak else ink, font=label_font)
        draw.text((table_left + 145, y), f"{psd[index]:.2f}",
                  fill="#991b1b" if is_peak else ink, font=label_font)
        if is_peak:
            draw.text((table_left + 245, y), "← 最高，答案",
                      fill="#991b1b", font=label_font)
    draw.text((table_left, 850), "頻率間距：0.25 Hz",
              fill=muted, font=small_font)

    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG")


def write_frequency_explain_plot(data: dict[str, np.ndarray],
                                 result: dict[str, Any],
                                 path: Path) -> None:
    """輸出用週期與 PSD 兩種角度解釋頻率的教學 PNG。"""
    from PIL import Image, ImageDraw

    if not result["data_valid"]:
        raise ValueError("輸入資料無效，無法產生頻率教學圖")

    width, height = 1400, 980
    image = Image.new("RGB", (width, height), "#ffffff")
    draw = ImageDraw.Draw(image)
    title_font = _report_font(32, bold=True)
    heading_font = _report_font(23, bold=True)
    label_font = _report_font(18)
    small_font = _report_font(14)
    formula_font = _report_font(22, bold=True)

    ink = "#1f2937"
    muted = "#596579"
    grid = "#d9dee7"
    axis_color = "#6b7280"
    red = "#d1495b"
    blue = "#1d4ed8"

    draw.text((70, 28), "震顫頻率是怎麼算出來的？",
              fill=ink, font=title_font)
    draw.text(
        (72, 78),
        "同一個答案可用「時域數週期」理解，也可用「FFT／PSD找最高點」自動計算。",
        fill=muted,
        font=label_font,
    )

    left, right = 105, 1335
    time_top, time_bottom = 155, 405
    psd_top, psd_bottom = 600, 900

    # ---------- ① 時域：一秒數週期 ----------
    draw.text((left, 115), "① 先看一秒波形：一秒內重複幾次，就是幾 Hz",
              fill=ink, font=heading_font)
    timestamp_s = (np.asarray(data["sample_tick_ms"], dtype=float)
                   - float(data["sample_tick_ms"][0])) / 1000.0
    gyro_x = np.asarray(data["gyro_x_dps"], dtype=float)
    one_second = timestamp_s <= 1.0
    time_1s = timestamp_s[one_second]
    gyro_1s = gyro_x[one_second]
    raw_limit = max(1.0, float(np.max(np.abs(gyro_1s))) * 1.45)

    def time_x(value: float) -> float:
        return left + value * (right - left)

    def time_y(value: float) -> float:
        return time_top + ((raw_limit - value) / (2.0 * raw_limit)) * (
            time_bottom - time_top
        )

    # 每 0.2 秒是一個 5 Hz 週期；交錯底色讓五段容易數。
    for cycle in range(5):
        x0 = time_x(cycle * 0.2)
        x1 = time_x((cycle + 1) * 0.2)
        if cycle % 2 == 0:
            draw.rectangle((x0, time_top, x1, time_bottom), fill="#f4f8fc")
        draw.line((x0, time_top, x0, time_bottom), fill="#9aa6b6", width=1)
        draw.text(
            ((x0 + x1) / 2, time_bottom - 26),
            f"第 {cycle + 1} 次",
            fill=muted,
            font=small_font,
            anchor="ma",
        )
    draw.line((right, time_top, right, time_bottom), fill="#9aa6b6", width=1)

    for tenth in range(0, 11):
        value = tenth / 10.0
        x = time_x(value)
        draw.line((x, time_bottom, x, time_bottom + 6), fill=axis_color, width=1)
        if tenth % 2 == 0:
            draw.text((x, time_bottom + 10), f"{value:.1f}",
                      fill=muted, font=small_font, anchor="ma")
    for value in (-10.0, 0.0, 10.0):
        y = time_y(value)
        draw.line((left, y, right, y), fill=grid, width=1)
        draw.text((left - 10, y), f"{value:.0f}", fill=muted,
                  font=small_font, anchor="rm")
    draw.rectangle((left, time_top, right, time_bottom),
                   outline=axis_color, width=2)
    points = [
        (time_x(float(t)), time_y(float(value)))
        for t, value in zip(time_1s, gyro_1s)
    ]
    draw.line(points, fill=red, width=4)
    draw.text((left + 575, time_bottom + 34), "時間 (s)",
              fill=ink, font=label_font)
    draw.text((18, (time_top + time_bottom) // 2 - 10),
              "GyroX", fill=ink, font=label_font)
    draw.text((25, (time_top + time_bottom) // 2 + 18),
              "(deg/s)", fill=muted, font=small_font)

    # 標出相鄰兩個 peak 的距離 T = 0.20 秒。
    arrow_y = time_y(12.0)
    peak_1_x, peak_2_x = time_x(0.05), time_x(0.25)
    draw.line((peak_1_x, arrow_y, peak_2_x, arrow_y), fill="#9a3412", width=3)
    draw.polygon(
        [(peak_1_x, arrow_y), (peak_1_x + 12, arrow_y - 6),
         (peak_1_x + 12, arrow_y + 6)],
        fill="#9a3412",
    )
    draw.polygon(
        [(peak_2_x, arrow_y), (peak_2_x - 12, arrow_y - 6),
         (peak_2_x - 12, arrow_y + 6)],
        fill="#9a3412",
    )
    draw.text(((peak_1_x + peak_2_x) / 2, arrow_y - 32),
              "一個週期 T = 0.20 秒", fill="#9a3412",
              font=label_font, anchor="ma")

    draw.text(
        (left + 270, 485),
        "頻率 f = 1 ÷ 週期 T = 1 ÷ 0.20 = 5 Hz",
        fill="#166534",
        font=formula_font,
    )

    # ---------- ② FFT／PSD：由程式找最高頻率 ----------
    draw.text((left, 555), "② 程式用 FFT 拆開各種頻率，再找 PSD 最高點",
              fill=ink, font=heading_font)
    frequencies = np.asarray(result["frequencies_hz"], dtype=float)
    psd = np.asarray(result["psd_sum_dps2_per_hz"], dtype=float)
    visible = (frequencies >= 0.0) & (frequencies <= 15.0)
    visible_f = frequencies[visible]
    visible_psd = psd[visible]
    psd_max = max(1.0e-9, float(np.max(visible_psd)) * 1.12)

    def psd_x(value: float) -> float:
        return left + (value / 15.0) * (right - left)

    def psd_y(value: float) -> float:
        return psd_bottom - (value / psd_max) * (psd_bottom - psd_top)

    draw.rectangle((psd_x(3.0), psd_top, psd_x(7.0), psd_bottom),
                   fill="#edf6ff")
    draw.rectangle((psd_x(4.0), psd_top, psd_x(6.0), psd_bottom),
                   fill="#ffe9d6")
    for hz in range(0, 16):
        x = psd_x(float(hz))
        draw.line((x, psd_top, x, psd_bottom), fill=grid, width=1)
        if hz % 2 == 0:
            draw.text((x, psd_bottom + 9), str(hz),
                      fill=muted, font=small_font, anchor="ma")
    for fraction in (0.0, 0.5, 1.0):
        value = fraction * psd_max
        y = psd_y(value)
        draw.line((left, y, right, y), fill=grid, width=1)
        draw.text((left - 10, y), f"{value:.0f}", fill=muted,
                  font=small_font, anchor="rm")
    draw.rectangle((left, psd_top, right, psd_bottom),
                   outline=axis_color, width=2)
    # 每根柱是一個 FFT frequency bin，本例間距為 0.25 Hz。
    bar_half_width = max(
        2.0,
        (psd_x(float(frequencies[1])) - psd_x(float(frequencies[0]))) * 0.36,
    )
    for freq, value in zip(visible_f, visible_psd):
        x = psd_x(float(freq))
        draw.rectangle(
            (x - bar_half_width, psd_y(float(value)),
             x + bar_half_width, psd_bottom),
            fill=blue,
        )

    peak_hz = float(result["candidate_frequency_hz"])
    peak_index = int(np.argmin(np.abs(frequencies - peak_hz)))
    peak_x = psd_x(peak_hz)
    peak_y = psd_y(float(psd[peak_index]))
    draw.line((peak_x, psd_top, peak_x, psd_bottom),
              fill="#b91c1c", width=2)
    draw.ellipse((peak_x - 7, peak_y - 7, peak_x + 7, peak_y + 7),
                 fill="#b91c1c")
    draw.text((peak_x + 15, peak_y - 16),
              f"3–7 Hz 內最高點 = {peak_hz:.2f} Hz",
              fill="#991b1b", font=label_font)
    draw.text((psd_x(3.0) + 8, psd_top + 8),
              "藍底：3–7 Hz 搜尋範圍", fill="#1e3a5f", font=small_font)
    draw.text((psd_x(4.0) + 8, psd_top + 33),
              "橘底：4–6 Hz 專題頻帶", fill="#8a3c00", font=small_font)
    draw.text((right - 380, psd_top + 10),
              "實際程式：X、Y、Z 各算 PSD 後相加",
              fill=muted, font=small_font)
    draw.text((right - 195, psd_bottom - 25), "每根柱 = 0.25 Hz",
              fill=muted, font=small_font)
    draw.text((left + 575, psd_bottom + 34), "頻率 (Hz)",
              fill=ink, font=label_font)
    draw.text((11, (psd_top + psd_bottom) // 2 - 10),
              "PSD", fill=ink, font=label_font)

    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG")


def write_hann_window_explain_plot(path: Path) -> None:
    """用「片段循環播放的接縫」解釋 Hann window。"""
    from PIL import Image, ImageDraw

    width, height = 1400, 900
    image = Image.new("RGB", (width, height), "#ffffff")
    draw = ImageDraw.Draw(image)
    title_font = _report_font(31, bold=True)
    heading_font = _report_font(22, bold=True)
    label_font = _report_font(17)
    small_font = _report_font(14)

    ink = "#1f2937"
    muted = "#596579"
    grid = "#d9dee7"
    axis_color = "#6b7280"
    red = "#d1495b"
    green = "#15803d"
    blue = "#1d4ed8"

    # 故意截取不是整數週期的 5.3 Hz，讓片段首尾不相等。
    fs_hz = 100.0
    n = 100
    t = np.arange(n) / fs_hz
    raw = 8.0 * np.sin(2.0 * np.pi * 5.3 * t)
    hann = np.hanning(n)
    softened = raw * hann
    raw_repeat = np.concatenate((raw, raw))
    softened_repeat = np.concatenate((softened, softened))
    repeat_t = np.arange(2 * n) / fs_hz

    raw_centered = raw - np.mean(raw)
    raw_fft = np.abs(np.fft.rfft(raw_centered))
    hann_fft = np.abs(np.fft.rfft(raw_centered * hann))
    frequencies = np.fft.rfftfreq(n, d=1.0 / fs_hz)
    raw_fft /= np.max(raw_fft)
    hann_fft /= np.max(hann_fft)

    draw.text((70, 25), "Hann window：像把一段聲音的頭尾「淡入、淡出」",
              fill=ink, font=title_font)
    draw.text(
        (72, 75),
        "FFT會把截取的片段想像成不斷循環播放；接縫突然跳動，就會被誤認成額外頻率。",
        fill=muted,
        font=label_font,
    )

    columns = [
        {
            "left": 75,
            "right": 665,
            "title": "不用 Hann：尾巴直接接回開頭",
            "signal": raw_repeat,
            "fft": raw_fft,
            "color": red,
            "note": "接縫突然跳一下 → FFT出現較多假的頻率",
            "note_color": "#b91c1c",
        },
        {
            "left": 735,
            "right": 1325,
            "title": "使用 Hann：頭尾逐漸壓到 0",
            "signal": softened_repeat,
            "fft": hann_fft,
            "color": green,
            "note": "接縫都回到 0 → 頻率能量集中在5–6 Hz附近",
            "note_color": "#166534",
        },
    ]

    wave_top, wave_bottom = 165, 415
    fft_top, fft_bottom = 560, 805

    for column in columns:
        left = column["left"]
        right = column["right"]
        draw.text((left, 120), column["title"],
                  fill=ink, font=heading_font)

        def wave_x(value: float) -> float:
            return left + (value / 2.0) * (right - left)

        def wave_y(value: float) -> float:
            return wave_top + ((10.0 - value) / 20.0) * (
                wave_bottom - wave_top
            )

        for second in (0.0, 0.5, 1.0, 1.5, 2.0):
            x = wave_x(second)
            draw.line((x, wave_top, x, wave_bottom), fill=grid, width=1)
            draw.text((x, wave_bottom + 8), f"{second:.1f}",
                      fill=muted, font=small_font, anchor="ma")
        for value in (-8.0, 0.0, 8.0):
            y = wave_y(value)
            draw.line((left, y, right, y), fill=grid, width=1)
        draw.rectangle((left, wave_top, right, wave_bottom),
                       outline=axis_color, width=2)
        draw.line(
            [(wave_x(float(time)), wave_y(float(value)))
             for time, value in zip(repeat_t, column["signal"])],
            fill=column["color"],
            width=3,
        )

        boundary_x = wave_x(1.0)
        draw.line((boundary_x, wave_top, boundary_x, wave_bottom),
                  fill="#7c2d12", width=3)
        if left < 100:
            jump_top = wave_y(float(raw[-1]))
            jump_bottom = wave_y(float(raw[0]))
            draw.line((boundary_x, jump_top, boundary_x, jump_bottom),
                      fill="#b91c1c", width=7)
            draw.text((boundary_x + 12, wave_top + 10), "接縫跳動",
                      fill="#b91c1c", font=label_font)
        else:
            draw.ellipse((boundary_x - 6, wave_y(0.0) - 6,
                          boundary_x + 6, wave_y(0.0) + 6),
                         fill="#166534")
            draw.text((boundary_x + 12, wave_top + 10), "接縫回到 0",
                      fill="#166534", font=label_font)
        draw.text(((left + right) / 2, wave_bottom + 37), "時間 (s)",
                  fill=ink, font=label_font, anchor="ma")
        draw.text((left, 465), column["note"],
                  fill=column["note_color"], font=label_font)

        # FFT僅顯示0–15 Hz，相對強度便於比較頻率擴散。
        draw.text((left, 515), "FFT結果：各頻率的相對強度",
                  fill=ink, font=heading_font)

        def fft_x(value: float) -> float:
            return left + (value / 15.0) * (right - left)

        def fft_y(value: float) -> float:
            return fft_bottom - value * (fft_bottom - fft_top)

        for hz in range(0, 16, 3):
            x = fft_x(float(hz))
            draw.line((x, fft_top, x, fft_bottom), fill=grid, width=1)
            draw.text((x, fft_bottom + 8), str(hz),
                      fill=muted, font=small_font, anchor="ma")
        for fraction in (0.0, 0.5, 1.0):
            y = fft_y(fraction)
            draw.line((left, y, right, y), fill=grid, width=1)
        draw.rectangle((left, fft_top, right, fft_bottom),
                       outline=axis_color, width=2)
        visible = frequencies <= 15.0
        bin_width = fft_x(1.0) - fft_x(0.0)
        for freq, value in zip(frequencies[visible], column["fft"][visible]):
            x = fft_x(float(freq))
            draw.rectangle(
                (x - bin_width * 0.31, fft_y(float(value)),
                 x + bin_width * 0.31, fft_bottom),
                fill=blue if left < 100 else green,
            )
        draw.text(((left + right) / 2, fft_bottom + 36), "頻率 (Hz)",
                  fill=ink, font=label_font, anchor="ma")

    draw.text(
        (700, 865),
        "重點：Hann不是找頻率；它只是先把資料頭尾變柔和，避免切片接縫製造假頻率。",
        fill="#166534",
        font=heading_font,
        anchor="mm",
    )

    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG")


def _analyze_csv(path: Path) -> dict[str, Any]:
    data = read_input_csv(path)
    gyro = np.column_stack((
        data["gyro_x_dps"],
        data["gyro_y_dps"],
        data["gyro_z_dps"],
    ))
    return analyze_tremor_frequency(
        gyro,
        sample_tick_ms=data["sample_tick_ms"],
        sequence=data["sequence"],
        sensor_valid=data["sensor_valid"],
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="要分析的 400 筆 CSV")
    parser.add_argument("--write-example", type=Path, help="輸出固定 5 Hz 測試 CSV")
    parser.add_argument("--write-noisy-example", type=Path,
                        help="輸出含雜訊、自主動作與頻率飄動的約 5 Hz 測試 CSV")
    parser.add_argument("--output-json", type=Path, help="另存完整 PSD JSON")
    parser.add_argument("--plot", type=Path, help="輸出含三軸波形與 PSD 的 PNG")
    parser.add_argument("--explain-plot", type=Path,
                        help="輸出解釋頻率計算方式的教學 PNG")
    parser.add_argument("--hann-plot", type=Path,
                        help="輸出具象解釋 Hann window 的教學 PNG")
    args = parser.parse_args()

    if args.write_example is not None:
        write_example_csv(args.write_example)
        print(f"已產生測試資料：{args.write_example}")
    if args.write_noisy_example is not None:
        write_noisy_example_csv(args.write_noisy_example)
        print(f"已產生混合雜訊測試資料：{args.write_noisy_example}")
    if args.hann_plot is not None:
        write_hann_window_explain_plot(args.hann_plot)
        print(f"已輸出 Hann window 教學圖：{args.hann_plot}")

    if args.input is not None:
        data = read_input_csv(args.input)
        gyro = np.column_stack((
            data["gyro_x_dps"],
            data["gyro_y_dps"],
            data["gyro_z_dps"],
        ))
        result = analyze_tremor_frequency(
            gyro,
            sample_tick_ms=data["sample_tick_ms"],
            sequence=data["sequence"],
            sensor_valid=data["sensor_valid"],
        )
        output = json.dumps(result, ensure_ascii=False, indent=2)
        if args.output_json is not None:
            args.output_json.parent.mkdir(parents=True, exist_ok=True)
            args.output_json.write_text(output + "\n", encoding="utf-8")
            print(f"已輸出分析結果：{args.output_json}")

        summary = {
            key: result[key]
            for key in (
                "data_valid",
                "data_reasons",
                "frequency_reliable",
                "frequency_reasons",
                "dominant_frequency_hz",
                "candidate_frequency_hz",
                "tremor_band_power_4_6_dps2",
                "tremor_band_rms_4_6_dps",
                "axis_power_4_6_dps2",
                "frequency_resolution_hz",
            )
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        if args.plot is not None:
            nonzero_axes = sum(
                float(np.max(np.abs(data[column]))) > 1.0e-9
                for column in ("gyro_x_dps", "gyro_y_dps", "gyro_z_dps")
            )
            if nonzero_axes == 1 and float(np.max(np.abs(data["gyro_x_dps"]))) > 1.0e-9:
                write_single_axis_report_plot(data, result, args.plot)
            else:
                write_report_plot(data, result, args.plot)
            print(f"已輸出分析圖：{args.plot}")
        if args.explain_plot is not None:
            write_frequency_explain_plot(data, result, args.explain_plot)
            print(f"已輸出頻率教學圖：{args.explain_plot}")
    elif args.plot is not None or args.explain_plot is not None:
        parser.error("--plot／--explain-plot 必須搭配 --input")

    if (args.input is None and args.write_example is None
            and args.write_noisy_example is None and args.hann_plot is None):
        parser.print_help()
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
