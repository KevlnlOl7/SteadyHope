# STM32H745I-DISCO 馬達台架韌體

這是 `STM32H745I-DISCO` 雙核心 CubeIDE 專案。CM7 負責 BNO055、100 Hz
gate／估測演算法與 TB6612FNG；CM4 只做雙核心啟動 handshake，之後 idle。

## 現在這版會不會輸出？

會。這版預設是 **powered bench profile**，不再是 motor-off shadow build：

- 上電即 `motor_runtime_armed=1`
- 預設 intensity `100%`
- `MOTOR_MAX_ACTIVE_CCR=3200`，允許 TIM1 完整 duty 範圍
- mapper／TB6612 driver 使用有效非零設定
- 不要求 debugger 手動 ARM
- 不要求 encoder `SetZero`；encoder/position guard 在這個 profile 只作 telemetry，不會 veto PWM
- BNO055 `0x28` 與 `0x29` 都會自動偵測並使用

仍保留 gate、IMU fresh sample、100 Hz scheduler、數值有效性、換向 safe tick、driver 與 HAL
檢查。Gate 未開、IMU 讀取失敗或 scheduler overrun 時，正確結果仍是 `STBY=LOW`、`CCR=0`。

控制路徑：

```text
BNO055 100 Hz
  -> 選定 X/Y/Z 軸
  -> eHWFLC-KF 或 BMFLC
  -> hardened 4-6 Hz gate
  -> compensation_request_dps = -tremorEstimate
  -> duty/direction mapper
  -> TB6612 driver
  -> D2/D3/D4/D5
```

所有台架調整集中在
[`CM7/Core/Inc/motor_bench_config.h`](CM7/Core/Inc/motor_bench_config.h)，不要再到
`main.c` 各處找旗標。

## 瑋哲接線表：D2-D7 不要再猜

`D2`～`D7` 是板上 Arduino CN6 header label，不是 MCU GPIO 名稱。下表已對照
STM32H745I-DISCO 的 `.ioc`、CM7 GPIO/MSP 與 ST 的 UM2488 Rev 10 Table 8。

| STM32H745I-DISCO | MCU / peripheral | 接到外部 | 用途 |
|---|---|---|---|
| `D2` | `PG3` GPIO | TB6612 `AIN1` | 馬達方向 1 |
| `D3` | `PA6` GPIO | TB6612 `AIN2` | 馬達方向 2 |
| `D4` | `PK1` GPIO | TB6612 `STBY` | H-bridge enable；**舊的 STBY→3V3 必須拆掉** |
| `D5` | `PA8 / TIM1_CH1` | TB6612 `PWMA` | 20 kHz hardware PWM |
| `D6` | `PE6` EXTI | encoder `A / C1 / 黃` | x4 encoder telemetry；本 profile 可不接 |
| `D7` | `PI8` EXTI | encoder `B / C2 / 綠` | x4 encoder telemetry；本 profile 可不接 |
| `3V3` | logic supply | TB6612 `VCC` | logic 電源；不是馬達電源 |
| `GND` | common ground | TB6612 `GND/PGND`、encoder GND、bench supply `-` | **四者必須共地** |
| 外部限流電源 `+` | — | TB6612 `VM` | 依實際馬達額定電壓供電；不要接 STM32 3V3 |
| TB6612 `AO1/AO2` | channel A output | 馬達兩條線 | 馬達輸出；不要接到 `BO1/BO2` |

最容易接錯的是 `STBY`：舊硬體曾把它直接接 3V3；現在程式是由 `D4/PK1` 控制。
如果仍硬接 3V3，D4 便失去控制；如果完全沒接 D4，TB6612 內部 pulldown 會令 driver 一直
standby。先拆掉舊 3V3 線，再接 `D4 -> STBY`。不要把 `D5` 接到 STBY；`D5` 只接 `PWMA`。

