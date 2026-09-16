# -*- coding: utf-8 -*-
"""7/30 進度報告用的離線備援 demo。

只讀取已提交的合成測試結果，不會操作 STM32 或馬達。
"""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
TEST_VECTOR_DIR = REPO_ROOT / "algorithms" / "handoff" / "test_vectors"
ROBUSTNESS_DIR = TEST_VECTOR_DIR / "gating_robustness"
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
    raise ValueError(f"找不到符合條件的資料：{conditions}")


def did_enable(row: dict[str, str]) -> bool:
    return int(row["enabled_samples_during_tone"]) > 0


def show_frequency_vectors() -> None:
    print("\n[1] STM32 1～8 Hz 基本測試（15 deg/s、100 Hz）")
    rows = read_csv(TEST_VECTOR_DIR / "gating_frequency" / "expected_results.csv")
    print(" Hz | enabled | 啟動延遲(ms) | 震顫段開啟筆數")
    for row in rows:
        expected = "1" if row["should_enable"] == "1" else "0"
        print(
            f" {int(row['frequency_hz']):>2} | {expected:^7} | "
            f"{row['delay_from_tone_start_ms']:^12} | "
            f"{row['enabled_samples_during_400_sample_tone']:>6}/400"
        )


def show_amplitude_sweep() -> None:
    rows = read_csv(ROBUSTNESS_DIR / "amplitude_sweep.csv")
    print("\n[2-A] 頻率 × 振幅：56 組")
    print("每個頻率第一次會開啟的測試振幅；never 代表測到20 deg/s仍未開啟。")
    print(" Hz | 首次開啟振幅")
    for frequency_hz in range(1, 9):
        selected = [r for r in rows if r["frequency_hz"] == str(frequency_hz)]
        enabled = [r for r in selected if did_enable(r)]
        threshold = (
            f"{float(enabled[0]['amplitude_peak_dps']):.0f} deg/s"
            if enabled
            else "never"
        )
        print(f" {frequency_hz:>2} | {threshold}")
    print("重點：7 Hz在15 deg/s不開，但20 deg/s會誤開，必須上板補測。")


def show_mixed_sweep() -> None:
    rows = read_csv(ROBUSTNESS_DIR / "mixed_2hz_5hz_sweep.csv")
    print("\n[2-B] 2 Hz自主動作 + 5 Hz震顫：40 組")
    print("固定5 Hz震顫為20 deg/s，逐步增加2 Hz自主動作：")
    print(" 2 Hz振幅 | 震顫段開啟筆數 | 結果")
    for voluntary in (0, 10, 20, 30, 40):
        row = find_row(
            rows,
            voluntary_2hz_peak_dps=f"{voluntary:.1f}",
            tremor_5hz_peak_dps="20.0",
        )
        count = int(row["enabled_samples_during_tone"])
        result = "有開啟" if count else "未開啟"
        print(f" {voluntary:>8} | {count:>16}/400 | {result}")
    print("重點：自主動作很強時，頻帶比例可能讓同時存在的震顫無法通過。")


def show_sample_rate_sweep() -> None:
    rows = read_csv(ROBUSTNESS_DIR / "sample_rate_sweep.csv")
    print("\n[2-C] 實際取樣率95／100／105 Hz：9 組")
    print(" 實際取樣率 | 訊號頻率 | enabled | 啟動延遲(ms)")
    for row in rows:
        delay = (
            f"{float(row['first_enabled_delay_ms']):.0f}"
            if row["first_enabled_delay_ms"]
            else "never"
        )
        print(
            f" {float(row['actual_sample_rate_hz']):>8.0f} Hz | "
            f"{float(row['physical_frequency_hz']):>6.0f} Hz | "
            f"{int(did_enable(row)):^7} | {delay}"
        )
    print("重點：filter固定按100 Hz設計時，105 Hz下的4 Hz邊界會漏判。")


def show_jitter_sweep() -> None:
    rows = read_csv(ROBUSTNESS_DIR / "jitter_sweep.csv")
    print("\n[2-D] 取樣間隔誤差：20 組")
    print(" 誤差範圍 | 實際最短～最長間隔 | 啟動延遲範圍")
    for jitter in (0, 1, 2, 4):
        selected = [
            row for row in rows
            if float(row["max_requested_jitter_ms"]) == float(jitter)
        ]
        min_interval = min(float(row["min_interval_ms"]) for row in selected)
        max_interval = max(float(row["max_interval_ms"]) for row in selected)
        delays = [float(row["first_enabled_delay_ms"]) for row in selected]
        print(
            f" ±{jitter:<4} ms | {min_interval:>5.2f}～{max_interval:<5.2f} ms | "
            f"{min(delays):.0f}～{max(delays):.0f} ms"
        )
    print("重點：20組都能開啟，但時序誤差會改變啟動延遲。")


def show_dropout_sweep() -> None:
    rows = read_csv(ROBUSTNESS_DIR / "dropout_sweep.csv")
    policy_labels = {
        "hold_last": "沿用上一筆",
        "zero_fill": "補零",
        "nan_fail_safe": "無效即關閉",
        "skip_update": "暫停更新",
    }
    pattern_labels = {
        "periodic_2pct": "週期掉點2%",
        "random_5pct": "隨機掉點5%",
        "burst_200ms": "連續掉點200ms",
    }
    interpretations = {
        "hold_last": "使用過期值",
        "zero_fill": "人工補0",
        "nan_fail_safe": "立即關閉並清計數",
        "skip_update": "狀態停在上一筆",
    }
    print("\n[2-E] 週期、隨機與連續掉點：12 組（3種掉點 × 4種處理）")
    print(" 掉點情境       | 處理方法   | 開啟筆數 | 解讀")
    for row in rows:
        pattern = row["dropout_pattern"]
        if pattern == "none":
            continue
        policy = row["dropout_policy"]
        count = int(row["enabled_samples_during_tone"])
        print(
            f" {pattern_labels[pattern]:<12} | {policy_labels[policy]:<8} | "
            f"{count:>3}/400 | {interpretations[policy]}"
        )
    print("建議：穿戴版第一版採『資料無效就關閉並清除計數』，仍需韌體組確認。")


def show_app_reference() -> None:
    print("\n[3] App BLE／FFT／PSD驗收答案")
    expected = json.loads(
        (FIXTURE_DIR / "ble_5hz_expected.json").read_text(encoding="utf-8")
    )
    print(
        f" BLE record：{expected['record_count']}筆 × "
        f"{expected['record_size_bytes']} bytes"
    )
    print(f" 主要頻率：{expected['dominant_frequency_hz']:.2f} Hz")
    print(
        " 4～6 Hz三軸RMS："
        f"{expected['tremor_band_rms_4_6_dps']:.4f} deg/s"
    )
    print(f" 資料有效：{expected['data_valid']}")


def main() -> int:
    print("=== SteadyHope 7/30 離線備援 demo ===")
    print("注意：以下為PC reference／合成資料，不是人體抑震率。")
    show_frequency_vectors()
    show_amplitude_sweep()
    show_mixed_sweep()
    show_sample_rate_sweep()
    show_jitter_sweep()
    show_dropout_sweep()
    show_app_reference()
    print("\n結論：板上判斷、App規格與失效邊界都有可重現答案；真實抑震率尚未量測。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
