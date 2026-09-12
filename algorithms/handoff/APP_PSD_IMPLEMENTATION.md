# App端 FFT／PSD 實作流程（從BLE資料到震顫圖）

日期：2026-07-28

修訂：2026-09-12，補充 App 程式核對、分析紀錄與事件語意、品質旗標及中斷處理；
§11 補上硬體 Gate 規則、App 可使用的說明文案及版本核對要求。
本次保留 `0.20／0.30／0.45` 門檻及原有頻帶；這是規格修訂，不代表 App 已完成修改。

演算法規格：張傢寧

App實作者：樊柔妤

BLE資料提供：李冠廷

這份文件直接回答「App收到BLE資料後要做什麼」。權威數值參考是
`algorithms/validation/tremor_frequency_reference.py`；App必須使用相同測試CSV，
確認輸出一致後才接實機BLE。

App 分支 `fan/import-app-history` 在 2026-09-12 核對時的最新提交為
`56805c93c46af81fb922af7780a8841a07258b39`。已確認的公式差異見 §7.1，
「分析紀錄」與「事件」的分工見 §12；不要把三個頻率可信度門檻直接當成事件起迄規則。
給軟體組的轉貼說明、修改順序與程式證據見
[APP_EVENT_REVIEW_20260912.md](APP_EVENT_REVIEW_20260912.md)。

## 1. App每收到一筆BLE資料

每筆固定16 bytes、little-endian：

| byte offset | 欄位 | 型別 |
|---:|---|---|
| 0–3 | `sequence` | `uint32` |
| 4–7 | `sample_tick_ms` | `uint32` |
| 8–9 | `gyro_x_raw` | `int16` |
| 10–11 | `gyro_y_raw` | `int16` |
| 12–13 | `gyro_z_raw` | `int16` |
| 14 | `sensor_valid` | `uint8` |
| 15 | `motor_enabled` | `uint8`；歷史 wire 名稱，語意為 `motor_output_active` |

解析後立即轉成角速度：

```text
x = gyro_x_raw / 16.0  // deg/s
y = gyro_y_raw / 16.0  // deg/s
z = gyro_z_raw / 16.0  // deg/s
```

把解析後的資料依`sequence`順序放進環形buffer。`sample_tick_ms`是STM32開機後的
取樣計時，不是現在的年月日時間。不要使用App收到每筆資料的時間取代它；BLE可能
批次到達，封包抵達間隔不等於IMU取樣間隔。

### 1.1 同時建立真實日期時間

App開始一段紀錄時，用手機系統時間建立session anchor：

```text
session_id = UUID()
session_start_utc_ms = App目前的Unix epoch毫秒
session_start_sample_tick_ms = 第一筆有效資料的sample_tick_ms
timezone_identifier = 手機目前時區，例如Asia/Taipei
```

之後每筆資料的真實時間為：

```text
recorded_at_utc_ms = session_start_utc_ms
                   + unsigned_delta(sample_tick_ms,
                                    session_start_sample_tick_ms)
```

資料庫存UTC，畫面再依`timezone_identifier`顯示當地日期時間。BLE斷線重連或STM32
重新開機後建立新session，避免sample tick歸零造成時間跳回。

100 Hz 的名目取樣間隔是 **10 ms**。原始資料、分析結果及馬達區段須共用上述
session anchor，分析結果時間取視窗最後一筆的量測時間；手機處理／上傳時間若要
保留，另存欄位。不得使用 `0.02 s` 或 `index * 20 ms` 推算此版資料。
同一 session 內的 tick 回繞以無符號差值／累積 tick 處理；重開機則建立新 session。
初始手機 anchor 若由接收時間估計，須保留其估計性質，不能宣稱已消除 BLE 傳輸延遲。
session／anchor 應在回呼分派之前確立，非同步上傳工作攜帶資料所屬的 session 與
樣本時間快照，不在稍後執行時改讀目前 session。原始資料首次回呼可能是 400 筆，
之後通常為 50 筆，不能用固定 50 筆推算每批的第一筆時間。

### 1.2 斷線與重新連線

藍牙關閉、斷線或裝置重開機時，實際持有 BluetoothManager delegate 的物件必須把
狀態轉發到分析管線，或明確呼叫相同的中斷處理；僅在 pipeline 定義 callback 不算接通。
中斷時清除 raw 分析視窗、步進計數、上一筆序號／時間及馬達背景狀態，記錄中斷原因。
尚未上傳的資料仍屬於舊 session，須以原 session 與原量測時間保存／排程，不能與新
session 混成同一批，也不能為了清分析 buffer 而默默刪除待上傳資料。
重新連線建立新 session、重新收滿 400 筆才分析；圖表顯示缺口，中斷不等於震顫停止。

## 2. 何時開始計算

1. buffer不足400筆：只顯示「資料累積中」，不計算頻率。
2. 收滿400筆後：取最新400筆，也就是最近4秒。
3. 之後每收到50筆新資料再計算一次，也就是每0.5秒更新。
4. 相鄰兩次計算會共用前350筆資料，這是正常的rolling window。

計算前先檢查：

- 400筆`sequence`必須每筆加1。
- 相鄰`sample_tick_ms`必須介於8–12 ms。
- 400筆`sensor_valid`必須全部為1。
- 三軸數值必須全部為有限值；不能把 NaN／Inf 送入 FFT。

任一條失敗，本次輸出`data_valid=false`，頻率與強度為`null`，圖表新增缺口，
不得沿用上一個有效數字。

