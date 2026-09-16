# STM32 1–8 Hz × 七種振幅完整測試包

這個測試包將V2 gating的完整離線振幅掃描轉成STM32可直接編譯的逐筆測資。
它用來回答「各頻率要多強才會讓`enabled`變成1」，不是真人震顫、馬達負載或
真實抑震率。

## 測試條件

| 項目 | 規格 |
|---|---|
| 頻率 | 1、2、3、4、5、6、7、8 Hz |
| peak振幅 | 2、4、6、8、10、15、20 deg/s |
| 總case數 | 56組 |
| 每組長度 | 700筆：靜置1秒、tone 4秒、靜置2秒 |
| 輸入格式 | BNO055 GyroX raw `int16_t`，`raw / 16.0 = deg/s` |
| 更新率 | 100 Hz，每10 ms一筆 |
| gating參數 | `TremorGate_DefaultConfig()` |

case順序是「頻率先、振幅後」，例如vector 0是1 Hz/2 deg/s，vector 6是
1 Hz/20 deg/s，vector 7是2 Hz/2 deg/s。可以用：

```text
vector_index = (frequency_hz - 1) * 7 + amplitude_index
amplitude_index: 0,1,2,3,4,5,6 = 2,4,6,8,10,15,20 deg/s
```

## 給瑋哲的檔案

- `gating_amplitude_sweep_vectors.h`：56組raw輸入與逐筆reference `enabled`。
- `test_vectors.csv`：39,200筆long-form測資，可人工查閱或由工具轉換。
- `expected_results.csv`：56組的啟動時間、開啟筆數與釋放延遲摘要。
- `manifest.json`：版本、取樣率、單位與case定義。

`gating_amplitude_sweep_vectors.h`約使用118 KB Flash存放raw與expected陣列。只能在
一個測試`.c`檔include，不要放到多個translation unit，也不要複製到stack或RAM。

## STM32測試方式

沿用上週15 deg/s測試模式，只替換輸入陣列。第一階段禁止H-bridge，
不在100 Hz callback裡逐筆`printf`：

```c
#include "gating_amplitude_sweep_vectors.h"
#include "tremor_gate.h"

static uint32_t vector_index;
static uint32_t sample_index;
static uint32_t mismatch_count;

void Gating_Sweep_Test_Start(uint32_t selected_vector)
{
    TremorGateConfig config = TremorGate_DefaultConfig();
    vector_index = selected_vector;
    sample_index = 0U;
    mismatch_count = 0U;
    TremorGate_Init(&tremor_gate, &config);
}

void Gating_Sweep_Test_100Hz_Tick(void)
{
    if (sample_index >= GATING_SWEEP_SAMPLE_COUNT) {
        return;
    }

    const double gyro_x_dps =
        (double)GATING_SWEEP_GYRO_X_RAW_LSB[vector_index][sample_index] /
        GATING_SWEEP_RAW_LSB_PER_DPS;
    const uint8_t actual = TremorGate_Update(&tremor_gate, gyro_x_dps);
    const uint8_t expected =
        GATING_SWEEP_EXPECTED_ENABLED[vector_index][sample_index];

    if (actual != expected) {
        ++mismatch_count;
    }
    ++sample_index;
}
```

每組至少回傳：

```text
vector_index,frequency_hz,amplitude_peak_dps,mismatch_count,
first_enabled_sample,enabled_samples_during_tone,final_enabled
```

`mismatch_count`要用`uint32_t`。一組結束後再印摘要，避免UART影響每10 ms的時序。

## 目前PC/C reference邊界

| 頻率 | 開啟的peak振幅 | 解讀 |
|---:|---|---|
| 1 Hz | 無 | 頻帶外，全部關閉 |
| 2 Hz | 無 | 自主動作帶，全部關閉 |
| 3 Hz | 無 | 全部關閉 |
| 4 Hz | 15、20 deg/s | 低振幅不足以開啟 |
| 5 Hz | 10、15、20 deg/s | 頻帶中心最容易開啟 |
| 6 Hz | 15、20 deg/s | 低振幅不足以開啟 |
| 7 Hz | 20 deg/s | **已知頻帶邊緣誤開** |
| 8 Hz | 無 | 頻帶外，全部關閉 |

STM32逐點與reference一致，代表移植正確；7 Hz/20 deg/s即使逐點一致，
在設計驗收上仍是需要處理的誤開，不能寫成功能通過。

## 重新產生與PC驗證

```powershell
python algorithms/validation/generate_gating_amplitude_sweep_vectors.py
python -m unittest discover -s algorithms/validation -p "test_gating_amplitude_sweep_vectors.py"
algorithms\handoff\test\build_and_run.bat
```

需要修改測試條件時，修改Python產生器後重新產生；不要手動改header或CSV數字。
