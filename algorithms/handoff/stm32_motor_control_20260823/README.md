# STM32 馬達控制台架交付包（2026-08-23）

## 定位

這是給瑋哲使用的 **STM32 motor-control canonical integration reference**。目前預設已切成 powered-bench profile：上電 armed、100% intensity、full-scale PWM，且 encoder/SetZero/position guard 不再阻擋離架馬達測試。Repo 的 `firmware/algo` 是 STM32H745I-DISCO 雙核心 CubeIDE target，CM7 實際編譯的 `main.c` 由 validator 強制與本包 canonical byte-identical。這代表軟體路徑已解除，但目前仍沒有本機 ST-LINK dual-core flash、GPIO/PWM 波形或負載台架證據；build 通過不能寫成馬達已實測，更不是配戴、醫療使用或販售版本。

目前同一個 Git branch 也包含 authoritative 的 **4–6 Hz hardened gate**：

- `algorithms/handoff/src/gating/tremor_gate.c`
- `algorithms/handoff/src/gating/tremor_gate.h`
- `algorithms/handoff/src/control/suppression_control.c/.h`

目前這個 branch 已整合成對的 gate 檔，且 validator 會檢查 target mirror；瑋哲不需要再手動覆蓋。只有移植到其他舊 target 時，才需要同時替換 `.c/.h` 並執行 CubeIDE Clean Build。切換 branch 也不代表板上已更新，仍須完成 build、flash 與測資逐筆比對。正式 motor permission 只可由 `SuppressionControl` 的 fail-safe 輸出往下傳，舊版 `freqEstimate`、雙 gate AND 與固定全速 2 秒狀態機不可保留在馬達權限路徑。

最先要改的是：**TB6612FNG `STBY` 不得再硬接 3V3**。拆掉舊線後改接 `D4 / PK1` GPIO。TB6612FNG 的 STBY input 本身有 internal pulldown；若自製板需要更強的 fail-low，可另加約 `10 kΩ` external pulldown，但它不是 breakout 臨時接線的必要條件。

- [QUICK_START_給瑋哲.md](QUICK_START_%E7%B5%A6%E7%91%8B%E5%93%B2.md)：目前 branch 的接線、build、gate 測試、telemetry 與調參步驟。
- [`reference/main.c`](reference/main.c)：0823 唯一 canonical `main.c`，整合最新版 gate、`SuppressionControl`、mapper、encoder、position guard、TB6612 driver 與 HAL adapter；CubeIDE 編譯的是 `firmware/algo/CM7/Core/Src/main.c` mirror，兩者差異會令 integration validator 失敗。
- [`example/stm32_motor_integration_example.c`](example/stm32_motor_integration_example.c)：依目前 actuator API 寫的說明性 glue code；不是可直接上電的完整 `main.c`。

portable 實作位於 `../src/actuator/`：`quadrature_encoder`、`motor_position_guard`、`tb6612_driver`；最新版 gate 與控制 wrapper 位於 `../src/gating/`、`../src/control/`；STM32 專用 adapter 位於本包的 `src/actuator/stm32_tb6612_hal.c/.h`。

## Canonical `main.c` 的使用方式

不要再把 0822 shadow reference、Ryan branch 的舊 `main.c` 或 example 當成最新版。0822 包是 sealed historical evidence；0823 的 canonical source 只有：

```text
algorithms/handoff/stm32_motor_control_20260823/reference/main.c
```

目前 branch 已由 validator 保證它與實際 target 編譯的下列檔案 byte-identical：

```text
firmware/algo/CM7/Core/Src/main.c
```

不要再手動複製或覆蓋目前 branch。只有移植到另一個 target，且 `.ioc`、peripheral handle、timer、UART、I2C 或 pin mapping 已不同時，才保留該 target 的 CubeMX 產生區並逐段移植 canonical 的 USER CODE、100 Hz fresh-sample pipeline、encoder callbacks、ForceSafe 與 telemetry 語意；完成後仍須用 validator 對實際 target `main.c` 驗證。

