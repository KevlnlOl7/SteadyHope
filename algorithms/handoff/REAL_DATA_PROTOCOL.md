# 實機資料錄製與V2 gating門檻校調流程

日期：2026-07-30

這份流程讓韌體、機構與演算法組取得可重現的100 Hz資料。第一輪受試者是健康組員，
因此結果只能稱為「工程測試／模擬抖動」，不可寫成Parkinson's disease患者驗證。

## 1. 安全與測試順序

1. 先不通電配戴，只錄IMU與gating資料。
2. gating固定向量測試通過後，馬達先接非人體負載。
3. 必須先確認限位、最大PWM、電流、溫度及緊急停止，才可討論通電配戴。
4. 不把健康組員刻意快速抖動稱為病理性震顫。

## 2. 每筆100 Hz資料格式

| 欄位 | 型態／單位 | 必要 | 說明 |
|---|---|---:|---|
| `session_id` | string | 是 | 一次連續錄製的編號；重開STM32需換新編號 |
| `segment_id` | string | 是 | 同一session內的動作區段 |
| `activity_label` | string | 是 | `rest`、`voluntary_slow`、`voluntary_fast`、`simulated_tremor`或`mixed` |
| `expected_gate` | `uint8` 0/1 | 是 | 工程測試期望；不是疾病診斷標籤 |
| `sequence` | `uint32` | 是 | 每筆加1，用來檢查掉資料 |
| `sample_tick_ms` | `uint32` / ms | 是 | STM32開機計時，每筆約增加10 ms |
| `gyro_x_raw`、`gyro_y_raw`、`gyro_z_raw` | `int16` | 是 | BNO055原始Gyro |
| `gyro_x_dps`、`gyro_y_dps`、`gyro_z_dps` | `float` / deg/s | 是 | raw除以16後的角速度 |
| `tremor_envelope` | `float` / deg/s | 是 | 4–6 Hz震顫帶強度 |
| `voluntary_envelope` | `float` / deg/s | 是 | 1–3 Hz自主動作帶強度 |
| `tremor_ratio` | `float` / 0–1 | 是 | 目前訊號以震顫帶為主的比例 |
| `enabled` | `uint8` 0/1 | 是 | gating是否允許馬達控制 |
| `tremor_estimate` | `float` / deg/s | 建議 | eHWFLC-KF估測波形，不使用`freqEstimate` |
| `pwm_percent` | `float` / 0–100 | 通電時 | 實際送出的PWM duty，不是拉力 |
| `motor_direction` | `int8` -1/0/1 | 通電時 | 反向、停止、正向；實際極性需標定 |
| `sensor_valid` | `uint8` 0/1 | 是 | IMU讀取是否成功 |

範本：`templates/real_recording_template.csv`。

## 3. 第一輪不通電錄製情境

每個動作錄20秒、重複3次，中間靜置5秒。BNO055固定位置與方向，全程保持100 Hz。

| 情境 | 動作 | `expected_gate` | 目的 |
|---|---|---:|---|
| 靜置 | 手自然放鬆 | 0 | 量測偏移與噪聲 |
| 慢速自主動作 | 約1 Hz屈伸／旋轉 | 0 | 檢查低頻拒絕 |
| 一般自主動作 | 約2 Hz重複動作 | 0 | 檢查1–3 Hz自主頻帶 |
| 快速自主動作 | 自然快速動作，不追求固定頻率 | 0 | 找誤觸發 |
| 模擬抖動 | 節拍器輔助約4、5、6 Hz，小幅度 | 1 | 工程觸發與延遲測試 |
| 停止再出現 | 5 Hz 5秒、停止3秒、再5 Hz 5秒 | 依區段 | 檢查關閉與重新啟動 |
| 混合動作 | 慢速自主動作疊加快速小幅抖動 | 先只記錄 | 探索限制，不作臨床標籤 |

人工動作無法保證恰好4、5、6 Hz，因此分析時必須以三軸FFT／PSD確認實際頻率，
不能只相信節拍器設定。

## 4. 資料品質驗收

- `sequence`不可跳號或重複。
- 相鄰`sample_tick_ms`須為8–12 ms。
- `sensor_valid`須為1；錯誤資料不可拿來校門檻。
- 每一段需保存安裝方向、動作說明、馬達狀態及操作者。
- 原始CSV不得手動刪點或平滑；清理後資料另存新檔並記錄規則。

## 5. 門檻分析

先在CSV加入`gyro_x_dps`與`expected_gate`，再執行：

```powershell
python algorithms/validation/calibrate_gating_thresholds.py `
  --input recording.csv --output-json calibration.json
```

輸出包含Sensitivity、Specificity、False Positive Rate、Balanced Accuracy、啟動與關閉
延遲，以及候選`amp_on`、`amp_off`、`ratio_on`、`ratio_off`。prototype工程目標暫定：

- 模擬震顫段Sensitivity至少90%。
- 非震顫段False Positive Rate不超過2%。

分類率會排除每次標籤切換後750 ms的transition grace，因為這段應以啟動／關閉延遲
評估，不應重複算成分類錯誤；工具仍會獨立列出實際切換延遲。

這些只是工程驗收目標。門檻不得只用同一位健康組員的一次資料決定；至少要保留不同
日期的資料做獨立確認，日後取得合規的PD資料後還要重新校調。