## 3. PSD白話意思

FFT把4秒角速度波形拆成許多不同頻率。因為取樣率100 Hz、資料長度400筆：

```text
頻率間距 = 100 / 400 = 0.25 Hz
第k格頻率 = k * 0.25 Hz
```

例如5 Hz位於：

```text
k = 5 / 0.25 = 20
```

PSD不是「出現次數」。它代表每個頻率格中有多少角速度訊號power；App最後把
4–6 Hz所有格子的power加起來，再開根號轉回容易理解的`deg/s RMS`。

## 4. 每一軸如何從Gyro算出one-sided PSD

X、Y、Z三軸分開執行以下步驟。`N=400`、`fs=100`。

### 4.1 去除平均值

```text
mean = sum(axis[n]) / N
centered[n] = axis[n] - mean
```

這會移除感測器固定偏移與非常慢的姿勢成分。

### 4.2 套Hann window

```text
w[n] = 0.5 * (1 - cos(2*pi*n/(N-1))), n=0...N-1
windowed[n] = centered[n] * w[n]
window_power = sum(w[n]^2)
```

Hann window把4秒資料頭尾平滑壓到接近0，降低截斷造成的頻譜洩漏。

### 4.3 執行400點real FFT

使用Swift Accelerate／vDSP或其他FFT函式庫，取得`k=0...200`的複數結果：

```text
FFT[k] = real[k] + j * imag[k]
```

App不能直接把FFT magnitude當PSD，還必須做以下正規化：

```text
psd[k] = (real[k]^2 + imag[k]^2) / (fs * window_power)
```

轉成one-sided PSD：

```text
psd[1...199] *= 2
psd[0]與psd[200]不乘2
```

每軸PSD單位為`(deg/s)^2/Hz`。若所使用的FFT函式庫會額外除以N或乘上縮放係數，
必須調整至與Python參考結果一致，不能只看圖形形狀像不像。

## 5. 三軸合併與主要頻率

三軸完成PSD後，同一個frequency bin相加：

```text
psd_sum[k] = psd_x[k] + psd_y[k] + psd_z[k]
frequency[k] = k * 0.25
```

不要先算`sqrt(x^2+y^2+z^2)`再做FFT，因為取絕對值會改變波形並產生假倍頻。

3–7 Hz對應bin 12–28：

```text
peak_index = argmax(psd_sum[12...28])
candidate_frequency_hz = peak_index * 0.25
```

`candidate_frequency_hz`只是最高點；通過第7節的可靠度條件後，才能顯示成
`dominant_frequency_hz`。

## 6. 計算4–6 Hz震顫強度

4–6 Hz對應bin 16–24，`df=0.25 Hz`：

```text
power_4_6 = sum(psd_sum[k] * 0.25), k=16...24
tremor_strength_rms_dps = sqrt(power_4_6)
```

三軸個別強度也以相同方式計算：

```text
power_x_4_6 = sum(psd_x[k] * 0.25), k=16...24
power_y_4_6 = sum(psd_y[k] * 0.25), k=16...24
power_z_4_6 = sum(psd_z[k] * 0.25), k=16...24
```

`power_4_6`單位為`(deg/s)^2`；開根號後的`RMS`單位為`deg/s`，App主圖使用RMS。

## 7. 何時可以顯示主要頻率

以下是prototype的防亂顯示規則，不是疾病診斷門檻。
前提是 `data_valid=true`；三個特徵均針對同一份 400 筆視窗。

```text
vector_rms = sqrt(mean(centered_x^2 + centered_y^2 + centered_z^2))
power_0_5_15 = sum(psd_sum[k] * 0.25), k=2...60
power_3_7 = sum(psd_sum[k] * 0.25), k=12...28
peak_power = candidate前後0.5 Hz的power，也就是peak_index前後2格

tremor_band_fraction = power_3_7 / (power_0_5_15 + 1e-12)
peak_concentration = peak_power / (power_3_7 + 1e-12)
```

三條同時成立才令`frequency_reliable=true`：

- `vector_rms >= 0.20 deg/s`
- `tremor_band_fraction >= 0.30`
- `peak_concentration >= 0.45`

若不成立，強度圖仍可顯示有效的4–6 Hz RMS，但主要頻率顯示`--`，並顯示
「目前沒有清楚的主要震顫頻率」。

`vector_rms` 使用去平均但**尚未套 Hann**的三軸資料，不能以 §6 的 4–6 Hz
band RMS 代替。`peak_power` 必須累加五個 bin（`peak_index-2...peak_index+2`），
不能只取最高單一 bin。為維持與目前 Python V1 相同的數值，本版仍未將這五個 bin
裁切至 3–7 Hz；因此邊界的 `peak_concentration` 可能大於 1，不得假設它是嚴格的
0–1 信心分數。日後若修改此邊界規則，需同步更新 Python、App、規格與基準輸出版本。

本版比較條件為上述 `>=`。§10 的數值誤差容許量不代表可自行降低分類門檻；
App 額外減去 `1e-4` 的處理須移除，或先以邊界案例提出跨平台比較策略並同步定版。

### 7.1 2026-09-12 App 差異核對

