# STM32 馬達控制台架交付包（2026-08-23）

## 定位

這是給瑋哲做 **6 V、離架、限流台架整合** 的手動交付說明，不是已上板驗證、可配戴、可醫療使用或可販售的版本。目前 repo 沒有瑋哲最新的 STM32CubeIDE 專案，所以無法聲稱 target build 或燒錄通過；必須在他的 branch 手動整合並補齊量測紀錄。

目前同一個 Git branch 也包含 authoritative 的 **4–6 Hz hardened gate**：

- `algorithms/handoff/src/gating/tremor_gate.c`
- `algorithms/handoff/src/gating/tremor_gate.h`
- `algorithms/handoff/src/control/suppression_control.c/.h`

兩個 gate 檔必須成對替換瑋哲 8/18 branch 的 3–8 Hz 舊版並執行 CubeIDE Clean Build；只換 `.c`、只換係數或保留舊 object 都不算更新。切換 branch 也不代表板上已更新，必須完成 build、flash 與測資逐筆比對。正式 motor permission 只可由 `SuppressionControl` 的 fail-safe 輸出往下傳，舊版 `freqEstimate`、雙 gate AND 與固定全速 2 秒狀態機不可保留在馬達權限路徑。

最先要改的是：**TB6612FNG `STBY` 不得再硬接 3V3**。改接 `D4 / PK1` GPIO，並在 `STBY` 對 GND 加約 `10 kΩ` pulldown。未改完前不得連接馬達電源進行本設計測試。

- [QUICK_START_給瑋哲.md](QUICK_START_%E7%B5%A6%E7%91%8B%E5%93%B2.md)：接線、CubeMX、校正與台架驗收步驟。
- [`example/stm32_motor_integration_example.c`](example/stm32_motor_integration_example.c)：依目前 actuator API 寫的說明性 glue code；不是可直接上電的完整 `main.c`。

portable 實作位於 `../src/actuator/`：`quadrature_encoder`、`motor_position_guard`、`tb6612_driver`；最新版 gate 與控制 wrapper 位於 `../src/gating/`、`../src/control/`；STM32 專用 adapter 位於本包的 `src/actuator/stm32_tb6612_hal.c/.h`。

先在 Windows 從 `algorithms/handoff/` 執行：

```powershell
.\test\run_actuator_tests.bat
```

這會嚴格編譯並執行 suppression wrapper、motor mapper、encoder、position guard、TB6612 driver、假的 HAL 呼叫順序及整合鏈測試，也會對範例做 syntax compile。全部通過只代表 host implementation check；不代表 CubeIDE target build、實際 GPIO/PWM 波形或馬達台架已通過。

## 接線契約

| 功能 | STM32H745I-DISCO | 外部端 | 要求 |
|---|---|---|---|
| AIN1 | `D2 / PG3` | TB6612 `AIN1` | GPIO，boot LOW |
| AIN2 | `D3 / PA6` | TB6612 `AIN2` | GPIO，boot LOW |
| PWMA | `D5 / PA8 / TIM1_CH1` | TB6612 `PWMA` | hardware PWM，boot CCR=0 |
| STBY | **`D4 / PK1`** | TB6612 `STBY` | GPIO，boot LOW，約 10 kΩ pulldown；禁止硬接 3V3 |
| Logic | `3V3` | TB6612 `VCC` | 3.3 V logic |
| Motor supply | 共地 | TB6612 `VM` | 第一階段只用 6 V 限流台架電源 |
| Encoder A | `D6 / PE6` | 黃線/C1 | rising + falling EXTI |
| Encoder B | `D7 / PI8` | 綠線/C2 | rising + falling EXTI |
| Encoder power | `3V3`, GND | 藍線、黑線 | 先核對手上 encoder 的額定電壓 |
| Motor | `AO1`, `AO2` | 紅線、白線 | 實際方向必須在夾具上短脈衝確認 |

PE6/PI8 不能直接配成同一個 STM32 hardware timer encoder mode。保留現有接線時，A/B 都要設雙邊緣 EXTI，每次中斷立刻重讀兩腳並呼叫 x4 decoder。**不能只在 100 Hz 主迴圈輪詢 A/B**。

## PWM 與排程

- Control tick 固定 `100 Hz`（10 ms/tick）。
- PWM carrier 目標 `20 kHz`；timer 啟動一次，運行中只更新 CCR。
- **只有量到 TIM1 kernel clock = 64 MHz、edge-aligned up-counting 時**，才使用 `PSC=0`, `ARR=3199`：

  ```text
  64,000,000 / ((0 + 1) * (3199 + 1)) = 20,000 Hz
  ```

- 時鐘或 mode 改變就重算，並用 scope/logic analyzer 實測 PA8。
- Driver/HAL 的 `pwm_full_scale_ccr` 是 PWM denominator，必須等於實際 `ARR+1`；若上述 `ARR=3199` 經量測成立，兩處便一致填 3200。這不等於允許 100% duty，實際 max duty 仍是獨立的台架限制。
- Max duty、gain、deadband、slew、行程和 fault timeout 都沒有商品預設；unit test 數值不可複製到實機。

