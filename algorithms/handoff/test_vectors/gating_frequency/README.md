# STM32 V2 gating 固定頻率測試向量

這組資料用來回答一個問題：同一份 `tremor_gate.c` 放到 STM32 後，是否只在
4–6 Hz 測試輸入下輸出 `enabled=1`。資料是演算法注入測試，不是真人震顫資料，
測試時先斷開馬達或禁止 H-bridge 輸出。

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
| 測試頻率 | 1、2、3、4、5、6、8 Hz |

預期結果：

- 1、2、3、8 Hz：`enabled` 全程維持0。
- 4、5、6 Hz：訊號開始後，`enabled` 應由0變成1；訊號停止後應回到0。
- 啟動不會剛好在訊號出現的瞬間，因為帶通濾波器需要建立狀態，且gating要求
  條件連續成立20筆。

## 給韌體組的檔案

- `gating_frequency_vectors.h`：七組 `int16_t` C陣列，可直接編進STM32測試模式。
- `gating_01hz.csv` 至 `gating_08hz.csv`：相同資料的人類可讀版本。
- `manifest.json`：共同參數及每組資料的預期開關類別。
- `expected_results.csv`：目前交付版`tremor_gate.c`在PC逐筆執行的參考結果。

每一個CSV欄位：

| 欄位 | 型態／單位 | 說明 |
|---|---|---|
| `sequence` | `uint32` | 從0開始的取樣編號 |
| `sample_tick_ms` | `uint32` / ms | STM32開機後的取樣計時，每筆增加10 ms |
| `gyro_x_raw_lsb` | `int16` | 模擬BNO055暫存器原始值 |
| `gyro_x_dps` | `float` / deg/s | `gyro_x_raw_lsb / 16.0` |
| `segment` | text | 靜置或固定頻率段，僅供檢查 |

## STM32注入方式

不要同時讀真實BNO055。測試模式每次TIM6 100 Hz tick取出一筆：

```c
#include "gating_frequency_vectors.h"

static uint32_t test_index = 0U;
static uint32_t test_vector = 4U; /* index 4 = 5 Hz */

void Algorithm_Test_Tick(void)
{
    double gyro_x_dps =
        (double)GATING_TEST_GYRO_X_RAW_LSB[test_vector][test_index] /
        GATING_TEST_RAW_LSB_PER_DPS;
    uint8_t enabled = TremorGate_Update(&tremor_gate, gyro_x_dps);

    /* 將 test_index、gyro_x_dps、env、ratio、enabled 記錄或送出。 */
    test_index++;
    if (test_index >= GATING_TEST_SAMPLE_COUNT) {
        test_index = 0U;
        TremorGate_Reset(&tremor_gate);
    }
}
```

每換一組頻率前必須呼叫 `TremorGate_Reset()`，否則上一組的IIR與envelope狀態會
污染下一組結果。板上至少記錄：`test_index`、`gyro_x_dps`、
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