板上 MCU I/O 是 3.3 V；原廠 pinout 見
[ST UM2488](https://www.st.com/resource/en/user_manual/um2488-discovery-kits-with-stm32h745xi-and-stm32h750xb-mcus-stmicroelectronics.pdf)，
TB6612 的 VCC、VM、STBY 與 channel-A pin 定義見
[Toshiba TB6612FNG datasheet](https://toshiba.semicon-storage.com/info/TB6612FNG_datasheet_en_20141001.pdf?did=10660&prodName=TB6612FNG)。

## Gate 何時才會開

預設選 X 軸、eHWFLC-KF；hardened gate 的預設條件是：

- 4–6 Hz tremor band envelope `>= 6 dps`
- tremor/voluntary energy ratio `>= 0.55`
- 連續 20 個 100 Hz samples 成立後開啟
- 關閉門檻為 `3 dps`、ratio `0.45`、連續 15 samples

所以拿板子慢慢轉、只晃 Y/Z 軸或振幅太小時，本來就不會有 PWM。第一輪可用 X 軸約
`5 Hz`、`12–15 dps` 的離架輸入確認路徑。

CubeIDE Live Expressions 建議依序看：

```text
bno_detected_address
imu_ready
selectedGyroInputDps
gate_enabled_debug
actuation_permitted_debug
suppression_start_allowed
motorIntensityPercent
compensationRequestDps
motor_command_output.duty_fraction
motor_applied_ccr
motor_applied_stby
motor_applied_ain1
motor_applied_ain2
motor_runtime_fault_latched
```

不要用會停住 CPU 的 breakpoint 看 100 Hz PWM；停住 CPU 會製造 scheduler overrun，程式便會
正確 ForceSafe。使用 Live Expressions、scope 或 logic analyzer。

`motorIntensityPercent` 開機是 `100`，但現有 UART command `01 xx` 仍可在 runtime 改成
`0–100`。若 App／ESP32 連線後突然沒有輸出，先確認它是否送了 `01 00`；回到 full output
可送 `01 64`（hex 的 100），或 reset 讓它回到 config 的 boot 值。

## 瑋哲要調什麼、改哪裡

只改 [`motor_bench_config.h`](CM7/Core/Inc/motor_bench_config.h)：

| 想調整的行為 | 巨集 | 現值 | 怎麼改 |
|---|---|---:|---|
| IMU 軸 | `MOTOR_TREMOR_INPUT_AXIS` | `0` | `0=X, 1=Y, 2=Z` |
| 演算法 | `MOTOR_SUPPRESSION_ESTIMATOR` | eHWFLC-KF | 可改 `SUPPRESSION_ESTIMATOR_BMFLC` |
| 補償方向相反 | `MOTOR_COMMAND_DIRECTION_POLARITY` | `1` | 只改成 `-1`；不要交換 D2/D3 接線 |
| 小訊號忽略量 | `MOTOR_COMMAND_DEADBAND_DPS` | `0.0` | 增加會減少小命令 |
| dps 到 duty 增益 | `MOTOR_COMMAND_GAIN_DUTY_FRACTION_PER_DPS` | `1.0` | 太暴力就降低，例如 `0.25` |
| 最大 duty | `MOTOR_COMMAND_MAX_DUTY_FRACTION` | `1.0` | `0.5` 代表 50% |
| 每 10 ms duty 變化 | `MOTOR_COMMAND_MAX_DUTY_STEP_PER_TICK` | `1.0` | 降低會加入 ramp |
| HAL 最大 compare | `MOTOR_MAX_ACTIVE_CCR` | `3200` | 50% cap 用 `1600` |
| 開機強度 | `MOTOR_DEFAULT_INTENSITY_PERCENT` | `100` | `0–100`；UART `01 xx` 亦可即時改 |
| 換向空白時間 | mapper/driver `REVERSAL_DEAD_TICKS` | 各 `1` | 每 tick = 10 ms |

若降低最大 duty，`MOTOR_COMMAND_MAX_DUTY_FRACTION` 與 `MOTOR_MAX_ACTIVE_CCR` 必須一致：

```text
MOTOR_MAX_ACTIVE_CCR = 3200 × max duty
```

例如 50% 要同時設 `0.5` 和 `1600U`。如果只把 HAL cap 改小、mapper 仍產生更大 CCR，HAL
會拒絕命令並 latch fault，不會自動裁切。

Gate 門檻不在 motor config；source of truth 是
[`algorithms/handoff/src/gating/tremor_gate.c`](../../algorithms/handoff/src/gating/tremor_gate.c)
的 `TremorGate_DefaultConfig()`。若改 gate，必須同步 target mirror 並重跑 validator。

物理「收線／放線」在舊紀錄中互相矛盾，repo 目前只能確定兩組電氣方向。請先讓馬達離開
機構，用短測試觀察：若演算法補償方向相反，只改
`MOTOR_COMMAND_DIRECTION_POLARITY`，不要重接 D2/D3。

## 無 PWM 時照這個順序查

1. `imu_ready=0`：查 BNO055 SDA/SCL、供電、共地；`bno_detected_address` 應為 `0x28` 或 `0x29`。
2. `gate_enabled_debug=0`：確認輸入軸、4–6 Hz、振幅與 20-sample 開啟時間。
3. gate=1 但 `suppression_start_allowed=0`：看 `motor_runtime_fault_latched`、scheduler 與 driver/HAL fault。
4. `motor_applied_ccr>0` 且 `motor_applied_stby=1`，PA8/D5 卻沒 PWM：確認燒的是新 CM7 ELF、D5 與 scope ground。
5. D5 有 PWM但馬達不動：依序量 `D4/STBY`、`VM`、common GND、`AO1/AO2`；不要再改 gate。
6. 只有方向不對：改 `MOTOR_COMMAND_DIRECTION_POLARITY`，不要交換控制線。

## 建置與燒錄

在 repo root 執行：

```powershell
python .\algorithms\validation\validate_cubeide_motor_integration.py
python .\algorithms\validation\validate_stm32_motor_main.py `
  --main .\firmware\algo\CM7\Core\Src\main.c --skip-shadow
.\algorithms\handoff\test\run_actuator_tests.bat
powershell -ExecutionPolicy Bypass -File .\firmware\algo\build_headless.ps1
```

必須同時燒錄相同 build profile 的兩個 image：

- `firmware/algo/CM7/Debug/algo_CM7.elf`
- `firmware/algo/CM4/Debug/algo_CM4.elf`

或同時使用兩個 `Release` ELF。只燒 CM7 或只燒 CM4 不是完整雙核心更新。

第一輪請把馬達與線軸固定在離架夾具，先確認 `D4/D5/AO1/AO2` 波形再接負載。這版是為了
解除軟體阻擋、開始台架量測；尚未宣稱物理方向、負載電流、溫升或抑震成效已驗證。
