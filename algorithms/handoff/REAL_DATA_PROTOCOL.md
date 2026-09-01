# 實機資料錄製與V2 gating門檻校調流程

初版：2026-07-30　修訂：2026-08-06

這份流程讓韌體、機構與演算法組取得可重現的100 Hz資料。第一輪受試者是健康組員，
因此結果只能稱為「工程測試／模擬抖動」，不可寫成Parkinson's disease患者驗證。

## 1. 本輪交付邊界與分工

- 許方彥：固定IMU、確認機構不干涉、依segment plan執行動作並記錄異常。
- 李冠廷／范瑋哲：以100 Hz輸出逐筆sample stream，保留sequence、tick與有效狀態。
- 張傢寧：驗收資料品質、三軸PSD、gating誤開／漏判與候選門檻。
- 第一輪馬達必須關閉；沒有穩定雛形、限位、限流與緊急停止前，不做人體通電抑震。

## 2. 檔案分層：不要把所有文字塞進100 Hz封包

一次錄製使用三類檔案：

1. `recording_session_manifest.csv`：受試者代碼、版本、IMU位置／方向與馬達狀態。
2. `recording_segment_plan.csv`：每段動作、trial、期望gating與是否納入計分。
3. `recording_<session_id>.csv`：STM32／PC實際保存的100 Hz逐筆資料。

BLE最小16-byte封包只傳sequence、tick、三軸raw、`sensor_valid`與`motor_enabled`；其中
`motor_enabled` 是相容既有 App 的 wire 名稱，現行韌體送的是 `motor_output_active`：完整
安全鏈接受並套用非零 command。它不是 `gate_enabled`，也不證明馬達真的移動；
session與動作標籤由App或PC錄製工作階段另外附加。工程`activity_label`不等於App讓
使用者選擇的生活情境tag，兩者不得混成疾病診斷標籤。

範本：

- `templates/recording_session_manifest_template.csv`
- `templates/recording_segment_plan.csv`
- `templates/real_recording_template.csv`

建議檔名：`YYYYMMDD_<subject_code>_<session_id>_motor-off.csv`。

## 3. 每筆100 Hz資料格式

| 欄位 | 型態／單位 | 必要 | 說明 |
|---|---|---:|---|
| `session_id` | string | 是 | 一次連續錄製的編號；重開STM32需換新編號 |
| `segment_id` | string | 是 | 同一session內的動作區段 |
| `activity_label` | string | 是 | 使用下節定義的工程動作標籤 |
| `expected_gate` | `uint8` 0/1 | 是 | 工程測試期望；不是疾病診斷標籤 |
| `scored` | `uint8` 0/1 | 是 | 0表示保留資料但暫不納入門檻分類率 |
| `sequence` | `uint32` | 是 | 每筆加1，用來檢查掉資料 |
| `sample_tick_ms` | `uint32` / ms | 是 | STM32開機計時，每筆約增加10 ms |
| `gyro_x_raw`、`gyro_y_raw`、`gyro_z_raw` | `int16` | 是 | BNO055原始Gyro |
| `gyro_x_dps`、`gyro_y_dps`、`gyro_z_dps` | `float` / deg/s | 是 | raw除以16後的角速度 |
| `tremor_envelope` | `float` / deg/s | 是 | 4–6 Hz震顫帶包絡強度 |
| `voluntary_envelope` | `float` / deg/s | 是 | 1–3 Hz自主動作帶包絡強度 |
| `tremor_ratio` | `float` / 0–1 | 是 | 震顫帶相對於兩頻帶包絡總和的比例 |
| `enabled` | `uint8` 0/1 | 是 | 離線/工程 CSV 的 gate 狀態；不是 BLE wire `motor_enabled`，也不是抑震率 |
| `tremor_estimate` | `float` / deg/s | 建議 | eHWFLC-KF估測波形；不使用`freqEstimate` |
| `pwm_percent` | `float` / 0–100 | 通電時 | 實際PWM duty，不是拉力或位移 |
| `motor_direction` | `int8` -1/0/1 | 通電時 | 反向、停止、正向；實際極性需標定 |
| `sensor_valid` | `uint8` 0/1 | 是 | IMU讀取是否成功 |

