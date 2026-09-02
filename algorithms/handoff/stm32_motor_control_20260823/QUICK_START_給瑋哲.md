# 給瑋哲：powered-bench 快速測試

## 這版的狀態

這版已解除先前阻擋馬達的預設設定。燒入相同 profile 的 CM7＋CM4 後：

- 上電 armed
- intensity = 100%
- TIM1 max CCR = 3200（完整 duty）
- mapper／TB6612 config 有效
- 不用 debugger 改變數
- 不用 encoder SetZero；D6/D7 目前只作 telemetry
- Gate 開時，`-tremorEstimate` 會送到方向＋PWM

Gate off、IMU stale、scheduler overrun、driver/HAL error 仍會停機，這些是控制正確性，不是
舊的手動解鎖。

## 1. 接線

| 板上 pin | MCU | 接 TB6612／encoder |
|---|---|---|
| D2 | PG3 | `AIN1` |
| D3 | PA6 | `AIN2` |
| D4 | PK1 | `STBY` |
| D5 | PA8 / TIM1_CH1 | `PWMA` |
| D6 | PE6 | encoder A／C1（本輪可不接） |
| D7 | PI8 | encoder B／C2（本輪可不接） |
| 3V3 | — | TB6612 `VCC` |
| GND | — | TB6612 GND/PGND、encoder GND、外部電源負極共地 |
| 外部馬達電源正極 | — | TB6612 `VM` |
| TB6612 AO1/AO2 | — | 馬達兩條線 |

務必處理 `STBY`：如果舊線還是 `STBY -> 3V3`，先拆掉，再接 `D4 -> STBY`。`D5` 只接
`PWMA`，不能接 STBY。這份程式用 channel A，所以馬達接 `AO1/AO2`，不是 `BO1/BO2`。
本輪可完全不接 encoder；若要接，V+／GND、A/B 與線色都必須依手上 encoder 的
datasheet／標示確認，不能只靠黃、綠、藍、黑等線色猜。

## 2. Build 與 flash

Repo root 執行：

```powershell
python .\algorithms\validation\validate_cubeide_motor_integration.py
python .\algorithms\validation\validate_stm32_motor_main.py `
  --main .\firmware\algo\CM7\Core\Src\main.c --skip-shadow
.\algorithms\handoff\test\run_actuator_tests.bat
powershell -ExecutionPolicy Bypass -File .\firmware\algo\build_headless.ps1
```

要燒同一種 profile 的兩個檔：

```text
firmware/algo/CM7/Debug/algo_CM7.elf
firmware/algo/CM4/Debug/algo_CM4.elf
```

或兩個都用 Release。只更新其中一顆 core 不算更新完成。

## 3. 第一輪測試方法

1. 馬達先離架固定，不接手、不裝進手套。
2. 先上 STM32／logic power，確認 boot 時 D4 LOW、D5 LOW。
3. 接外部馬達電源並共地。
4. 不要下 breakpoint；用 Live Expressions＋scope。
5. 預設讀 BNO055 X 軸。以 X 軸約 5 Hz、12–15 dps 搖動。
6. Gate 預設需連續 20 個 100 Hz samples 達到 `amp>=6 dps`、ratio `>=0.55`。
7. Gate 開後應看到 D4 HIGH、D5 20 kHz PWM，D2/D3 隨補償正負換向。

換向時有 10–20 ms 的 CCR=0 safe tick 是正常現象，不是掉輸出。

## 4. Live Expressions 判讀

依序看：

```text
bno_detected_address              // 0x28 或 0x29
imu_ready                         // 1
selectedGyroInputDps              // X 軸輸入
gate_enabled_debug                // Gate 開後 1
actuation_permitted_debug         // 1
suppression_start_allowed         // 1
motorIntensityPercent             // boot 100；確認 App 沒有改成 0
compensationRequestDps            // 非零、正負交替
motor_command_output.duty_fraction
motor_applied_ccr                 // 1..3200
motor_applied_stby                // active 時 1
motor_applied_ain1
motor_applied_ain2
motor_runtime_fault_latched       // 正常為 0
```

判讀：

- Gate 一直 0：先查 X/Y/Z 軸、頻率、振幅，不是查 TB6612。
- App／ESP32 連線後 duty 突然為 0：看 `motorIntensityPercent`；UART `01 00` 會設 0，`01 64` 會恢復 100%。
- Gate=1、permission=1，但 `suppression_start_allowed=0`：查 runtime fault、scheduler、driver/HAL。
- `motor_applied_ccr>0`，D5 scope 沒 PWM：確認新 CM7 ELF、D5/PA8 與 scope ground。
- D5 有 PWM、馬達不動：量 D4/STBY、VM、common ground、AO1/AO2。
- 馬達方向相反：改 config 的 direction polarity，不要交換 D2/D3。

## 5. 要調參只改這個檔

檔案：

```text
firmware/algo/CM7/Core/Inc/motor_bench_config.h
```

| 要調的項目 | 巨集 | 預設 |
|---|---|---:|
| 輸入軸 | `MOTOR_TREMOR_INPUT_AXIS` | `0`（X） |
| 演算法 | `MOTOR_SUPPRESSION_ESTIMATOR` | eHWFLC-KF |
| 補償正負反轉 | `MOTOR_COMMAND_DIRECTION_POLARITY` | `1`，反向改 `-1` |
| dps→duty gain | `MOTOR_COMMAND_GAIN_DUTY_FRACTION_PER_DPS` | `1.0` |
| deadband | `MOTOR_COMMAND_DEADBAND_DPS` | `0.0` |
| max duty | `MOTOR_COMMAND_MAX_DUTY_FRACTION` | `1.0` |
| duty ramp/tick | `MOTOR_COMMAND_MAX_DUTY_STEP_PER_TICK` | `1.0` |
| HAL CCR cap | `MOTOR_MAX_ACTIVE_CCR` | `3200U` |
| boot intensity | `MOTOR_DEFAULT_INTENSITY_PERCENT` | `100U` |

若要 50% 上限，要同時改：

```c
#define MOTOR_COMMAND_MAX_DUTY_FRACTION 0.5
#define MOTOR_MAX_ACTIVE_CCR            1600U
```

只降低 CCR cap、卻讓 mapper 產生更大 duty，HAL 會報錯停機。

Gate 門檻在 `algorithms/handoff/src/gating/tremor_gate.c` 的
`TremorGate_DefaultConfig()`；不要用 `freqEstimate` 控制 gate。

## 6. 這輪要記錄的結果

- commit SHA、CM7/CM4 ELF SHA-256
- BNO address、輸入軸
- D4 STBY、D5 PWM、D2/D3 波形
- Gate、compensation request、CCR trace
- VM 電壓、電流、馬達方向
- 若方向反了，記錄最後使用的 `MOTOR_COMMAND_DIRECTION_POLARITY`

目前物理「收線／放線」的舊紀錄互相衝突，所以先記電氣方向與實際觀察，不要在未測前把
AIN1-high 寫成確定的 release/take-up。