Canonical 使用 header basename，不含任何電腦專屬絕對路徑。目前 repo target 已完成以下
source ownership，不要再手動加入第二份：

```text
firmware/algo/CM7/Core/Src + Core/Inc       tremor_gate mirror
firmware/algo/CM7/Core/Algo/bmflc          BMFLC target copy
firmware/algo/CM7/Core/Algo/ehwflc         eHWFLC-KF target copy
Eclipse linked resource Handoff_Control     handoff/src/control
Eclipse linked resource Handoff_Actuator    handoff/src/actuator
Eclipse linked resource Handoff_STM32_Actuator  STM32 HAL adapter
```

`.cproject` 已為 Debug/Release 設好相符的 include path 與 source entry，validator 會檢查
target-local gate mirror 與 canonical gate byte-identical。若移植到另一個 CubeIDE target，
每個 module 必須只選一個 owner：使用 target-local copy，或改用 handoff source，不能兩者
同時編譯。Include path 只解決 header，不會自動加入 `.c`；也禁止在 `main.c` 補回
`C:/Users/...` 類絕對 include。`BNO055_STM32.h` 則使用該 target 實際 driver 的目錄。

Canonical 現在由單一檔案 `firmware/algo/CM7/Core/Inc/motor_bench_config.h` 提供 powered-bench 設定：

```c
#define MOTOR_POWERED_BENCH_MODE        1U
#define MOTOR_BENCH_CONFIG_APPROVED     1U
#define MOTOR_DEFAULT_RUNTIME_ARMED     1U
#define MOTOR_DEFAULT_INTENSITY_PERCENT 100U
#define MOTOR_MAX_ACTIVE_CCR            3200U
```

Mapper/driver 也是有效非零 config；gate 開啟後可直接到 TB6612。Powered bench 刻意 bypass encoder homing、position travel、wrong/no-motion 與 active-timeout authority，讓目前沒有 counts/mm 的機構也能先做離架旋轉、PWM、方向與 gate 測試。Gate off、stale IMU、scheduler overrun、numeric/driver/HAL fault 仍會 ForceSafe。所有調整與現場排查請直接讀 `firmware/algo/README.md`，不要再靠 debugger 臨時翻旗標。

## 驗證順序

先從 repo root 執行 canonical validator：

```powershell
python .\algorithms\validation\validate_stm32_motor_main.py
```

整合到 target 後，再對實際編譯檔執行：

```powershell
python .\algorithms\validation\validate_stm32_motor_main.py `
  --main .\firmware\algo\CM7\Core\Src\main.c
