# STM32 7 Hz高振幅邊界測試包

這個測試包專門確認離線模擬發現的邊界：7 Hz位於目前4–6 Hz目標頻帶外，
但振幅提高後仍可能通過帶通filter邊緣。這是合成資料的演算法注入測試，不是
真人震顫、馬達負載測試或抑震率。

## 測試條件

| 項目 | 規格 |
|---|---|
| 輸入 | 模擬BNO055 GyroX raw `int16_t` |
| 取樣率 | 100 Hz，每10 ms一筆 |
| 頻率 | 固定7 Hz |
| 峰值振幅 | 10、15、20 deg/s |
| 每組長度 | 7秒／700筆：靜置1秒、訊號4秒、靜置2秒 |
| 設計期望 | 7 Hz在4–6 Hz目標頻帶外，三組都應維持關閉 |

目前交付版PC reference結果：

| 振幅 | 是否曾開啟 | 訊號出現後首次開啟 | 4秒訊號段開啟筆數 | 解讀 |
|---:|---:|---:|---:|---|
| 10 deg/s | 否 | never | 0/400 | 符合設計 |
| 15 deg/s | 否 | never | 0/400 | 符合設計 |
| 20 deg/s | 是 | 390 ms | 361/400 | 已知邊界誤開，須上板確認 |

## 給瑋哲的檔案

- `gating_7hz_boundary_vectors.h`：三組raw輸入與逐筆reference enabled，可直接編進測試模式。
- `gating_7hz_10dps.csv`、`gating_7hz_15dps.csv`、`gating_7hz_20dps.csv`：人類可讀輸入。
- `expected_trace.csv`：2,100筆逐點中間值與enabled。
- `expected_results.csv`：三組摘要。
- `manifest.json`：版本、時間與測試範圍。

## STM32注入方式

先禁止H-bridge或斷開馬達，只驗證sensing與`enabled`。每換一組前呼叫
`TremorGate_Reset()`，並把sample index歸零：

```c
#include "gating_7hz_boundary_vectors.h"
#include "tremor_gate.h"

static uint32_t vector_index = 0U; /* 0=10, 1=15, 2=20 deg/s */
static uint32_t sample_index = 0U;

void Algorithm_7Hz_Boundary_Test_Tick(void)
{
    if (sample_index >= GATING_7HZ_SAMPLE_COUNT) {
        return; /* 已完成，停住等待人工換下一組 */
    }
    const double gyro_x_dps =
        (double)GATING_7HZ_GYRO_X_RAW_LSB[vector_index][sample_index] /
        GATING_7HZ_RAW_LSB_PER_DPS;
    const uint8_t enabled = TremorGate_Update(&tremor_gate, gyro_x_dps);

    /* 記錄vector_index、sample_index、gyro_x_dps與enabled。 */
    (void)enabled;
    ++sample_index;
}
```

板上至少回傳：

```text
test_case_id,amplitude_peak_dps,sample_index,sample_tick_ms,gyro_x_dps,enabled
```

建議再回傳`tremor_envelope`、`voluntary_envelope`與`tremor_ratio`。20 deg/s若
和reference一樣開啟，不代表STM32出錯，而是重現目前演算法已知的filter邊界；
後續才決定要調窄filter、提高比例門檻或接受較窄的有效頻帶。

## 重新產生與PC驗證

```powershell
python algorithms/validation/generate_gating_7hz_boundary_vectors.py
cd algorithms/handoff
test/build_and_run.bat
```

不要手動修改CSV或header內的數字；需要改條件時修改產生器再重新產生。
