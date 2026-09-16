# STM32 V2 gating 固定頻率測試向量

這組資料用來回答一個問題：同一份 `tremor_gate.c` 放到 STM32 後，是否只在
4–6 Hz 測試輸入下輸出 `enabled=1`。資料是演算法注入測試，不是真人震顫資料，
第一階段先禁止 H-bridge 輸出並確認控制命令；結果正確後，第二階段才接馬達與
非人體負載，確認馬達及機構能否實際跟隨4–6 Hz命令。

## 固定條件

| 項目 | 規格 |
|---|---|
| 輸入軸 | `GyroX` |
| 取樣率 | 100 Hz（每10 ms一筆） |
| BNO055比例 | `gyro_dps = raw_lsb / 16.0` |
| 峰值振幅 | 15 deg/s |
| 每組長度 | 7秒，共700筆 |
| 0–1秒 | 靜置，0 deg/s |
| 1–5秒 | 固定頻率正弦波 |
| 5–7秒 | 靜置，0 deg/s |
| 測試頻率 | 1～8 Hz，共八組 |

預期結果：

- 1、2、3、7、8 Hz：`enabled` 全程維持0。
- 4、5、6 Hz：訊號開始後，`enabled` 應由0變成1；訊號停止後應回到0。
- 啟動不會剛好在訊號出現的瞬間，因為帶通濾波器需要建立狀態，且gating要求
  條件連續成立20筆。

## 給韌體組的檔案

- `gating_frequency_vectors.h`：八組 `int16_t` C陣列，可直接編進STM32測試模式。
- `gating_01hz.csv` 至 `gating_08hz.csv`：相同資料的人類可讀版本。
- `manifest.json`：共同參數及每組資料的預期開關類別。
- `expected_results.csv`：目前交付版`tremor_gate.c`在PC逐筆執行的參考結果。
- `expected_trace.csv`：每一筆的輸入、envelope、ratio、counter與`enabled` golden結果。

每一個CSV欄位：

| 欄位 | 型態／單位 | 說明 |
|---|---|---|
| `sequence` | `uint32` | 從0開始的取樣編號 |
| `sample_tick_ms` | `uint32` / ms | STM32開機後的取樣計時，每筆增加10 ms |
| `gyro_x_raw_lsb` | `int16` | 模擬BNO055暫存器原始值 |
| `gyro_x_dps` | `float` / deg/s | `gyro_x_raw_lsb / 16.0` |
| `segment` | text | 靜置或固定頻率段，僅供檢查 |

## STM32注入方式

`GATING_TEST_GYRO_X_RAW_LSB[頻率索引][取樣索引]` 是韌體需要逐筆讀取的測試輸入：

| 頻率索引 | 測試頻率 |
|---:|---:|
| 0 | 1 Hz |
| 1 | 2 Hz |
| 2 | 3 Hz |
| 3 | 4 Hz |
| 4 | 5 Hz |
| 5 | 6 Hz |
| 6 | 7 Hz |
| 7 | 8 Hz |

測試模式不要同時使用真實BNO055作為演算法輸入。每次TIM6 100 Hz tick只取一筆
`int16_t` raw資料，除以16轉成deg/s後，再送入`TremorGate_Update()`：

```c
#include "tremor_gate.h"
#include "gating_frequency_vectors.h"

static uint32_t test_sample_index = 0U;
static uint32_t test_vector_index = 4U; /* index 4 = 5 Hz */
static uint8_t test_finished = 0U;

void Algorithm_Test_Tick(void)
{
    double gyro_x_dps;
    uint8_t enabled;

    if (test_finished != 0U) {
        return;
    }

    gyro_x_dps =
        (double)GATING_TEST_GYRO_X_RAW_LSB
            [test_vector_index][test_sample_index] /
        GATING_TEST_RAW_LSB_PER_DPS;
    enabled = TremorGate_Update(&tremor_gate, gyro_x_dps);

    /* 將sample index、gyro、envelope、ratio、enabled記錄或送出。 */
    test_sample_index++;
    if (test_sample_index >= GATING_TEST_SAMPLE_COUNT) {
        test_finished = 1U;
    }
}
```

每組資料共700筆、執行7秒。完成後應停在`test_finished=1`，不要立即循環，以免
難以辨認測試起點。每換一組頻率前，將`test_sample_index`與`test_finished`清為0，
並呼叫`TremorGate_Reset()`；否則上一組的IIR與envelope狀態會污染下一組結果。

若第二階段要連同馬達方向與PWM一起測試，同一筆`gyro_x_dps`必須同時送進
`TremorGate_Update()`與原本產生`tremorEstimate`的演算法。不可讓gating使用測試
陣列，但`tremorEstimate`仍使用真實BNO055，否則馬達開關與馬達方向會來自不同
訊號。`freqEstimate`只可觀察，不可用於gating或App震顫頻率。

板上至少記錄：`test_vector_index`、`test_sample_index`、`gyro_x_dps`、
`tremor_envelope`、`voluntary_envelope`、`tremor_ratio`、`enabled`。

目前C版參考結果（訊號從1000 ms開始）：

| 頻率 | 首次enabled | 相對訊號開始延遲 | 4秒訊號段enabled筆數 | 結尾 |
|---:|---:|---:|---:|---:|
| 1 Hz | never | never | 0/400 | 0 |
| 2 Hz | never | never | 0/400 | 0 |
| 3 Hz | never | never | 0/400 | 0 |
| 4 Hz | 1670 ms | 670 ms | 333/400 | 0 |
| 5 Hz | 1520 ms | 520 ms | 348/400 | 0 |
| 6 Hz | 1490 ms | 490 ms | 351/400 | 0 |
| 7 Hz | never | never | 0/400 | 0 |
| 8 Hz | never | never | 0/400 | 0 |

STM32若使用同一份C與同一份raw陣列，`enabled`應逐筆一致。上述延遲包含濾波器建立
狀態及連續20筆的開啟條件，因此不能只用200 ms估算總延遲。

## 重新產生

在repo根目錄執行：

```powershell
python algorithms/validation/generate_gating_frequency_vectors.py
```

不要手動修改CSV或header內的數字；要改振幅、時間或頻率，應修改產生器後重新產生，
再執行 `algorithms/handoff/test/build_and_run.bat`。

## STM32回傳資料驗收

韌體組回傳CSV最少需要：

```text
frequency_hz,sample_index,gyro_x_dps,enabled
```

建議再包含`tremor_envelope`、`voluntary_envelope`、`tremor_ratio`、
`tremorEstimate`、`pwm_percent`與`motor_direction`。執行：

```powershell
python algorithms/validation/analyze_stm32_gating_log.py `
  --input stm32_gating_log.csv --output-json stm32_result.json
```

工具會檢查取樣編號、100 Hz時序、測試輸入及每一筆`enabled`，並列出和
`expected_trace.csv`的差異數。