已核對 [TremorAnalyzer.swift](https://github.com/KevlnlOl7/SteadyHope/blob/56805c93c46af81fb922af7780a8841a07258b39/software/iOS-App/Glove/Algorithms/TremorAnalyzer.swift#L109-L134)：

| 項目 | 該提交的 App 實作 | 本文件要求 |
|---|---|---|
| `vectorRms` | 等於 4–6 Hz band RMS | 去平均後的三軸整體 RMS |
| 頻帶占比分母 | 全部 0–50 Hz PSD | 0.5–15 Hz PSD |
| 主峰集中度分子 | 最高單一 bin | 主峰前後 0.5 Hz、共五個 bin |
| 門檻 | 0.20／0.30／0.45，各減 `1e-4` | 0.20／0.30／0.45，依上文比較策略 |

這是**公式對齊工作**，不能只把書面整理中的 `0.55` 改成 `0.30` 就視為完成。
硬體 Gate 的 `0.55` 是另一種包絡比例，不放入本節 PSD 判斷。

### 7.2 三種旗標各自代表什麼

| 欄位 | 意義 | 不可據此推論 |
|---|---|---|
| `data_valid` | 視窗資料品質是否符合要求 | 資料有效就表示有震顫 |
| `frequency_reliable` | 是否符合本版候選主頻回報條件 | true 就是一次事件開始、false 就是震顫停止 |
| `motor_enabled` | wire 舊名；`motor_output_active`，表示完整控制鏈已套用非零命令 | 不等於原始 Gate、實際馬達位移或抑震有效 |

本次規格沒有把上述三者做 AND／OR 定義成患者震顫事件。事件功能另見 §12。

## 8. 完整流程pseudocode

```text
onBleRecord(bytes):
    sample = parseLittleEndian16ByteRecord(bytes)
    sample.x = sample.gyro_x_raw / 16.0
    sample.y = sample.gyro_y_raw / 16.0
    sample.z = sample.gyro_z_raw / 16.0
    sample.recorded_at_utc_ms = session_start_utc_ms
                              + unsignedDelta(sample.sample_tick_ms,
                                              session_start_sample_tick_ms)
    rawBuffer.append(sample)
    rawBuffer.keepLatest(400)
    newSampleCountSinceLastAnalysis += 1
    updateMotorCommandBackground(sample.recorded_at_utc_ms, sample.motor_enabled)

    if rawBuffer.count < 400:
        showAccumulating()
        return

    if newSampleCountSinceLastAnalysis < 50:
        return
    newSampleCountSinceLastAnalysis = 0

    window = rawBuffer.latest(400)
    if sequenceGap(window) or badTimestamp(window) or invalidSensor(window) or nonFiniteGyro(window):
        appendChartGap(window.last.recorded_at_utc_ms)
        showDataInvalid()
        saveAnalysisRecord(time=window.last.recorded_at_utc_ms,
                           dataValid=false, frequencyReliable=false,
                           dominantFrequency=null, strengthRms=null,
                           motorCommandActiveFraction=null, gapReason=qualityFailure)
        return

    psdX = oneSidedPSD(window.x, fs=100, hann=true)
    psdY = oneSidedPSD(window.y, fs=100, hann=true)
    psdZ = oneSidedPSD(window.z, fs=100, hann=true)
    psdSum = psdX + psdY + psdZ

    peakIndex = argmax(psdSum[12...28])
    candidateHz = peakIndex * 0.25
    strengthRms = sqrt(sum(psdSum[16...24]) * 0.25)
    motorCommandActiveFraction = validLatest50MotorFlags(window)
                      ? mean(motor_enabled of latest 50 samples) : null
    reliable = checkFrequencyEvidence(...)

    append60SecondPoint(
        time=window.last.recorded_at_utc_ms,
        strength=strengthRms
    )
    showFrequency(reliable ? candidateHz : null)
    saveAnalysisRecord(time=window.last.recorded_at_utc_ms,
                       dataValid=true, frequencyReliable=reliable,
                       dominantFrequency=reliable ? candidateHz : null,
                       strengthRms=strengthRms, motorCommandActiveFraction=motorCommandActiveFraction)
    // 保存分析紀錄不更新「最後震顫時間」，也不增加震顫事件次數。
```

`saveAnalysisRecord` 表示修訂後的資料語意，並非宣稱現有 Swift API 已支援；
無效狀態／`gapReason` 若另存品質紀錄，後端與 App 須共同保留可對齊的時間缺口。

## 9. App圖表怎麼使用結果

使用者首頁：

- 大字：目前主要震顫頻率`dominant_frequency_hz`，不可靠時顯示`--`。
- 大字：目前4–6 Hz震顫強度`tremor_strength_rms_dps`。
- 折線圖：最近60秒RMS，每0.5秒一點，Y軸從0開始。
- 背景區段：依每筆 `motor_enabled` 標出「完整控制鏈已套用非零命令」的時間；
  不可標成原始 Gate、已確認馬達轉動或抑震成功。
- 狀態文字：資料正常、資料累積中、BLE可能掉包或目前無清楚頻率。

若目的是讓醫生或照護者知道「什麼情況比較容易震顫」，App還要提供活動標記，
例如休息、吃飯、喝水、寫字、走路、服藥後及其他。時間只能回答「何時」，
`activity_tag`與使用者備註才能回答「當時在做什麼」。

每0.5秒分析結果建議儲存：

```text
session_id
recorded_at_utc_ms
dominant_frequency_hz          // nullable
tremor_strength_rms_dps        // nullable
motor_command_active_fraction              // 最近0.5秒套用非零命令比例0...1
data_valid
frequency_reliable
activity_tag
note
```

工程／詳細頁面可以另外顯示最近4秒三軸raw Gyro及`psd_sum[12...28]`，但不能把
PSD尖峰圖誤當成使用者的時間趨勢圖。

### 9.1 品質旗標、馬達命令比例與上傳

沿用遠端 `0117ca0` 的語意與規範欄位名 `motor_command_active_fraction`。
App `56805c9` 目前仍用 `motorOnFraction`；若既有 API 保留此舊名，須與後端明確
記錄欄位映射／版本，不能單端改名造成無法解碼。計算窗口維持最近 50 筆平均。
BLE 的 `motor_enabled` wire 名稱不變，其值代表套用非零命令，不是 Gate permission。

- `frequency_reliable` 必須保存分析器實際輸出，不能固定寫成 `true`。
- `data_valid=true`、`frequency_reliable=false`：仍可保存有效的 band RMS，
  `dominant_frequency_hz=null`。資料無效時強度也為 `null`，不能補成 0。
- **本 V1 的 `motor_command_active_fraction` 是最近 50 筆（名目 0.5 秒）的平均**，不是 400 筆。
  全部旗標有效且為 0／1 時，`sum(latest50.motor_enabled) / 50`；例如只有 1 筆為 1，
  結果是 `0.02`，不能用「有任一筆啟動」轉成 `1.0`。400 筆的平均若有分析需求，
  必須另命名並註明其 4 秒窗口，不能取代本欄位。
- 無法取得連續有效的 50 筆或旗標不合法時，馬達比例為未知；需以 nullable 欄位或
  獨立品質狀態表達，不能使用 0 代表未知。這是介面修訂要求，現有非 nullable DTO
  需由 App 與後端同步處理。
- 「最新一筆馬達狀態」「最近 50 筆有任一啟動」「最近 50 筆啟動比例」是不同資料，
  UI 布林提示不能覆蓋上傳用比例。
- 0.5 秒分析可批次上傳；若僅每約 3 秒保存摘要，必須標示這是取樣摘要，不能以摘要
  筆數代表震顫次數，也不能把每個重疊視窗的 4 秒直接相加為震顫時長。

## 10. App驗收標準

先讀取`algorithms/validation/fixtures/tremor_5hz.csv`，不可先接BLE。正確結果：

| 輸出 | 預期值 |
|---|---:|
| 主要頻率 | 5.00 Hz，FFT bin 20 |
| 頻率間距 | 0.25 Hz |
| 三軸4–6 Hz power | 約72.5000 `(deg/s)^2` |
| 三軸4–6 Hz RMS | 約8.5147 `deg/s` |
| X軸power | 約50.0000 `(deg/s)^2` |
| Y軸power | 約18.0000 `(deg/s)^2` |
| Z軸power | 約4.5000 `(deg/s)^2` |

允許浮點差異建議：主要頻率必須完全等於同一個0.25 Hz bin；power與RMS相對誤差
小於0.5%。若不一致，優先檢查：是否除以16、Hann公式是否用`N-1`、one-sided內部
bin是否乘2、PSD是否除以`fs*sum(w^2)`，以及是否先分軸再相加。

再用`tremor_noisy_5hz.csv`驗收：主要頻率應為4.75 Hz、4–6 Hz RMS約5.7901 deg/s。
純2 Hz驗收可取`test_vectors/gating_frequency/gating_02hz.csv`中sequence 100–499的
400筆tone資料，將Y、Z設為0；此時不得顯示震顫主要頻率。

### 10.1 BLE byte解析驗收

`algorithms/validation/fixtures/ble_5hz_records.bin`是400筆真正的16-byte little-endian
record，共6400 bytes。App先只做byte解析，確認每筆欄位與
`ble_5hz_expected.json`一致，再把解析後的三軸資料送進FFT／PSD。產生器是
`algorithms/validation/ble_packet_reference.py`。

資料品質錯誤案例列在`algorithms/validation/fixtures/app_quality_cases.json`，包含：

- 只有399筆。
- `sequence`跳號。
- `sample_tick_ms`不連續。
- `sensor_valid=0`。
- 資料完整但訊號太小。

前四種令`data_valid=false`；訊號太小時資料仍完整，所以`data_valid=true`，但
`frequency_reliable=false`且主要頻率顯示`--`。兩種狀態不可混成同一個錯誤。

### 10.2 修訂交付的驗收項目（待 App 執行）

以下是待驗收條件，不代表本次文件修訂已執行 Swift／實機測試。

| 案例 | 必須確認的結果 |
|---|---|
| 既有 `tremor_noisy_5hz.csv` | 主頻 4.75 Hz；band RMS 約 5.790100；vector RMS 約 6.819208；band fraction 約 0.660540；peak concentration 約 0.919102，與同名 expected JSON 比較 |
| 三軸全零、Seq／Tick／Valid 正常 | `data_valid=true`、`frequency_reliable=false`、頻率 null；可保存分析紀錄，不更新最後震顫時間或事件次數 |
| 頻率不可靠但資料有效 | UI 顯示 `--`，上傳仍為 `frequency_reliable=false`，不能改成 true |
| 最新 50 筆僅 1 筆 Motor=1 | `motor_command_active_fraction=0.02`；最新 400 筆中更早的旗標不影響此欄位 |
| 缺樣本／Tick 異常／Valid=0／非有限數值 | 品質缺口及原因可追溯，頻率與強度不以 0 或舊值填補 |
| 斷線再連線 | 實際 callback 清空分析窗口並建立新 session；收滿新的 400 筆才分析，舊待上傳資料仍保留原 session |
| 100 Hz 與 tick 回繞 | 原始資料及分析時間共用 session anchor；不使用 20 ms 備援，不跨重開機延用舊 anchor |

驗收紀錄應保留 App commit、規格修訂日期、輸入資料及中間特徵值；只看到 5 Hz
顯示正確，不能證明三項公式都已對齊。

## 11. 頻帶與控制旗標的界線

App 在 3–7 Hz 搜尋候選主頻；硬體 Gate 的核心比較帶仍是 4–6 Hz 對 1–3 Hz。
兩者是不同用途。`motor_enabled` 回報的是實際套用非零命令的狀態，不能取代
獨立的原始 Gate 旗標，更不能當作患者震顫有無。以下補充說明，不調整控制參數。

### 11.1 硬體組提供給 App 組的判斷依據

2026-09-12 經 GitHub branches API 核對，Ryan 韌體分支最新為
`c08bfcca1921fcfdcb5abe6127e3d36cc4e2d65a`，演算法交付基準為
`0117ca0a85579f0c5c52b026f40b67c67a84c94b`。兩者 `tremor_gate.c` 的 Git blob
相同（`15a9713aee683ed2c27c0a08a592061127395e13`）；Ryan 主程式初始化傳入
`NULL`，沿用下列 Gate 預設。這是已核對的**程式版本**，尚未確認配戴裝置實際燒錄版本。

| 項目 | 已核對的程式規則 | 解讀 |
|---|---|---|
| 輸入 | 名目 100 Hz 的單軸角速度，單位 deg/s；Ryan 設定選 X 軸 | 不同於 App 三軸 PSD 合計或三軸 vector RMS |
| 頻帶 | 同一輸入分別通過 4–6 Hz 與 1–3 Hz 因果帶通 | 比較兩頻帶的訊號成分；沒有使用 `freqEstimate` 做主頻通過／不通過判定 |
| 幅度特徵 | 各頻帶取絕對值，再做峰值保持及衰減包絡；衰減係數 0.94／筆 | 不是 RMS，也不是固定 4 秒窗口功率 |
| 包絡比例 | `E_t / (E_t + E_v + 1e-9)`，`E_t` 為 4–6 Hz 包絡，`E_v` 為 1–3 Hz 包絡 | 不等於 App 的 `P(3–7 Hz) / P(0.5–15 Hz)`；0.55 不是 App 頻率可信度門檻 |
| Gate 由關轉開 | `E_t >= 6.0 deg/s` **且**比例 `>= 0.55`，連續 20 筆均成立 | 100 Hz 下名目確認時間 200 ms；任一筆不成立就清除啟動計數 |
| Gate 由開轉關 | `E_t < 3.0 deg/s` **或**比例 `< 0.45`，連續 15 筆均不符合維持條件 | 100 Hz 下名目確認時間 150 ms；重新符合維持條件就清除解除計數 |
| 中間區域 | 啟動、維持使用不同門檻，保留既有開關狀態 | 這是遲滯設計，不能只寫一個 0.55 條件描述全部狀態 |
| 異常中止 | 無效輸入、配置／數值異常及控制鏈拒收舊樣本等，另走清除或停止路徑 | 不適用一般 150 ms 解除等待，也不能解讀成觀測到患者震顫停止 |

包絡的精確遞迴為 `E[n] = max(abs(bandpass_output[n]), 0.94 * E[n-1])`。
20／15 筆描述的是濾波後條件的確認計數，**不是患者震顫已持續的時間**；濾波與
包絡也有暫態，因此不能宣稱裝置會在生理震顫開始後恰好 200 ms 啟動。
4–6 Hz 是濾波器通帶，不是理想的頻率切割線；不能承諾通帶外所有訊號必定不觸發。

來源：

- [交付版 Gate 計算與預設](https://github.com/KevlnlOl7/SteadyHope/blob/0117ca0a85579f0c5c52b026f40b67c67a84c94b/algorithms/handoff/src/gating/tremor_gate.c)
- [MATLAB 頻帶設計](https://github.com/KevlnlOl7/SteadyHope/blob/0117ca0a85579f0c5c52b026f40b67c67a84c94b/algorithms/matlab/gating_sim.m#L40-L42)
- [Gate 單軸與 100 Hz 輸入契約](https://github.com/KevlnlOl7/SteadyHope/blob/0117ca0a85579f0c5c52b026f40b67c67a84c94b/algorithms/handoff/src/gating/tremor_gate.h)
- [Ryan 初始化採預設配置](https://github.com/KevlnlOl7/SteadyHope/blob/c08bfcca1921fcfdcb5abe6127e3d36cc4e2d65a/firmware/algo/CM7/Core/Src/main.c#L1901-L1907)
- [Ryan 軸向配置](https://github.com/KevlnlOl7/SteadyHope/blob/c08bfcca1921fcfdcb5abe6127e3d36cc4e2d65a/firmware/algo/CM7/Core/Inc/motor_bench_config.h)

Gate 是拉線控制的觸發條件之一。Ryan 目前還有拉線、保持、回程及 App 調整長度
等狀態；保持時可以沒有非零馬達命令，Gate 解除後的回程在其他安全條件通過時
仍可能有命令。
因此 `motor_enabled=0` 不代表 Gate 關閉，`motor_enabled=1` 也不代表 Gate 開啟。
[控制狀態與實際 wire 來源](https://github.com/KevlnlOl7/SteadyHope/blob/c08bfcca1921fcfdcb5abe6127e3d36cc4e2d65a/firmware/algo/CM7/Core/Src/main.c)

### 11.2 App 的「資料與判斷方式」說明

在趨勢圖旁提供「資料與判斷方式」入口；首頁顯示簡短文字，完整公式及上表放在
可展開的「詳細規則」。以下是**待 App 組實作的文案與行為規格**，不是已完成的畫面。

可直接使用的簡短文案：

> 裝置記錄配戴部位的動作訊號，呈現抖動相關的頻率與角速度強度，供回診時參考。
> 可搭配您自行填寫的活動及服藥時間，查看當時的紀錄變化。
>
> 頻率顯示「--」時，請查看資料狀態：可能是資料不足、中斷，或暫時沒有清楚的
> 主要頻率；不代表一定沒有抖動。
>
> 裝置作動標記表示控制命令送出的時段，不能直接當作抖動的開始、結束或改善程度。
> 本紀錄不能單獨判定病程或服藥療效。

說明頁可另外列出設計目標：「本專題優先減少需要介入時未觸發的情況，因此容許
部分日常動作也觸發裝置。」這是設計取捨，不能寫成已證明不會漏掉患者震顫。

| App 說明項目 | 要讓使用者知道的內容 |
|---|---|
| 頻率 | 目前規格在 3–7 Hz 搜尋主要頻率；資料與頻率品質條件通過後才顯示。未通過時保留原因，不顯示為 0 Hz |
| 強度 | 顯示的是 4–6 Hz 角速度 RMS，單位 deg/s；不是手部位移距離或疾病分期。詳細頁另列 App 三項可信度公式及 0.20／0.30／0.45 工程門檻，見 §7 |
| 裝置作動 | 圖例建議寫「裝置作動（命令紀錄）」；詳細說明為控制鏈成功套用非零馬達命令。不要命名為「震顫事件」或「抑震成功」 |
| 活動與服藥 | 來自使用者自行填寫的實際時間；未填寫不推測成已服藥、未服藥或特定活動，也不自動生成療效結論 |
| 判斷規則版本 | 顯示分析規則修訂及適用韌體版本；連線裝置版本尚未核對時顯示「裝置版本／參數待確認」，不能把參考預設冒充本次實際設定 |

詳細規則要將「App 頻率可信度」與「硬體 Gate」分開列出，並標示硬體門檻是本專題
的工程配置。3–7 Hz 及頻譜分析有研究背景，但不能替本專題所有數值背書：
[Timmermans et al.（2025）](https://www.nature.com/articles/s41531-025-01056-2)
使用 4 秒視窗、MFCC 分類器、3–7 Hz 頻率條件及動作排除；其臨床驗證不能轉用為
本 Gate 的 6／3 deg/s、0.55／0.45、200／150 ms，或 App 三項門檻的驗證。

### 11.3 硬體交付與 App 驗收

硬體組需提供實際燒錄的 commit／build、取樣率、使用軸向、Gate 參數及配置識別，
讓 App 說明與該次紀錄可追溯。可先隨交付紀錄人工核對；現有 16-byte sample
沒有完整 Gate 配置或原始 Gate 狀態，本節不宣稱新增欄位已可由 BLE 讀取。

如果後續要統計 Gate 區段，需另定義帶時間及有效性的獨立 Gate 遙測，並區分
一般門檻解除、資料中斷及控制故障等原因；App 與硬體確認協定版本後再實作。
App 從原始 IMU 另行重算的 Gate 若未驗證與韌體一致，只能標示為重算結果，不能
冒充硬體回報。患者震顫事件仍依 §12 另定義與驗證，不能靠新增說明頁補成已完成。

待 App 驗收：說明入口可達；缺資料與無可靠頻率能區分；Gate 與命令狀態未互相
代用；版本未知不顯示為已核對；無服藥紀錄不生成服藥標記；分析紀錄不計成事件。

### 11.4 控制觸發的設計優先序：減少漏觸發

依專題團隊於 2026-09-12 補充的指導目標，控制觸發**優先減少患者需要介入時
沒有啟動的情況，容許部分額外觸發**。健康日常動作的低 Gate 啟用比例不能作為
唯一調參目標；六位健康受試者資料用來衡量非目標活動的額外 Gate 啟用，實際
機械干擾另行量測。這項取捨不代表現有配置已達到足夠的患者敏感度，也不授權
移除資料有效性、行程、故障或停止保護。

現有硬性包絡比例條件會在自主動作較強時抑制啟用，與上述目標有衝突風險。
固定版本 `0117ca0` 的合成測試中，2 Hz 與 5 Hz 的 peak 振幅同為 10 deg/s，
或同為 20 deg/s 時，4 秒目標訊號段均為 0/400 筆啟用；這是優先檢討 ratio
硬性否決條件的依據。合成訊號只用於定位漏觸發機制，不能用來宣稱患者敏感度。
[混合訊號結果](https://github.com/KevlnlOl7/SteadyHope/blob/0117ca0a85579f0c5c52b026f40b67c67a84c94b/algorithms/handoff/test_vectors/gating_mixed_boundary/expected_results.csv#L2-L5)

候選配置的離線評估順序如下；本次僅補規格，尚未選定新門檻或修改韌體：

| 優先序 | 指標與要求 |
|---|---|
| 1 | 事先獨立標註目標震顫段及希望介入的情境；列出有效目標段中完全未觸發的段數與比例，不用 Gate 自己產生標籤 |
| 2 | 從目標段開始到首次 Gate 啟用的延遲；完全未啟動另列，不能從延遲統計中消失而不說明 |
| 3 | 有效目標時段內的 Gate 開啟時間占比，觀察是否只短暫觸發後頻繁退出；不以至少開過一次就當作整段覆蓋 |
| 4 | 健康日常活動的額外啟用時間、次數及可量測的機械干擾，用來描述提高觸發率的代價 |

先在同一組既有訊號比較 ratio 條件的放寬或改為輔助證據，再分別評估幅度及連續
確認條件；頻帶與軸向也是已知影響因素。每次記錄配置及中間特徵，避免同時改多項
而無法辨識原因。後續以獨立、有標註的患者資料確認；健康資料不能估計患者漏判率。
目標段觸發率與時間覆蓋率是不同指標，計算時須註明分母與資料缺口。

Gate 啟用之後是否產生預期的牽引，要由控制器狀態與機械反應另行驗收。Ryan
目前保持狀態可沒有非零命令，回程則可能在 Gate 關閉後繼續；增加 Gate duty
不等於已增加有效抑震。額外觸發仍受機構行程、輸出與停止條件約束。

App 應持續保存符合品質條件的分析資料，不能只在 Gate 或馬達命令開啟時保存。
控制端容許額外觸發的取捨，不改變監測端的資料語意：Gate、命令、分析紀錄與
患者震顫事件分別保存／說明，事件規則仍依 §12 定義及驗證。

## 12. 分析紀錄與事件功能（2026-09-12 補充）

### 12.1 目前可直接修正的分析紀錄

App commit `56805c9` 的 [DataViewModel.swift](https://github.com/KevlnlOl7/SteadyHope/blob/56805c93c46af81fb922af7780a8841a07258b39/software/iOS-App/Glove/ViewModels/DataViewModel.swift#L519-L550)
會在資料有效且距上次保存超過 3 秒時建立 `TremorEvent`。此行為定義的是定期分析
快照；先按「分析紀錄」顯示與保存，不將一筆快照算成一次震顫，也不因此更新
「最後震顫時間」。使用者活動標籤仍可附在對應分析紀錄上。

原交付未完整定義事件起迄，這是演算法與軟體的介面缺口，不能要求 App 自行把
frequency flag、Gate flag 或 3 秒保存間隔組成臨床事件標準。

### 12.2 事件規則尚待定案的項目

| 項目 | 需要明訂的內容 |
|---|---|
| 事件來源 | Gate 觸發區段、另行開發的疑似震顫偵測結果，或使用者自述；來源不能混用 |
| 開始／結束 | 採哪個訊號、何時確認、時間標在觀測點或回推點；含門檻與版本 |
| 分段與合併 | 短暫不成立、跨活動、跨午夜是否切段；不能讓上傳頻率決定事件數 |
| 中斷 | 斷線、無效資料、控制停用以中斷／原因記錄，不當成已觀測的震顫停止 |
| 資料模型 | session、開始、最後有效觀測、可確認的結束、持續時間、是否被中斷、判斷來源及規則版本 |
| 時長計算 | 只計可觀測時間，不累加重疊 4 秒窗口，也不填補未觀測區段 |

如果採 Gate 升降沿，必須有獨立且已確認語意的 Gate 資料，才能命名為
**Gate 觸發區段**。目前 BLE `motor_enabled` 是 `motor_output_active`，只能直接
統計馬達命令作用區段，不能當作原始 Gate 升降沿。控制停用與故障等條件也會使
命令歸零，不能推論為患者震顫停止；關閉原因未知就保留未知。

本次不新增事件最短秒數或新的臨床幅度門檻；待上述事件規則定案後，以另個版本
實作與驗收。這不妨礙先完成 §7、§9.1、§10.2 已明確的公式、保存與時間軸修正。

## 13. 使用告知與研究限制（App 文案草案）

日期：2026-09-12。此節提供可供團隊審閱的告知文字與 App 呈現規格，不是法律
意見、完整研究同意書、完整隱私政策或人體使用授權。正式提供患者前，須由學校
研究倫理／法務等適當窗口核對實際用途、計畫、資料處理及裝置能力。

建議頁名為「使用告知與研究限制」。告知的目的是說明用途、證據及風險，不以
「使用後一切責任自負」轉嫁已知缺陷。文案也不能取代 §7／§9.1 等實作修正。

### 13.1 首次顯示的文字草案

> **SteadyHope 使用告知與研究限制**
>
> **1. 研究原型與用途**
> 本版本為專題研究原型，研究內容包含手部動作紀錄及拉線控制。患者震顫辨識、
> 配戴安全性及抑震效果尚未完成驗證，不能據此宣稱適合患者自行配戴或居家使用。
> 提供的紀錄供觀察與溝通參考，不能替代醫師診斷、治療或專業評估。
>
> **2. 不依 App 自行調整用藥**
> 請勿僅依本系統的頻率、強度或圖表，自行停藥、增減劑量或變更服藥時間。
> 服藥前後的圖表差異不能單獨證明藥物療效或病程變化。
>
> **3. 判斷與資料限制**
> 日常動作可能觸發裝置，也可能在出現震顫時未觸發。設計目標是減少漏觸發，
> 但尚不能保證達成。作動標記不等於已確認的震顫事件或抑震成功；未顯示頻率、
> 沒有作動或資料中斷，也不代表一定沒有震顫。
>
> **4. 拉線風險與停止試用**
> 拉線及固定結構可能造成壓迫、疼痛或活動受限。如出現疼痛、麻木、明顯勒痕、
> 皮膚變色或持續拉扯，請立即停止試用，並通知現場負責人依事先確認的程序
> 停機及協助解除。關閉 App、停止命令或切斷電源，不保證拉線會自動鬆開。
> 若不適持續或有明顯受傷，請尋求醫療協助。
>
> **5. 自行填寫的紀錄**
> 活動、服藥時間及備註由使用者提供；未填寫代表資訊未知。圖表需連同實際活動、
> 服藥情況及資料缺口解讀，不能以缺少紀錄推定沒有服藥或沒有症狀。
>
> **6. 權益與資料告知**
> 閱讀本告知不代表放棄任何法定權利，也不等同同意參加人體研究或所有資料用途。
> 人體研究的參與與退出、資料蒐集及使用範圍，須另有清楚的說明與適用的同意程序。

第 4 點的「停機及協助解除」只是應具備的處置要求，**不是已完成的功能聲明**。
目前未核對實機的獨立停止、解除方式及負責人，不能把本段當作已完整的操作說明。
提供人體配戴前須補上經實際確認的操作步驟、示意圖與聯絡方式；不能用一個
「我同意」按鈕補足缺少停止／解除機構、驗證或適用研究程序的問題。

### 13.2 個人資料告知要另行完成

目前尚未確認完整的資料處理責任單位、保存期限、存放地區及權利申請管道，本節
不憑空填入，不承諾已加密、完全匿名、只存手機或隨時可刪除所有備份。
正式告知需按實際 App／後端流程填寫，至少包含：

- 負責蒐集的單位、聯絡方式、蒐集目的及資料類別。
- 資料利用期間、地區、對象及方式；是否上傳原始 IMU、誰可查看服藥及活動紀錄。
- 查詢、複製、更正、停止利用及刪除等權利的實際申請方式與適用限制。
- 可選擇不提供的資料、不提供時受影響的功能；研究、展示或其他用途的處理安排。

這些是待補內容，尚不是完整可發布的隱私告知；不得用不會開啟的連結或未完成的
頁面代替。個資告知與蒐集／利用的合法依據是不同問題；涉及第 6 條所列醫療等
資料時須另確認其適用依據及同意要求，不能以一般勾選一概處理。
[個資法第 8 條](https://law.moj.gov.tw/LawClass/LawSingle.aspx?pcode=I0050021&flno=8)、
[第 6 條](https://law.moj.gov.tw/LawClass/LawSingle.aspx?pcode=I0050021&flno=6)。

### 13.3 App 呈現要求

- 首次使用顯示重點，設定頁及趨勢頁可隨時重新閱讀；文字可放大，不只藏在頁尾。
- 閱讀確認可寫「我已閱讀並了解用途、限制與風險」；不預先勾選，不寫「我承擔一切責任」。
- 提供離開或暫不參與的選項；閱讀確認不自動啟動馬達、量測或資料上傳。
- 人體研究同意、資料處理告知及必要的個別用途同意，依適用程序分別處理；不由閱讀確認取代。
- 保存告知版本與適用 App／韌體版本，實際聯絡窗口與停止／解除方式須能查到。
- 機械拉扯風險也要在裝置操作說明中呈現；僅在 App 顯示文字不足以教會實際解除。

### 13.4 法規核對依據與不能使用的說法

下列為 2026-09-12 查閱的台灣官方來源，說明告知文案的界線；不據此斷言本專題
已符合全部法規、一定屬特定器材等級，或某份免責條款必定有效。

- [民法第 222 條](https://law.moj.gov.tw/LawClass/LawSingle.aspx?pcode=B0000001&flno=222)
  明定故意或重大過失責任不得預先免除。若屬消保法所規範的商品／服務責任，
  [消保法第 10-1 條](https://law.moj.gov.tw/LawClass/LawSingle.aspx?pcode=J0170001&flno=10-1)
  另有限制預先免責的規定；本專題是否適用須看實際關係，不能直接套定。
- [TFDA 醫療器材新手上路](https://www.fda.gov.tw/tc/siteContent.aspx?sid=11754)
  依醫療器材管理法第 3 條說明設計、使用功能與分類。若用途包含疾病緩解或調節
  人體機能，須核對器材屬性；不能靠「非醫療器材」「僅供參考」自行排除管理。
- 若屬人體研究，[人體研究法第 5 條](https://law.moj.gov.tw/LawClass/LawSingle.aspx?pcode=L0020176&flno=5)
  原則要求事前倫理審查，並有公告免審範圍；研究同意的告知內容另見
  [第 14 條](https://law.moj.gov.tw/LawClass/LawSingle.aspx?pcode=L0020176&flno=14)。
  App 告知不取代適用的審查、免審認定或研究同意。現有對話未核對相關核准文件，
  不推定已核准，也不直接斷言一定未核准。

避免使用「保證安全」「準確偵測每次震顫」「已證明抑震有效」「停止即自動鬆開」
「非醫療器材，所以不需相關審查」「使用者放棄一切求償權」等缺乏依據或可能誤導的文字。
