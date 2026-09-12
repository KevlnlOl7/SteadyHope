# App 震顫頻率與 PSD 資料規格（V1）

日期：2026-07-28

修訂：2026-09-12。保留 V1 的 `0.20／0.30／0.45` 工程門檻，補充頻率回報與事件
區分、最近 50 筆馬達比例、資料中斷及 App 公式對齊要求。本次只修訂文件，未修改 App。

給軟體組的說明與修改清單：[APP_EVENT_REVIEW_20260912.md](APP_EVENT_REVIEW_20260912.md)。

主責：張傢寧（演算法規格與 Python 參考程式）

協作：李冠廷（STM32／BLE 資料格式）、樊柔妤（App 接收與圖表）

## 1. 這項功能要做什麼

這項功能使用 BNO055 的三軸角速度，讓 App 顯示：

- 最近 4 秒的 GyroX、GyroY、GyroZ 波形，單位 `deg/s`。
- 目前的三軸合計 PSD 頻譜。
- 3–7 Hz 範圍內的主要震顫頻率，單位 `Hz`。
- 4–6 Hz 頻帶強度。
- 資料是否完整，以及這次頻率是否有足夠證據。
- `motorEnabled` 開啟區段，僅疊在時間波形上供對照。

這項功能是「App 顯示與後續分析」，不是馬達開關方法，也不是醫療診斷。
馬達 gating 繼續使用 `tremor_gate.c`；App 不可使用 eHWFLC-KF 的
`freqEstimate` 當作震顫頻率。