## 4. 動作標籤與第一輪情境

每個一般動作錄20秒、重複3次，中間靜置5秒。BNO055固定位置、束帶鬆緊與方向，
全程100 Hz、motor off。每個trial只選一個`motion_plane`：`flexion_extension`、
`radial_ulnar`或`pronation_supination`，不要把不同旋轉混在同一段。

| `activity_label` | 動作 | 目標頻率 | `expected_gate` | `scored` |
|---|---|---:|---:|---:|
| `rest` | 手臂有支撐並自然放鬆 | 無 | 0 | 1 |
| `posture_hold` | 維持中立姿勢 | 無 | 0 | 1 |
| `voluntary_slow` | 選定平面約1 Hz規律動作 | 1 Hz | 0 | 1 |
| `voluntary_normal` | 選定平面約2 Hz規律動作 | 2 Hz | 0 | 1 |
| `voluntary_fast` | 自然快速動作，不追求固定頻率 | 未指定 | 0 | 1 |
| `cup_hold` | 拿空塑膠杯並維持 | 未指定 | 0 | 1 |
| `simulated_tremor` | 節拍器輔助4、5、6 Hz小幅模擬抖動 | 4／5／6 Hz | 1 | 1 |
| `mixed` | 慢速自主動作疊加快速小幅抖動 | 探索 | 0 | 0 |

停止再出現情境要拆成三個segment：`REON_A`為5 Hz 5秒、`REON_PAUSE`靜置3秒、
`REON_B`再5 Hz 5秒，期望值分別為1、0、1。`mixed`先標`scored=0`，等三軸PSD與
影片／操作紀錄確認後再另行決定標籤，不能把空白或猜測值送入門檻校調。

人工動作無法保證恰好4、5、6 Hz；`target_frequency_hz`只是操作指示，分析時仍須
用三軸FFT／PSD確認實際主頻。完整執行表見`templates/recording_segment_plan.csv`。

## 5. Session manifest至少要記錄

- `subject_code`只使用組員代碼，不放姓名、病歷或可識別健康資料。
- `recorded_at_utc`、操作者、左／右手。
- STM32 device、firmware、algorithm與gate config版本。
- IMU固定位置、X／Y／Z正方向與束帶設定。
- 馬達狀態；第一輪固定為`off`。
- 異常事件，例如束帶滑動、漏資料或動作失去節拍。

## 6. 資料品質驗收

- `sequence`不可跳號或重複。
- 相鄰`sample_tick_ms`須為8–12 ms；超出要保留並回報，不可手動改時間。
- `sensor_valid`須為1；錯誤資料不可拿來校門檻。
- raw與dps必須符合`dps = raw / 16.0`。
- `tremor_ratio`須在0–1，兩個envelope不得為負。
- 原始CSV不得手動刪點、補點或平滑；清理後資料另存新檔並保留規則。

收到資料後先執行：

```powershell
python algorithms/validation/validate_real_recording.py `
  --input recording.csv --output-json recording_quality.json
```

只有`pass=true`的segment才進入門檻分析。驗收工具只檢查工程資料品質，不判斷
Parkinson's disease，也不把健康組員的模擬動作當成臨床ground truth。

## 7. 門檻分析

資料包含`gyro_x_dps`、`expected_gate`、`scored`與`session_id`後執行：

```powershell
python algorithms/validation/calibrate_gating_thresholds.py `
  --input recording.csv --output-json calibration.json
```

`scored=0`的探索性區段會保留但排除分類率。輸出包含Sensitivity、Specificity、
False Positive Rate、Balanced Accuracy、啟動與關閉延遲，以及候選`amp_on`、
`amp_off`、`ratio_on`、`ratio_off`。prototype工程目標暫定：

- 模擬震顫段Sensitivity至少90%。
- 非震顫段False Positive Rate不超過2%。

分類率排除每次標籤切換後750 ms的transition grace；切換延遲會另外列出。這些只是
工程驗收目標。門檻不得只用同一位健康組員的一次資料決定；至少保留不同日期資料
獨立確認，日後取得合規PD資料後仍需重新校調。
