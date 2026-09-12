# App端 FFT／PSD 實作流程（從BLE資料到震顫圖）

日期：2026-07-28

修訂：2026-09-12，補充 App 程式核對、分析紀錄與事件語意、品質旗標及中斷處理。
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
獨立的原始 Gate 旗標，更不能當作患者震顫有無。這次不新增觀察分類器或控制參數。

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