```

兩次 validator 都通過後，才執行 host tests：

```powershell
.\algorithms\handoff\test\run_actuator_tests.bat
```

目前 repo target 再執行：

```powershell
python .\algorithms\validation\validate_cubeide_motor_integration.py
powershell -ExecutionPolicy Bypass -File .\firmware\algo\build_headless.ps1
```

Validator 會檢查 canonical module manifest、禁止的 legacy／`freqEstimate` authority、fresh-sample ownership、ForceSafe 與 telemetry contract；host tests 會嚴格編譯並執行 suppression wrapper、motor mapper、encoder、position guard、TB6612 driver、假的 HAL 呼叫順序及整合鏈測試，也會對範例做 syntax compile。全部通過只代表 static/host implementation check；不代表 CubeIDE target build、實際 GPIO/PWM 波形、馬達台架或人體測試已通過。

## 接線契約

| 功能 | STM32H745I-DISCO | 外部端 | 要求 |
|---|---|---|---|
| AIN1 | `D2 / PG3` | TB6612 `AIN1` | GPIO，boot LOW |
| AIN2 | `D3 / PA6` | TB6612 `AIN2` | GPIO，boot LOW |
| PWMA | `D5 / PA8 / TIM1_CH1` | TB6612 `PWMA` | hardware PWM，boot CCR=0 |
| STBY | **`D4 / PK1`** | TB6612 `STBY` | GPIO，boot LOW；拆掉舊 STBY→3V3；external 10 kΩ pulldown 僅為選配 fail-low |
| Logic | `3V3` | TB6612 `VCC` | 3.3 V logic |
| Motor supply + | — | TB6612 `VM` | 外部限流台架電源正端；電壓依手上馬達銘牌／datasheet |
| Common ground | STM32 `GND` | TB6612 `GND/PGND`、台架電源負端 | STM32、driver、encoder（若接）與電源必須共地 |
| Encoder A | `D6 / PE6` | encoder `A / C1` | rising + falling EXTI；線色須依手上 encoder 確認 |
| Encoder B | `D7 / PI8` | encoder `B / C2` | rising + falling EXTI；線色須依手上 encoder 確認 |
| Encoder power | 依 encoder datasheet | encoder `V+ / GND` | 本 profile 可不接；不可只靠線色猜電壓 |
| Motor | — | TB6612 `AO1/AO2` → 馬達兩線 | 不要接 `BO1/BO2`；實際方向在離架夾具確認 |

PE6/PI8 不能直接配成同一個 STM32 hardware timer encoder mode。保留現有接線時，A/B 都要設雙邊緣 EXTI，每次中斷立刻重讀兩腳並呼叫 x4 decoder。**不能只在 100 Hz 主迴圈輪詢 A/B**。
目前 `.ioc` 與 compiled `main.c` 都使用內部 `GPIO_PULLUP`，避免 encoder 斷線時輸入浮動；
若這輪要接 encoder，仍須依手上 encoder datasheet 確認輸出是 3.3 V 相容的 push-pull 或
open-collector；不接 D6/D7 不會阻擋 powered-bench PWM。

## PWM 與排程

- Control tick 固定 `100 Hz`（10 ms/tick）。
- PWM carrier 目標 `20 kHz`；timer 啟動一次，運行中只更新 CCR。
- **只有量到 TIM1 kernel clock = 64 MHz、edge-aligned up-counting 時**，才使用 `PSC=0`, `ARR=3199`：

  ```text
  64,000,000 / ((0 + 1) * (3199 + 1)) = 20,000 Hz
  ```

- 時鐘或 mode 改變就重算，並用 scope/logic analyzer 實測 PA8。
- Driver/HAL 的 `pwm_full_scale_ccr` 是 PWM denominator，等於 `ARR+1=3200`。目前 powered-bench profile 的 `max_active_ccr` 也明確設成 `3200`，所以允許完整 duty。要改成 50% 時，mapper/driver 的 `max_duty_fraction` 改 `0.5`，HAL cap 同步改 `1600U`；只改其中一處會被 HAL 拒絕。
- Max duty、gain、deadband 與 slew 的目前值是刻意用於解除台架測試阻擋，不是量測完成的商品參數；調整入口只有 `firmware/algo/CM7/Core/Inc/motor_bench_config.h`。

## 方向、零點與 encoder 校正

目前可確認的只有 bridge 電氣語意：

```text
direction +1 → AIN1=1, AIN2=0
direction -1 → AIN1=0, AIN2=1
```

哪一組是實體收線／放線目前沒有可信證據。第一次只能在離架夾具上短測；若演算法補償方向相反，只改 `MOTOR_COMMAND_DIRECTION_POLARITY` 的 `1/-1`，不要交換 D2/D3。Encoder 正負若要用於日後 guarded profile，再獨立確認 `MOTOR_ENCODER_COUNT_POLARITY`，不要同時換線與改兩個 polarity。

目前 powered-bench profile 的 encoder 是 telemetry-only：

1. Boot GPIO 仍先為 `STBY=LOW`, `CCR=0`, `AIN1=AIN2=LOW`。
2. 不要求 `SetZero` 即可由 gate 啟動 PWM。
3. D6/D7 可接 encoder 觀察 count，也可在第一輪 free-shaft test 不接。
4. 日後切回 wearable/guarded profile 時，才重新啟用本節原設計的 neutral SetZero、行程與 motion fault authority。

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
    ↓ + mapper / driver / HAL（powered bench；encoder telemetry-only）
motor_output_active
```