本規格的輸出首先是**分析紀錄**。`data_valid` 表示資料品質，`frequency_reliable`
表示主頻是否符合回報條件；兩者皆不直接定義一次震顫事件。定期保存一筆資料不能
算成一次發作，也不能更新「最後震顫時間」。事件規則的缺項與分工見
[`APP_PSD_IMPLEMENTATION.md` §12](APP_PSD_IMPLEMENTATION.md#12-分析紀錄與事件功能2026-09-12-補充)。

### 頻帶名詞不可混用

| 範圍 | 本專題固定語意 |
|---|---|
| 4–6 Hz | 第一版保守核心馬達目標，不是 PD 的完整臨床頻率範圍 |
| 4–7 Hz | MDS 描述的典型 parkinsonian rest tremor 可及範圍 |
| 3–7 Hz | 穿戴式資料的候選主頻搜尋範圍 |
| 7.25／8 Hz 純 tone | engineering out-of-target controls，不是健康者或臨床陰性樣本 |

頻率單獨不能區分 Parkinson's disease、其他震顫或節律性自主動作，因此不得用上述
任何一個頻帶作診斷，也不得把合成 tone 的 gate 結果稱為臨床 sensitivity、specificity
或 false positive。

## 2. 為什麼採用這個方法

Timmermans 等人 2025 年發表的腕戴式 gyroscope 研究使用 50 或 100 Hz
資料、4 秒視窗、分別計算三軸 PSD，再將三軸 PSD 相加並擷取 peak
frequency；該研究以 3–7 Hz 作為 Parkinson’s disease 靜止震顫的頻率條件。

SteadyHope V1 依照上述資料流，採用：

1. 100 Hz 三軸 Gyro。
2. 4 秒分析視窗，共 400 筆。
3. 每軸先去除平均值，再套 Hann window。
4. 每軸執行 FFT，換算成 one-sided PSD。
5. 將 X、Y、Z 三軸 PSD 相加。
6. 在 3–7 Hz 內找最高點，作為主要頻率候選值。
7. 加總 4–6 Hz PSD，作為震顫頻帶強度。

原研究使用 Welch PSD；SteadyHope V1 先採用「單一 4 秒 Hann window PSD」。
這等同使用一個 segment 的 Welch 計算，可保留 `100 / 400 = 0.25 Hz`
的頻率間距，也較容易在 Swift 中逐步重現。它不是原研究分類器的完整重製：
本專題目前沒有照搬 MFCC、logistic regression 或病患分類門檻。

## 3. 韌體／BLE 邏輯資料格式（V1定案）

最低必要欄位：

| 欄位 | 傳輸型別 | 單位 | 白話意義 |
|---|---:|---:|---|
| `sequence` | `uint32` | 無 | 第幾筆資料，用來發現 BLE 是否漏資料 |
| `sample_tick_ms` | `uint32` | ms | STM32開機後的取樣計時，只用來檢查100 Hz時序 |
| `gyro_x_raw` | `int16` | 1/16 deg/s | BNO055 X軸Gyro原始值 |
| `gyro_y_raw` | `int16` | 1/16 deg/s | BNO055 Y軸Gyro原始值 |
| `gyro_z_raw` | `int16` | 1/16 deg/s | BNO055 Z軸Gyro原始值 |
| `sensor_valid` | `uint8` | 0/1 | 這筆 IMU 資料是否讀取成功 |
| `motor_enabled` | `uint8` | 0/1 | wire 相容名稱；實際語意是 `motor_output_active`（完整控制鏈套用非零命令），不是 Gate，也不證明馬達有移動 |

每筆固定16 bytes，採little-endian：

```text
4 sequence + 4 sample_tick_ms + 2 gyro_x_raw + 2 gyro_y_raw +
2 gyro_z_raw + 1 sensor_valid + 1 motor_enabled = 16 bytes
```

App收到後轉換：

```text
gyro_x_dps = gyro_x_raw / 16.0
gyro_y_dps = gyro_y_raw / 16.0
gyro_z_dps = gyro_z_raw / 16.0
```

重要事項：

- `sample_tick_ms`不是日期時間，而是STM32開機後的單調遞增計時。
- BLE傳原始 `int16`，不要先轉成三個`float32`，以降低封包大小。
- 保持 100 Hz，也就是每 10 ms 產生一筆資料。
- 每一筆是16 bytes邏輯紀錄；BLE一包放幾筆由實際MTU決定，不可拆壞單筆欄位順序。
- 若要批次傳送，目標傳輸延遲不超過50 ms；無論如何都必須保持100 Hz取樣。
- 即使分批傳送，每一筆仍要保留自己的`sequence`與`sample_tick_ms`。
- `motor_enabled` 是歷史 wire field 名稱，目前解讀為命令作用狀態；不可稱為
  Gate permission、實際馬達轉動或抑震成功，也不可拿來修改 PSD 計算結果。
- `sensor_valid`與`motor_enabled`在STM32內可用Boolean語意；BLE封包固定用`uint8`的0或1。

### 3.1 真實日期時間與使用情境

醫生或照護者需要的「2026-07-28 18:30發生震顫」不是由STM32提供。STM32通常只有
開機計時，沒有可信任的網路校時；真實日期時間由App建立session時記錄：

| App session欄位 | 型別 | 說明 |
|---|---|---|
| `session_id` | UUID/string | 每次連線或開始紀錄的唯一編號 |
| `session_start_utc_ms` | `int64` | App的Unix epoch毫秒，存UTC |
| `session_start_sample_tick_ms` | `uint32` | 同一時刻對應的STM32 sample tick |
| `timezone_identifier` | string | 例如`Asia/Taipei`，只用於顯示當地時間 |

每一筆資料的實際時間由App換算：

```text
recorded_at_utc_ms = session_start_utc_ms
                   + unsigned_delta(sample_tick_ms,
                                    session_start_sample_tick_ms)
```

BLE斷線重連或STM32重新開機時必須建立新session。不要把每個BLE封包到達App的時間
直接當作每一筆IMU時間，因為批次傳輸會讓多筆資料同時到達。

名目取樣間隔為 10 ms；不得使用 50 Hz 的 20 ms 常數推算此版時間軸。session 與
anchor 要在原始資料／分析回呼分派之前確立，同一批資料共用其 session 與樣本時間。
分析紀錄的時間取該視窗最後一筆量測時間，處理時間與上傳時間另存，不互相覆蓋。
斷線、重新連線或 MCU 重開機時重建分析窗口與 session；未上傳資料仍保留原 session。
初始 anchor 若由手機接收時間估計，仍有傳輸延遲的不確定性。

只有日期時間仍不能知道「當時在做什麼」。若要讓醫生或照護者分析情境，App還要讓
使用者選擇或補記`activity_tag`，第一版建議：`rest`、`eating`、`drinking`、
`writing`、`walking`、`after_medication`、`other`，並可附加文字`note`。

## 4. App 分析與更新時間

App至少保留最近60秒的顯示結果；原始Gyro環形buffer至少保留最新400筆。
每次分析只取最新4秒：

App開發人員請直接依照[APP_PSD_IMPLEMENTATION.md](APP_PSD_IMPLEMENTATION.md)實作；
該文件包含BLE byte offset、Hann／FFT／PSD公式、frequency bin、pseudocode及5 Hz驗收值。

| 項目 | 規格 |
|---|---|
| 取樣率 | 100 Hz |
| 分析視窗 | 4 秒／400 筆 |
| App 更新間隔 | 每 0.5 秒更新一次 |
| FFT 大小 | 400 |
| 頻率間距 | 0.25 Hz |
| 主要頻率搜尋範圍 | 3–7 Hz |
| 專題 gating 關注頻帶 | 4–6 Hz |
| PSD 單位 | `(deg/s)^2/Hz` |
| 4–6 Hz power 單位 | `(deg/s)^2` |
| 振幅圖顯示量 | 4–6 Hz三軸合計band RMS，單位`deg/s` |

不要直接對
`sqrt(GyroX^2 + GyroY^2 + GyroZ^2)` 做 FFT。取絕對大小會改變波形並可能
產生倍頻；應先算三軸各自的 PSD，再把 PSD 相加。

### 4.1 無效資料規則

以下任一條成立，該次4秒視窗即為無效，不計算也不沿用上一筆結果：

- 不足400筆。
- `sequence`沒有每筆加1，代表BLE掉包或資料重複。
- 相鄰`sample_tick_ms`不是8–12 ms，代表取樣時序不穩定。
- 任一筆`sensor_valid=0`。
- 任一軸數值為 NaN／Inf。

無效結果在App上畫成缺口，頻率與強度顯示`--`，不能把上一個數字繼續顯示成
目前結果。

## 5. App主振幅圖規格（V1定案）

主圖不是raw Gyro波形，也不是頻率折線圖。每0.5秒產生一個「最近4秒內，
4–6 Hz震顫有多強」的數值：

```text
P_4_6 = sum((PSD_X + PSD_Y + PSD_Z) * 0.25 Hz), f = 4...6 Hz
tremor_strength_rms_dps = sqrt(P_4_6)
```

| 圖表項目 | 定義 |
|---|---|
| 圖名 | 最近60秒震顫強度 |
| X軸 | 實際日期時間，使用每個視窗的`recorded_at_utc_ms`轉為當地時間 |
| Y軸 | `tremor_strength_rms_dps`，單位`deg/s`，從0開始 |
| 更新頻率 | 每0.5秒新增一點，60秒共最多120點 |
| 命令作用區段 | 依原始 `motor_enabled`（=`motor_output_active`）時間區段加背景色，不改變曲線數值 |
| 無效資料 | 曲線中斷並顯示資料不足，不連線、不補值 |
| 主要頻率 | 另外以數字顯示`dominant_frequency_hz`，不當作主圖Y軸 |

Y軸不得標成輕度／中度／重度；目前沒有患者資料可以建立臨床分級。相同配戴位置、
相同活動情境下，RMS降低表示4–6 Hz角速度成分降低，但不能單獨解讀為病情改善。

App可以把最近4秒的三軸raw Gyro與PSD放在「工程／詳細資料」頁面；使用者首頁以
目前主要頻率、目前震顫強度、60秒強度趨勢、馬達命令作用區段及資料品質為主。

每0.5秒的歷史結果至少儲存：`recorded_at_utc_ms`、`dominant_frequency_hz`、
`tremor_strength_rms_dps`、`motor_command_active_fraction`、`data_valid`、`frequency_reliable`、
`activity_tag`與`note`。歷史頁才可以依時段或活動比較震顫，而不是只看即時60秒。

`motor_command_active_fraction` 沿用遠端規範欄位名，App 現有 `motorOnFraction`
若保留為 API 舊名，須與後端明訂映射／版本。它採**最近 50 筆／名目 0.5 秒**窗口，計算合法且連續的
0／1 旗標平均。它與 PSD／RMS 的 400 筆／4 秒窗口不同；不能用任一筆為 1 的布林值
代替比例，也不能改用 400 筆平均覆蓋此欄位。資料不足／旗標無效時保留未知狀態，
不可補成 0；既有 DTO 若無法表達未知，需與後端同步修訂欄位或品質狀態。

## 6. 輸出定義

Python 參考程式的主要輸出：

| 輸出 | 白話意義 |
|---|---|
| `data_valid` | 400 筆是否完整、數值是否正常、時間與編號是否連續 |
| `frequency_reliable` | 3–7 Hz 是否有足夠清楚且集中的週期訊號 |
| `dominant_frequency_hz` | 可顯示給使用者的主要頻率；不可靠時為 `null` |
| `candidate_frequency_hz` | 供工程 debug 的最高點；不代表一定是震顫 |
| `tremor_band_power_4_6_dps2` | 三軸合計的 4–6 Hz power |
| `tremor_band_rms_4_6_dps` | 4–6 Hz 強度的 RMS 形式，較容易與角速度理解 |
| `axis_power_4_6_dps2` | X、Y、Z各軸的4–6 Hz power，可用來找主要抖動軸 |
| `frequencies_hz` | PSD 圖的 X 軸 |
| `psd_sum_dps2_per_hz` | PSD 圖的 Y 軸 |

App 顯示規則：

- `data_valid=false`：顯示「資料不完整／BLE 可能掉包」，頻率顯示 `--`。
- `data_valid=true` 但 `frequency_reliable=false`：顯示「目前沒有清楚的主要震顫頻率」，
  頻率顯示 `--`。
- 兩者都為 `true`：才顯示 `dominant_frequency_hz`。

「頻率可信度」目前使用相對 power 與 peak 集中程度判斷，只是 prototype
的畫面保護條件，不是臨床診斷門檻，必須用實機與真實配戴資料再校調。

Python V1的明確保護條件為：三軸合計RMS至少0.20 deg/s、3–7 Hz power至少占
0.5–15 Hz power的30%，且主要peak前後0.5 Hz至少占3–7 Hz power的45%。
這些只是避免App在靜置或雜訊下亂顯示頻率，不能稱為疾病判斷門檻。

2026-09-12 核對的 App 分支最新提交 `56805c93c46af81fb922af7780a8841a07258b39`
雖使用相同三個數字，卻將 vector RMS 取成 4–6 Hz band RMS、占比分母取全頻譜、
集中度只取單一最高 bin。應依
[`APP_PSD_IMPLEMENTATION.md` §7](APP_PSD_IMPLEMENTATION.md#7-何時可以顯示主要頻率)
對齊公式與比較策略，不能僅對照常數。
目前 Python V1 的 peak ±0.5 Hz 分子未裁到 3–7 Hz，邊界值可能大於 1；這是已知
定義限制，不能當作 0–1 信心分數，也不能只在 App 單端悄悄更改。

上傳必須保留實際 `frequency_reliable`，不能固定寫成 true。有效但頻率不可靠的
紀錄可保留 RMS，頻率為 null；無效紀錄的頻率與強度為 null，另保留品質缺口。
分析紀錄筆數及其重疊的 4 秒窗口不能直接換算震顫次數或持續時間。

本次沒有為患者震顫事件新增最短秒數或幅度門檻。若另統計 Gate 升降沿，須有
獨立 Gate 資料；目前 `motor_enabled` 是命令作用狀態，不能作 Gate 替代。
`TremorGate_DefaultConfig` 的預設 Gate 啟動條件為 4–6 Hz 包絡 ≥6 deg/s，且包絡
比例 ≥0.55，連續 20 筆（名目 200 ms）。實際韌體若覆寫配置，應記錄所用版本
及參數；此為獨立控制邏輯。

完整的硬體啟動／解除條件、包絡定義、適用韌體及 App 可直接採用的「資料與判斷
方式」文案見 [APP_PSD_IMPLEMENTATION.md](APP_PSD_IMPLEMENTATION.md) §11。
硬體的 6 deg/s 是單軸濾波包絡門檻，與本文件 0.20 deg/s 的三軸 vector RMS
屬於不同特徵。硬體解除條件也有獨立的 3 deg/s／0.45／15 筆設定，不應只用
「頻率占比 0.55 持續 200 ms」描述完整規則。

## 7. Python 參考程式與測試資料

檔案：

- `algorithms/validation/tremor_frequency_reference.py`
- `algorithms/validation/test_tremor_frequency_reference.py`
- `algorithms/validation/fixtures/tremor_5hz.csv`
- `algorithms/validation/fixtures/tremor_5hz_expected.json`
- `algorithms/validation/fixtures/tremor_noisy_5hz.csv`
- `algorithms/validation/fixtures/tremor_noisy_5hz_expected.json`
- `algorithms/validation/fixtures/ble_5hz_records.bin`（400筆16-byte BLE record）
- `algorithms/validation/fixtures/ble_5hz_expected.json`
- `algorithms/validation/fixtures/app_quality_cases.json`
- `algorithms/validation/ble_packet_reference.py`

PNG只在需要報告或除錯時產生，不納入Git；自動測試使用隱藏暫存檔，執行後刪除，
不會把教學圖留在repo。

執行環境需要 `numpy`；產生 PNG 另需 `Pillow`。

在 repo 根目錄執行：

```powershell
python algorithms/validation/tremor_frequency_reference.py `
  --input algorithms/validation/fixtures/tremor_5hz.csv
```

產生答辯用 PNG（三軸原始波形＋三軸合計 PSD）：

```powershell
python algorithms/validation/tremor_frequency_reference.py `
  --input algorithms/validation/fixtures/tremor_5hz.csv `
  --plot "$env:TEMP\steadyhope_tremor_5hz_plot.png"
```

如果需要向老師解釋「頻率怎麼算」，使用教學圖：

```powershell
python algorithms/validation/tremor_frequency_reference.py `
  --input algorithms/validation/fixtures/tremor_5hz.csv `
  --explain-plot "$env:TEMP\steadyhope_tremor_5hz_explain.png"
```

另提供一組較接近實測外觀的單軸 GyroX 合成資料，包含頻率飄動、振幅改變、
約 2 Hz 自主動作、感測雜訊與短暫動作；Y、Z 在這組示範中固定為 0。
它的用途是確認單軸波形即使看起來不規律，只要仍有持續的約 5 Hz 成分，
PSD 仍能找出主要頻率：

```powershell
python algorithms/validation/tremor_frequency_reference.py `
  --input algorithms/validation/fixtures/tremor_noisy_5hz.csv `
  --plot "$env:TEMP\steadyhope_tremor_noisy_5hz_plot.png"
```

產生 Hann window 具象教學圖：

```powershell
python algorithms/validation/tremor_frequency_reference.py `
  --hann-plot "$env:TEMP\steadyhope_hann_window_explain.png"
```

執行自動測試：

```powershell
python -m unittest discover -s algorithms/validation `
  -p "test_tremor_frequency_reference.py" -v
```

測試資料是固定公式產生的 5 Hz 三軸合成角速度，用來確認 Python 與 App
計算結果一致。它不是患者資料，也不能拿來宣稱裝置具有臨床辨識準確率。

## 8. 實機驗證順序

1. 先用 `tremor_5hz.csv` 確認 Python 輸出 5.0 Hz。
2. App 使用同一份 CSV，確認也是 5.0 Hz，且 PSD peak 位置一致。
3. STM32／BLE 傳送 400 筆測試陣列，確認 App 沒有掉包。
4. 馬達關閉，記錄方彥實際配戴的三軸 Gyro。
5. 用節拍器協助做不同速度的週期動作，但真實頻率仍由 PSD 事後計算，
   不把人的手動動作直接當成精準 4、5、6 Hz 標準源。
6. 最後才分析真實配戴資料的主要頻率、4–6 Hz power 與主要抖動軸。

## 9. 文獻與開源資源

1. Timmermans NA, et al. *A generalizable and open-source algorithm for
   real-life monitoring of tremor in Parkinson’s disease*. npj Parkinson’s
   Disease, 2025.
   https://doi.org/10.1038/s41531-025-01056-2

2. 上述研究的開源程式：
   https://github.com/biomarkersParkinson/pdathome_tremor

3. PADS 公開 smartwatch 資料集論文；資料包含 100 Hz 三軸 acceleration
   與 rotation，可作為後續外部資料驗證方向：
   https://doi.org/10.1038/s41531-023-00625-7

4. Bhatia KP, et al. *Consensus Statement on the classification of tremors,
   from the task force on tremor of the International Parkinson and Movement
   Disorder Society*. Movement Disorders, 2018. 文中說明合併 parkinsonism 的
   rest tremor 通常落在 4–7 Hz：
   https://doi.org/10.1002/mds.27121