## 方向、零點與 encoder 校正

軟體唯一語意為：

```text
direction +1 = FORWARD = RELEASE = 正轉放線 = encoder count 增加
direction -1 = REVERSE = TAKE_UP = 反轉收線 = encoder count 減少
```

這不是對紅白線或黃綠線相位的猜測。第一次只能在離架夾具上，用經台架決定的低能量短脈衝核對。若相反，分別調整 driver 的 `release_ain1_level` 或 decoder 的 `count_polarity`，不要同時亂換線與改軟體。

開機必須停在 `CALIBRATION_REQUIRED`：

1. `STBY=LOW`, `CCR=0`, `AIN1=AIN2=LOW`。
2. 人員手動把機構放到確認過的中立位置。
3. 只在 bridge off 且 encoder snapshot 有效時，接受一次明確的 `SetZero`。
4. reset、brownout、watchdog 或 position fault 後都要重新確認及 `SetZero`；不可自動沿用或把開機位置直接當零點。

「開機當下位置」只是相對座標，不是 homing。可配戴設計仍需要獨立 home/limit/absolute reference、硬體行程限制與快速釋放機構。

Encoder 規格目前是 11/12 PPR/CPR 未定，必須實測：輸出軸每方向各轉 10 圈、各至少 3 次，保留 x4 count 原始值與 invalid count。計算：

```text
counts_per_output_rev = abs(delta_count) / 10
mm_per_count = (pi * effective_spool_diameter_mm) / counts_per_output_rev
```

10 mm 線軸公式只適用理想單層且無滑動；繩徑、繞線層、齒隙、打滑及負載都會改變有效行程，正式 limit 必須用最終機構重測。

## 三個輸出不得混用

```text
gate_enabled
    ↓ + sensor fresh / estimator / inhibit checks
actuation_permitted
    ↓ + mapper / SetZero / position guard / driver / HAL
motor_output_active
```

- `gate_enabled`：gate 判斷成立，不代表馬達開啟。
- `actuation_permitted`：上游允許進入馬達層評估，仍不是物理輸出。
- `motor_output_active`：最終有效 command 的 `STBY=1`、`CCR>0` 且方向有效；仍只證明送出命令，不證明馬達真的移動或抑制成功。

UART/App/log 要保留三欄，不能再合併成一個 `motor_enabled`。另記 `calibration_required`、`encoder_count`、position/driver fault、direction、CCR 與 tick time。

`eHWFLC-KF freqEstimate` 只能做 diagnostics；不得用於 motor gating、不得當 App tremor-frequency biomarker，也不得改變輸出授權。見 [`../GATING_DESIGN.md`](../GATING_DESIGN.md)。

## 台架安全邊界

- 移除舊程式的「full-duty 正/反轉 2 秒」狀態機。
- 第一階段只做 6 V、限流 bench supply、無負載或受控夾具、無手套、無人體測試；要有可立即斷電的實體方式及外部電流保護。
- TB6612FNG 沒有可供此軟體讀取的 motor-current sense 或 fault pin；軟體沒有 driver fault 不等於沒有堵轉、過流或過熱。使用外部限流/保險絲，要記錄電流則另加感測器。
- 6 V 結果不能直接套到 12 V。12 V 是新的驗證階段，須重測電流、溫度、轉速、行程、負載、制動、過衝、watchdog 與 brownout。
- Encoder invalid/overflow、wrong/no motion、超行程、超時、掉壓或異常電流/溫度都要在當 tick ForceSafe 並 latch fault，等待人工重新確認。

## 升級前仍缺的證據

1. 最新 CubeIDE 專案的可重現 build/flash 指令與 target compile evidence。
2. 綁定 release、每個數值皆有台架依據的 motor/position config registry。
3. Boot、fault、換向、reset 時的 PWM/AIN1/AIN2/STBY 波形。
4. Encoder 丟邊緣、方向、行程與 no/wrong-motion fault injection。
5. 硬體 home/limit、外部電流保護、溫度/拉力、快速釋放、風險分析及人體測試核准。

## 官方資料

- [Toshiba TB6612FNG datasheet](https://toshiba.semicon-storage.com/info/TB6612FNG_datasheet_en_20141001.pdf?did=10660&prodName=TB6612FNG)
- [ST UM2488 — STM32H745I-DISCO user manual](https://www.st.com/resource/en/user_manual/um2488-discovery-kits-with-stm32h745xi-and-stm32h750xb-microcontrollers-stmicroelectronics.pdf)
- [ST STM32H745xI/G datasheet](https://www.st.com/resource/en/datasheet/stm32h745ig.pdf)
- [JGA25-370B 供應商型錄頁](https://www.aslongdcmotor.com/sale-53110369-6v-12v-25mm-brushed-dc-gear-motor-encoder-jga25-370b-high-torque-25mm-brushed-dc-gear-motor.html)（只作型號系列參考，不能取代手上馬達料號與實測）
