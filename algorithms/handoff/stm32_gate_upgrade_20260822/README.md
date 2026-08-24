# STM32 Gate Upgrade 2026-08-22

這是給瑋哲（Ryan branch `70f97bb685e30885544e10e4dc2f677267802cbc`，2026-08-24）的 **motor-off gate shadow 驗證包**。

本包會把舊的 3–8 Hz `tremor_gate.c/.h` 成對換成目前已完成 host 驗證的 hardened V2 gate：

- sample rate：100 Hz
- tremor filter：4–6 Hz
- voluntary filter：1–3 Hz
- `amp_on/off`：6 / 3 deg/s
- `ratio_on/off`：0.55 / 0.45
- envelope decay：0.94
- `samples_on/off`：20 / 15
- 新增 config、NaN/Inf、超量程及 runtime-state fail-closed 檢查

這不是「可直接接上人體的馬達韌體」。目前 gate registry 的 motor authority 仍是 `none`；本輪目標只有：

1. 讓 STM32 執行最新版 gate。
2. 比對 STM32 與 PC golden trace 是否逐筆一致。
3. 確認任何 gate 結果都沒有取得馬達控制權。

本包**沒有直接修改 Ryan branch**。所有安裝與 patch 都必須由瑋哲在自己的 exact target worktree 明確執行。

## 先做這四件事

1. **實體拔除馬達電源或 H-bridge 電源，且不可配戴在人身上。** 軟體設 LOW 不能取代實體斷電。
2. 確認 Ryan repo HEAD 正好是 `70f97bb685e30885544e10e4dc2f677267802cbc`。
3. 先執行本包的 PC 測試：

   ```powershell
   .\run_host_tests.bat
   ```

4. 驗證 manifest 與全部檔案 SHA-256，再進行安裝：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\verify_package.ps1
   ```

## 安裝最新版 gate

在本資料夾下執行 dry-run；這一步不會修改 Ryan repo：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_gate_only.ps1 `
  -ProjectRoot "C:\path\to\Ryan-SteadyHope"
```

確認顯示 `CHECK PASSED` 後才執行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_gate_only.ps1 `
  -ProjectRoot "C:\path\to\Ryan-SteadyHope" -Apply
```

安裝程式只會成對替換：

- `firmware/algo/CM7/Core/Src/tremor_gate.c`
- `firmware/algo/CM7/Core/Inc/tremor_gate.h`

新版 `TremorGate` struct 比舊版大，binary ABI 不相容。因此兩個檔案一定要一起換，接著在 STM32CubeIDE 執行 **Project > Clean**，再做完整 CM7 rebuild；不可沿用舊 `.o`。

## 套用 motor-off shadow patch

`reference/main.c` 是從 exact Ryan commit `70f97bb685e30885544e10e4dc2f677267802cbc` 的完整 `main.c` 套用下列 patch 後得到的唯讀參考檔。它方便先審查完整結果，但不代表 Ryan branch 已被修改，也不取代 `tremor_gate.c/.h` 的成對安裝。

- 原始 `main.c` Git blob：`97085aea33569fbb2b989187ae2697e60a7565ce`
- shadow `main.c` Git blob：`468f28802b57b5bd9f1fa7d4d51def4007bc2b7d`
- `reference/main.c` SHA-256（LF byte snapshot）：`36e753b23820bea390598336c7fd7966ae80647b9974485b3a002e68d393802d`

Windows checkout 可能以 CRLF 儲存工作檔，所以跨平台核對時應使用 `git hash-object --path=firmware/algo/CM7/Core/Src/main.c` 的 clean Git blob；本包驗證另以 LF checkout 確認 reference 與 patch output 的 raw SHA-256 及 bytes 完全相同。

先確認 patch 可套用：

```powershell
git -C "C:\path\to\Ryan-SteadyHope" apply --check "C:\path\to\this-package\ryan_70f97bb_shadow_only.patch"
```

通過後才套用：

```powershell
git -C "C:\path\to\Ryan-SteadyHope" apply "C:\path\to\this-package\ryan_70f97bb_shadow_only.patch"
```

這個 patch 會：

- 將 `suppression_start_allowed` 固定為 0。
- 只讓 fresh、valid 的真實 IMU sample 推進 estimator 與 gate；內建 5 Hz 僅保留供 debugger 觀察。
- 任一無效 sample 立刻 reset 舊 detector 與 V2 gate，不再用上一筆資料推進狀態。
- 每個 control tick 都呼叫 `Actuator_StateMachine_Reset()`。
- 將 TB6612 的 PWMA startup level 設為 LOW，且本 patch 沒有任何路徑再把它設回 HIGH。

它不會讓 `freqEstimate`、舊的全速 5 秒 pull/return 或 App 長度調整取得控制權。`freqEstimate` 在這一階段只可留在 debugger 中，不可寫入 App 的 tremor frequency。

## STM32 21 組邊界測試

測試資料為 5.5、6、6.25、6.5、6.75、7、7.25 Hz，各搭配 10、15、20 deg/s，共 21 組。每組為 700 samples：1 秒 rest、4 秒 tone、2 秒 rest。

在獨立的 CubeIDE test build 中加入：

- `src/gating/tremor_gate.c/.h`
- `src/shadow/gate_shadow_adapter.c/.h`
- `target_test/gate_boundary_runner.c/.h`
- `target_test/gating_6to7_boundary_vectors.h`

`gating_6to7_boundary_vectors.h` 只能被 `gate_boundary_runner.c` 這一個 translation unit include，且這些測資不得編入正式 firmware image。

初始化：

```c
static GateBoundaryRunner runner;
GateBoundaryRunner_Init(&runner);
```

100 Hz timer 每一 tick 只呼叫一次：

```c
GateBoundaryRow row;
if (GateBoundaryRunner_Step(&runner, &row) != 0U) {
    /* Push row into a RAM ring buffer here. */
}
```

不要在 ISR 逐筆呼叫 blocking `printf` 或 UART transmit。先放 RAM buffer，再由低優先序 task 分批輸出。

CSV 欄位必須使用以下名稱；`gate_enabled` 不能寫成 `motor_enabled`：

```text
test_case_id,sample_index,sample_tick_ms,gyro_x_raw_lsb,tremor_envelope,voluntary_envelope,tremor_ratio,on_count,off_count,gate_enabled,gate_config_valid,gate_last_fault,actuation_authority
```

將 STM32 輸出的 14,700 筆 CSV 送回 PC 後執行：

```powershell
python .\tools\compare_stm32_gate_log.py `
  --input .\stm32_6to7_trace.csv `
  --output-json .\stm32_6to7_comparison.json
