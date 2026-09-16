# V2 gating 離線強健性模擬

這個目錄記錄 V2 gating 在合成 GyroX 訊號下的延伸測試。目的不是證明裝置已能抑震，而是先找出上板及人體測試前應注意的邊界條件。

## 固定條件

- gating filter 係數仍按照 100 Hz 設計。
- 輸入模擬 BNO055 GyroX，單位為 `deg/s`，並量化為 `1/16 deg/s`。
- 每組訊號共 7 秒：0–1 秒靜置、1–5 秒測試訊號、5–7 秒靜置。
- 使用目前 `tremor_gate` 的預設門檻與狀態機。
- 所有結果均為合成訊號，不是患者資料、實機馬達結果或真實抑震率。

## 檔案與結果

### `amplitude_sweep.csv`

測試 1–8 Hz，各使用 2、4、6、8、10、15、20 deg/s peak。

- 4 Hz 在 15 deg/s 才啟動，約延遲 670 ms。
- 5 Hz 在 10 deg/s 開始啟動，約延遲 620 ms。
- 6 Hz 在 15 deg/s 才啟動，約延遲 490 ms。
- 頻帶外唯一觀察到的誤啟動為 7 Hz、20 deg/s；約延遲 390 ms，測試訊號期間啟用比例約 90.25%。

這代表 `amp_on = 6` 不是「原始 GyroX 超過 6 deg/s 就開啟」。輸入先經過 band-pass filter，因此實際觸發振幅會隨頻率而變；7 Hz 又接近 4–6 Hz filter 的邊界，高振幅仍可能漏進來。

### `mixed_2hz_5hz_sweep.csv`

同時輸入 2 Hz 自主動作與 5 Hz 震顫，改變兩者振幅。

- 單獨 5 Hz、15 deg/s 時，啟用比例約 89.75%。
- 2 Hz 與 5 Hz 都是 10 deg/s 時沒有啟動。
- 2 Hz 為 20 deg/s 以上時，本次測試中即使 5 Hz 到 20 deg/s 也沒有啟動。

V2 判斷的是兩個頻帶的相對強度，因此強烈自主動作可能讓震顫比例不足。這是避免正常動作誤啟動的代價，也是真實資料必須校調的項目。

### `sample_rate_sweep.csv`

filter 係數保持 100 Hz，但實際資料分別以 95、100、105 Hz 產生。

- 95 Hz 與 100 Hz 下，4、5、6 Hz、15 deg/s 都能啟動。
- 105 Hz 下，5 Hz 與 6 Hz 能啟動，但 4 Hz 沒有啟動。

固定係數會隨實際取樣率偏移頻帶。特別是 4 Hz 位於下邊界，因此不能只看平均取樣率；STM32 應維持 100 Hz 定拍並保存取樣時間供檢查。

### `jitter_sweep.csv`

`jitter` 是「取樣時間間隔不固定」。理想的 100 Hz 應該每 10 ms 取得一筆資料，但 STM32 可能因為 timer、I2C 或其他工作而提早或延後。例如：

- ±1 ms：每筆間隔可能落在 9–11 ms。
- ±2 ms：每筆間隔可能落在 8–12 ms。
- ±4 ms：每筆間隔可能落在 6–14 ms。

本測試使用 5 Hz、15 deg/s 訊號，分別加入最大 ±0、±1、±2、±4 ms 的取樣間隔誤差，每種跑 5 次。每一筆誤差都在指定範圍內重新產生，不是把所有資料一起平移相同時間。

這裡的 `deterministic` 不是指誤差固定不變，而是程式使用固定的亂數種子。相同版本每次執行都會得到完全相同的誤差順序，讓組員、老師及 GitHub 自動測試能重現並核對結果；真實 STM32 的 jitter 不會剛好等於這五組模擬序列。

gating filter 仍按照每筆相隔 10 ms、100 Hz 的條件運算。因此這項測試是在觀察：資料實際到達時間不規則，但演算法仍假設固定 100 Hz 時，馬達開關判斷會受到多少影響。

- 所有測試都能啟動。
- 啟動延遲約落在 429–520 ms。
- 這只表示目前這 20 組可重現的合成測試沒有漏判，不代表其他 jitter 或真實 STM32 時序一定安全。

### `dropout_sweep.csv`

測試 5 Hz、15 deg/s，加入週期性 2%、隨機 5% 或連續 200 ms 掉點，並比較四種處理策略。

- `hold_last`：重複上一筆資料。
- `zero_fill`：遺失資料補 0。
- `nan_fail_safe`：輸入無效值，gating 立即關閉並清除 debounce 計數。
- `skip_update`：不更新 filter，沿用當前開關狀態。

`nan_fail_safe` 的啟用比例最低，因為每次無效資料都會關閉；其他策略較能維持輸出，但可能掩蓋資料過期。這是安全需求取捨，不能只用「馬達開得比較久」決定哪個最好。BLE/App 應另外標示資料不足，STM32 也要明確選定 policy。

## 重現方式

在 repo 根目錄執行：

```powershell
python algorithms/validation/gating_robustness_sim.py
python -m unittest discover -s algorithms/validation -p "test_gating_robustness_sim.py"
```

產生器與測試分別位於：

- `algorithms/validation/gating_robustness_sim.py`
- `algorithms/validation/test_gating_robustness_sim.py`

## 下一步實測

離線結果可決定實機測試的優先順序，但不能取代實測：

1. 用 STM32 timer 保存每筆資料的時間差，確認實際取樣率，以及取樣間隔偏離 10 ms 的程度。
2. 以板上測試資料確認 7 Hz 高振幅是否真的可能誤開。
3. 錄製慢速自主動作疊加模擬震顫，校調頻帶比例門檻。
4. 人員測試前先斷開馬達，只確認 sensing 與 enabled；通過後才進入有限位、限流的機構作動測試。
