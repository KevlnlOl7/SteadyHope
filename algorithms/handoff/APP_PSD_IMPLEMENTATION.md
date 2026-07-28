# App端 FFT／PSD 實作流程（從BLE資料到震顫圖）

日期：2026-07-28

演算法規格：張傢寧

App實作者：樊柔妤

BLE資料提供：李冠廷

這份文件直接回答「App收到BLE資料後要做什麼」。權威數值參考是
`algorithms/validation/tremor_frequency_reference.py`；App必須使用相同測試CSV，
確認輸出一致後才接實機BLE。

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
| 15 | `motor_enabled` | `uint8` |

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

## 2. 何時開始計算

1. buffer不足400筆：只顯示「資料累積中」，不計算頻率。
2. 收滿400筆後：取最新400筆，也就是最近4秒。
3. 之後每收到50筆新資料再計算一次，也就是每0.5秒更新。
4. 相鄰兩次計算會共用前350筆資料，這是正常的rolling window。

計算前先檢查：

- 400筆`sequence`必須每筆加1。
- 相鄰`sample_tick_ms`必須介於8–12 ms。
- 400筆`sensor_valid`必須全部為1。

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
    updateMotorBackground(sample.recorded_at_utc_ms, sample.motor_enabled)

    if rawBuffer.count < 400:
        showAccumulating()
        return

    if newSampleCountSinceLastAnalysis < 50:
        return
    newSampleCountSinceLastAnalysis = 0

    window = rawBuffer.latest(400)
    if sequenceGap(window) or badTimestamp(window) or invalidSensor(window):
        appendChartGap(window.last.recorded_at_utc_ms)
        showDataInvalid()
        return

    psdX = oneSidedPSD(window.x, fs=100, hann=true)
    psdY = oneSidedPSD(window.y, fs=100, hann=true)
    psdZ = oneSidedPSD(window.z, fs=100, hann=true)
    psdSum = psdX + psdY + psdZ

    peakIndex = argmax(psdSum[12...28])
    candidateHz = peakIndex * 0.25
    strengthRms = sqrt(sum(psdSum[16...24]) * 0.25)
    motorOnFraction = mean(motor_enabled of latest 50 samples)
    reliable = checkFrequencyEvidence(...)

    append60SecondPoint(
        time=window.last.recorded_at_utc_ms,
        strength=strengthRms
    )
    showFrequency(reliable ? candidateHz : null)
```

## 9. App圖表怎麼使用結果

使用者首頁：

- 大字：目前主要震顫頻率`dominant_frequency_hz`，不可靠時顯示`--`。
- 大字：目前4–6 Hz震顫強度`tremor_strength_rms_dps`。
- 折線圖：最近60秒RMS，每0.5秒一點，Y軸從0開始。
- 背景區段：依每筆`motor_enabled`標出馬達允許作動的時間。
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
motor_on_fraction              // 最近0.5秒馬達開啟比例0...1
data_valid
frequency_reliable
activity_tag
note
```

工程／詳細頁面可以另外顯示最近4秒三軸raw Gyro及`psd_sum[12...28]`，但不能把
PSD尖峰圖誤當成使用者的時間趨勢圖。

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
