# -*- coding: utf-8 -*-
"""7/30進度報告的離線備援demo；只讀已提交的驗收結果。"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
GATING_DIR = REPO_ROOT / "algorithms" / "handoff" / "test_vectors"
FIXTURE_DIR = REPO_ROOT / "algorithms" / "validation" / "fixtures"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


def find_row(rows: list[dict[str, str]], **conditions: str) -> dict[str, str]:
    for row in rows:
        if all(row[key] == value for key, value in conditions.items()):
            return row
    raise ValueError(f"找不到資料列：{conditions}")


def main() -> int:
    print("=== SteadyHope 7/30 離線備援 demo ===")
    print("注意：以下為PC reference／合成資料，不是人體抑震率。\n")

    print("[1] 1～8 Hz gating預期結果（15 deg/s、100 Hz）")
    frequency_rows = read_csv(GATING_DIR / "gating_frequency" / "expected_results.csv")
    print(" Hz | enabled應否開啟 | 啟動延遲(ms) | 顫抖段開啟筆數")
    for row in frequency_rows:
        expected = "1" if row["should_enable"] == "1" else "0"
        print(
            f" {int(row['frequency_hz']):>2} | {expected:^15} | "
            f"{row['delay_from_tone_start_ms']:^12} | "
            f"{row['enabled_samples_during_400_sample_tone']:>6}/400"
        )

    print("\n[2] 強健性模擬抓到的邊界")
    amplitude_rows = read_csv(GATING_DIR / "gating_robustness" / "amplitude_sweep.csv")
    seven_15 = find_row(
        amplitude_rows, frequency_hz="7", amplitude_peak_dps="15.0"
    )
    seven_20 = find_row(
        amplitude_rows, frequency_hz="7", amplitude_peak_dps="20.0"
    )
    print(
        " 7 Hz／15 deg/s：enabled筆數 = "
        f"{seven_15['enabled_samples_during_tone']}（未開啟）"
    )
    print(
        " 7 Hz／20 deg/s：enabled筆數 = "
        f"{seven_20['enabled_samples_during_tone']}（可能誤開）"
    )

    sample_rate_rows = read_csv(
        GATING_DIR / "gating_robustness" / "sample_rate_sweep.csv"
    )
    fs_105_4hz = find_row(
        sample_rate_rows,
        actual_sample_rate_hz="105.0",
        physical_frequency_hz="4.0",
    )
    print(
        " 實際105 Hz／4 Hz：enabled筆數 = "
        f"{fs_105_4hz['enabled_samples_during_tone']}（邊界漏判）"
    )

    print("\n[3] App BLE／FFT／PSD驗收答案")
    expected = json.loads(
        (FIXTURE_DIR / "ble_5hz_expected.json").read_text(encoding="utf-8")
    )
    print(f" BLE record：{expected['record_count']}筆 × {expected['record_size_bytes']} bytes")
    print(f" 主要頻率：{expected['dominant_frequency_hz']:.2f} Hz")
    print(f" 4～6 Hz三軸RMS：{expected['tremor_band_rms_4_6_dps']:.4f} deg/s")
    print(f" 資料有效：{expected['data_valid']}")

    print("\n結論：板上判斷、App規格與限制都有可重現答案；真實抑震率尚未量測。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