```

通過條件：

- `pass=true`
- `expected_rows=14700`、`actual_rows=14700`
- missing、unexpected、duplicate、tick mismatch 全為 0
- raw、envelope、ratio、on/off count、`gate_enabled` mismatch 全為 0
- `gate_config_valid` 每筆為 1
- `gate_last_fault` 每筆為 0
- `actuation_authority` 每筆為 0

`sample_tick_ms` 是測資的邏輯時間，不能單獨證明 STM32 真正維持 100 Hz。板上還要另外紀錄硬體 timer 或 cycle counter，確認相鄰 update 約為 10 ms，而且沒有漏 tick 或重複 update。

## 預期邊界行為

這個 4–6 Hz Butterworth gate 不是磚牆式頻率分類器。正確重現時會看到：

| 頻率 | 10 deg/s | 15 deg/s | 20 deg/s |
|---|---:|---:|---:|
| 5.5 Hz | 開 | 開 | 開 |
| 6.0 Hz | 關 | 開 | 開 |
| 6.25 Hz | 關 | 開 | 開 |
| 6.5 Hz | 關 | 開 | 開 |
| 6.75 Hz | 關 | 關 | 開 |
| 7.0 Hz | 關 | 關 | 開 |
| 7.25 Hz | 關 | 關 | 關 |

因此 7 Hz / 20 deg/s 開啟是目前 reference 的已知邊界行為。板上重現它代表「移植一致」，不代表臨床頻帶或馬達策略已通過。

## 回傳給演算法組的檔案

瑋哲完成後請回傳：

- `stm32_6to7_trace.csv`
- `stm32_6to7_comparison.json`
- CM7 Release build ID、編譯器版本、ELF/MAP hash
- 安裝後 `tremor_gate.c/.h` 的 SHA-256
- 實際 100 Hz timing log
- 示波器或 logic analyzer 證明 AIN1、AIN2、PWMA 全程 LOW 的紀錄

## 欄位語意不可再混用

- `gate_enabled`：演算法偵測成立，只供本輪記錄。
- `actuation_authority`：本包永遠為 0。
- `motor_output_active`：H-bridge/PWM 實際非零才是 1；本輪必須永遠為 0。
- Ryan 舊 16-byte packet 的 `motor_enabled` 是 drive command，不是 gate。shadow patch 後它應維持 0，不能拿它驗 gate。

通過本包只代表「最新版 gate 已在 STM32 上逐筆重現」。它不代表已證明抑震效果、人體安全、臨床準確率或商品可販售。