- `gate_enabled`：gate 判斷成立，不代表馬達開啟。
- `actuation_permitted`：上游允許進入馬達層評估，仍不是物理輸出。
- `motor_output_active`：最終有效 command 的 `STBY=1`、`CCR>0` 且方向有效；仍只證明送出命令，不證明馬達真的移動或抑制成功。

UART/App/log 要保留三欄，不能再合併成一個 `motor_enabled`。另記 `calibration_required`、`encoder_count`、position/driver fault、direction、CCR 與 tick time。

`eHWFLC-KF freqEstimate` 只能做 diagnostics；不得用於 motor gating、不得當 App tremor-frequency biomarker，也不得改變輸出授權。見 [`../GATING_DESIGN.md`](../GATING_DESIGN.md)。

## 台架安全邊界

- 移除舊程式的「full-duty 正/反轉 2 秒」狀態機。
- 第一階段使用符合手上馬達額定電壓的限流 bench supply、無負載或受控夾具、無手套、無人體測試；先設低 current limit，並保留可立即斷電的實體方式。未確認完整馬達料號前，不在文件硬寫 6 V。
- TB6612FNG 沒有可供此軟體讀取的 motor-current sense 或 fault pin；軟體沒有 driver fault 不等於沒有堵轉、過流或過熱。使用外部限流/保險絲，要記錄電流則另加感測器。
- 任一供電電壓的結果都不能直接套到另一電壓；變更後須重測電流、溫度、轉速、行程、負載、制動、過衝、watchdog 與 brownout。
- 目前 powered-bench profile 保留 gate off、stale IMU、scheduler、numeric、driver 與 HAL fault 的即時 ForceSafe；encoder/position 是 telemetry-only。Encoder invalid/overflow、wrong/no motion、行程與 timeout 的 veto/latch 是未來 wearable/guarded profile 恢復前必須驗收的要求，不是目前台架輸出的隱藏限制。

## 升級前仍缺的證據

1. 已有可重現 target build；仍缺已上板驗證的 dual-core flash/debug 流程、ST-LINK/board revision 與兩個 ELF hash 紀錄。
2. 綁定 release、HAL integer `max_active_ccr`，且每個數值皆有台架依據的 motor/position config registry。
3. Boot、fault、換向、reset 時的 PWM/AIN1/AIN2/STBY 波形。
4. Encoder 丟邊緣、方向、行程與 no/wrong-motion fault injection。
5. 硬體 home/limit、外部電流保護、溫度/拉力、快速釋放、風險分析及人體測試核准。

## 官方資料

- [Toshiba TB6612FNG datasheet](https://toshiba.semicon-storage.com/info/TB6612FNG_datasheet_en_20141001.pdf?did=10660&prodName=TB6612FNG)
- [ST UM2488 — STM32H745I-DISCO user manual](https://www.st.com/resource/en/user_manual/um2488-discovery-kits-with-stm32h745xi-and-stm32h750xb-mcus-stmicroelectronics.pdf)
- [ST STM32H745xI/G datasheet](https://www.st.com/resource/en/datasheet/stm32h745ig.pdf)
- [JGA25-370B 供應商型錄頁](https://www.aslongdcmotor.com/sale-53110369-6v-12v-25mm-brushed-dc-gear-motor-encoder-jga25-370b-high-torque-25mm-brushed-dc-gear-motor.html)（只作型號系列參考，不能取代手上馬達料號與實測）
