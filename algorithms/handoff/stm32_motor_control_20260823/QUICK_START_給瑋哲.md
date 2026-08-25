# 給瑋哲：STM32 馬達控制台架 Quick Start

## 0. 這次只驗證什麼

本輪第一個目標是把 0823 canonical `main.c` 正確整合進瑋哲實際編譯的 CM7 專案，確認最新版控制鏈、fresh-sample contract、telemetry 與 ForceSafe。**目前不是直接驅動馬達或上手測試。**

Canonical 預設：

```c
#define MOTOR_BENCH_CONFIG_APPROVED 0U
```

因此不論 gate、runtime arm 或 App 指令為何，控制鏈都必須維持 ForceSafe：`motor_output_active=0`、`STBY=LOW`、`CCR=0`。開機強度也預設為 0%，後續必須由已審核的 App／台架操作明確設定，但強度指令本身不能取得 motor authority。這是刻意的安全鎖，不是待修問題。不得為了讓馬達轉動直接改成 1；只有 mapper、PWM、方向、encoder、行程、timeout 與 fault config 都有最終硬體的台架證據並完成 review 後，才能另建 powered-bench build。

後續若取得明確台架核准，限定條件才是 `6 V`、限流 bench supply、馬達與線軸固定在夾具、不接手套、不接人體。即使台架通過，也不代表可用 12 V、上手、人體測試或商品設定。

若要同時驗證新版 gate，必須先完成
`../stm32_gate_upgrade_20260822/QUICK_START_給瑋哲.md` 的 motor-off 測試，確認
14,700 筆 STM32 輸出逐筆比對通過後，才進入本文件的馬達台架步驟。

先從 repo root 跑 validator：

```powershell
python .\algorithms\validation\validate_stm32_motor_main.py
```

Validator 通過後，再跑 host tests：

```powershell
.\algorithms\handoff\test\run_actuator_tests.bat
```

兩者都必須全部 `PASS`，但這只證明 static contract、host C 與範例語法，不能取代 CubeIDE target build、scope 波形或台架證據。

### 0.1 唯一 canonical `main.c`

最新版只看：

```text
algorithms/handoff/stm32_motor_control_20260823/reference/main.c
```

0822 shadow 是 sealed historical evidence；`example/stm32_motor_integration_example.c` 也不是完整 `main.c`。上述 canonical 檔位於演算法交接目錄，**CubeIDE 不會自動編譯它**。瑋哲必須明確將它整合到自己 branch 的：

```text
firmware/algo/CM7/Core/Src/main.c
```

若 `.ioc`、peripheral handles 與 canonical 基底完全一致，可保留原檔 Git diff/build ID 後複製覆蓋；若 CubeMX 產生區、timer、UART、I2C 或 pin mapping 不同，只移植 canonical 的 USER CODE 與 pipeline，不可盲目覆蓋產生區。整合後立即對真正要編譯的檔案再跑：

```powershell
python .\algorithms\validation\validate_stm32_motor_main.py `
  --main .\firmware\algo\CM7\Core\Src\main.c
```

這次 validator 也必須通過，才可 Clean Build CM7。

## 1. 接 VM 前逐項確認

本節是取得 reviewed bench config 與 powered-bench 核准後的條件清單。在 `MOTOR_BENCH_CONFIG_APPROVED=0` 的目前階段，VM 與馬達電源保持實體斷開。

- [ ] 拆掉 `STBY → 3V3`。
- [ ] 改接 `D4 / PK1 → STBY`，並在 STBY 對 GND 加約 `10 kΩ` pulldown。
- [ ] `D2 / PG3 → AIN1`、`D3 / PA6 → AIN2`、`D5 / PA8 → PWMA`。
- [ ] Encoder `A/黃 → D6/PE6`、`B/綠 → D7/PI8`。
- [ ] STM32、TB6612、encoder、bench supply 全部共地。
- [ ] 用電錶確認 VM/VCC 無短路；馬達、線軸和繩線均固定且不會打到人。
- [ ] 6 V 電源已限流，另有外部保護和可立即實體斷電的方法。
- [ ] 舊的「full-duty 正/反轉各 2 秒」測試狀態機已移出 build。

任一項未完成就不要接 VM。TB6612 的 STBY 若仍硬接 3V3，本模組無法保證 reset/fault 時關閉 bridge。

## 2. CubeMX / `.ioc`

### GPIO 和 PWM

1. `PG3`：label `MOTOR_AIN1`，GPIO output，initial LOW。
2. `PA6`：label `MOTOR_AIN2`，GPIO output，initial LOW。
3. `PK1`：label `MOTOR_STBY`，GPIO output，initial LOW。
4. `PA8`：`TIM1_CH1` PWM，不再當 fixed-HIGH GPIO；initial Pulse/CCR = 0。
5. 先量測 TIM1 kernel clock。只有 64 MHz、edge-aligned up-counting 時才設 `PSC=0`, `ARR=3199`；此時 driver/HAL 的 `pwm_full_scale_ccr` 應一致為 `ARR+1=3200`，但實際 max duty 仍須另行限制。否則依實際 clock 重算 20 kHz。
6. 啟動後用 scope/logic analyzer 量 PA8，確認 20 kHz；safe state duty 必須為 0。

### Encoder EXTI

1. `PE6 / ENCODER_A`：rising + falling EXTI。
2. `PI8 / ENCODER_B`：rising + falling EXTI。
3. 啟用 `EXTI9_5_IRQn`。
4. 每次 A 或 B 中斷都立即重讀 A/B 兩腳，再呼叫 `QuadratureEncoder_OnEdge()`。
5. ISR 不做 `printf`、blocking UART、delay 或分析運算。不能改成 100 Hz polling。

### Control tick

- 保持獨立 `100 Hz`（10 ms）固定 tick。
- PWM channel 啟動一次；100 Hz tick 只更新 CCR/GPIO command。
- 傳輸和檔案輸出放在非 ISR 工作中，並量測 scheduler overrun。

## 3. 加入 CM7 build

Canonical source 使用 header basename，禁止改成任何人的 `C:/Users/...` 絕對 include。CubeIDE 的 CM7 include search paths 至少加入：

```text
firmware/algo/CM7/Core/Inc
algorithms/handoff/src/control
algorithms/handoff/src/gating
algorithms/handoff/src/actuator
algorithms/handoff/src/bmflc
algorithms/handoff/src/ehwflc
algorithms/handoff/stm32_motor_control_20260823/src/actuator
```

另加入實際存放 `BNO055_STM32.h` 的目錄。Include path 只解決 header；下列 portable/adapter `.c` 仍須明確加入 CM7 build。

由 repo 加入：

```text
algorithms/handoff/src/gating/tremor_gate.c/.h
algorithms/handoff/src/actuator/quadrature_encoder.c/.h
algorithms/handoff/src/actuator/motor_position_guard.c/.h
algorithms/handoff/src/actuator/tb6612_driver.c/.h
algorithms/handoff/stm32_motor_control_20260823/src/actuator/stm32_tb6612_hal.c/.h
algorithms/handoff/src/control/motor_command_mapper.c/.h
algorithms/handoff/src/control/suppression_control.c/.h
algorithms/handoff/src/bmflc/*
algorithms/handoff/src/ehwflc/*
```

其中 `tremor_gate.c/.h` 是 4–6 Hz hardened 版本，必須成對取代 8/18 branch 的 3–8 Hz舊檔，再執行 CubeIDE Clean Build。禁止只換 `.c`、只貼濾波係數或沿用舊 object。不要復活舊的低通-相減前處理，不要用 `freqEstimate` 做 gating。

先保持 H-bridge／motor power 實體斷開，以 21 組 6–7 Hz boundary vectors 驗證板上逐筆輸出。只有 C/Python 的 raw、envelope、ratio、on-count、enabled 全部一致，才能宣稱「最新版 gate 已成功移植」；這仍不等於取得接馬達或人體測試權限。

測資位於：

```text
algorithms/handoff/test_vectors/gating_6to7_boundary/
```

STM32 test mode 每個 case 都要重新 `TremorGate_Init()`，以 100 Hz 依序注入 header 內的 700 筆 raw sample，並輸出合計 14,700 筆 CSV。至少包含：

```text
test_case_id,sample_index,sample_tick_ms,gyro_x_raw_lsb,
tremor_envelope,voluntary_envelope,tremor_ratio,on_count,gate_enabled
```

不要把最後一欄命名成 `motor_enabled`；這一輪比的是 gate，不是實際馬達。將 STM32 log 拿回 PC 後，從 repo root 執行：

```powershell
python algorithms/validation/compare_stm32_6to7_boundary_log.py `
  --input stm32_6to7_log.csv `
  --output-json stm32_6to7_comparison.json
```

驗收必須是 `pass=true`、`expected_rows=actual_rows=14700`，且 missing、unexpected、duplicate、tick、raw、on-count、enabled 與三個 float mismatch 全為 0。這段 test mode 仍須在瑋哲的實際 `main.c`／scheduler 接上，交付 ZIP 不是可直接 flash 的 `.bin`。

目前 repo 沒有你的最新 CubeIDE 專案，這步必須在你的 branch 手動整合。整合後保留 `.ioc`、CM7 Release build log、ELF/MAP hash、source hash 和實測波形。

## 4. 所有控制值都要由 bench 證據決定

不可從 unit test 或範例複製以下值：

- mapper 的 deadband、gain、max duty、slew、max request、direction polarity、reversal dead ticks；
- TB6612 的 CCR ceiling、max duty、release polarity、reversal dead ticks；
- position guard 的正負行程、每 tick 最大位移、no-motion 視窗、最大 active ticks；
- encoder count polarity 和 counts per output revolution。

正式 config 要由最終馬達、6/12 V 供電、10 mm 線軸、繩線、機構、負載、電流及溫度量測產生，經審核後綁定 release。

## 5. Boot 與 SetZero

1. GPIO 初始化即令 `STBY=LOW`, `AIN1=LOW`, `AIN2=LOW`。
2. CCR=0 後才啟動 PWM channel。
3. Encoder EXTI 關閉時讀真實 A/B level，呼叫 `QuadratureEncoder_Init()` 後再開 EXTI。
4. 用同一份 reviewed config snapshot 初始化 mapper、position guard、TB6612 driver 和 HAL adapter。
5. Boot 保持 `CALIBRATION_REQUIRED`，`motor_output_active=0`。
6. Bridge off 時由人員把機構放到中立位置，再以獨立按鈕或已認證指令明確觸發 `SetZero`。
7. Reset、brownout、watchdog 或 position fault 後回到第 5 步；禁止自動沿用上次零點或輸出。

## 6. 每個 100 Hz tick 的順序

```text
1. SuppressionControl_Update()
   -> gate_enabled / actuation_permitted / compensation_request_dps

2. MotorCommandMapper_Update()
   -> abstract direction / duty / bridge_enable

3. TB6612Driver_Update()
   -> 產生 actual candidate AIN1 / AIN2 / STBY / CCR；換向 dead ticks 時為 STOP

4. QuadratureEncoder_Snapshot()
   -> consistent count and encoder fault state

5. MotorPositionGuard_Update()
   -> 只用 actual candidate 的 direction / ACTIVE 狀態檢查行程和 motion

6. STM32_TB6612_HAL_Apply()
   -> physical GPIO/CCR; any failure calls ForceSafe
```

順序不可把 position guard 放在 TB6612 driver 前面：driver 的 reversal deadtime 會輸出 SAFE/STOP，guard 也必須看到 STOP，否則會把尚未加電的 dead ticks 誤算成 no-motion。若 guard veto 一個 ACTIVE candidate，要再呼叫一次 `TB6612Driver_Update(..., permission=0)` 取得新的 safe output，之後才交給 HAL；position fault 只可在 bridge off、重新確認中立點後以 `SetZero` 復原。

`gate_enabled`、`actuation_permitted`、`motor_output_active` 是三欄，不得再合成 `motor_enabled`。最後一欄只有實際有效 command 為 `STBY=1`、`CCR>0` 且方向有效時才是 1。

`encoder_valid` 只能在 snapshot 成功、`initialized==1`、`invalid_transition_latched==0`、`overflow_latched==0` 時為 1。

未取得 encoder snapshot、未 SetZero、guard 拒絕、driver error、HAL error 或 scheduler overrun 時，當 tick 必須：

```c
STM32_TB6612_HAL_ForceSafe(&motor_hal);
motor_output_active = 0U;
```

## 7. 極性和 encoder 校正

### 7.1 先確認方向

在離架、限流、固定夾具下，只送由 bench 決定的最低能量短脈衝；本文件不給可直接複製的 duty 或脈衝寬度。

- `direction=+1` 必須是 FORWARD/RELEASE（正轉放線）且 count 增加。
- `direction=-1` 必須是 REVERSE/TAKE_UP（反轉收線）且 count 減少。
- Stop 時必須 `STBY=0`, `CCR=0`。

不一致立即斷電，分開修正 `release_ain1_level` 與 `count_polarity` 後重測。

### 7.2 再量 counts/rev

1. 在輸出軸和機架畫對齊記號。
2. 記錄 start count，同方向完整轉輸出軸 10 圈，再記 end count。
3. RELEASE、TAKE_UP 各至少做 3 次。
4. 計算 `abs(end-start)/10`，比較方向間和重複間差異。
5. 同時記錄 invalid-transition count、overflow latch、供電與 firmware build ID。

在完成此量測前，不要假設 encoder 是 11 或 12 PPR/CPR，也不要把理論齒比寫成正式行程參數。

## 8. 第一輪台架驗收

- [ ] Reset/boot 全程 STBY/AIN1/AIN2 LOW、CCR 0。
- [ ] 未 SetZero 時，gate 開也沒有馬達輸出。
- [ ] SetZero 只在 bridge off 且 encoder snapshot 有效時成功。
- [ ] RELEASE=count+、TAKE_UP=count-，無 invalid/overflow。
- [ ] 換向時存在完整 zero-output dead ticks。
- [ ] Gate off、sensor stale、NaN/Inf、inhibit、watchdog、scheduler overrun 都在下一 control tick ForceSafe。
- [ ] 注入 encoder invalid、超行程、wrong/no motion、max-active-time 時皆 latch fault 並 ForceSafe。
- [ ] Fault 後不自動復轉；reset 後回 `CALIBRATION_REQUIRED`。
- [ ] Log 分開記錄 gate、permission 和 actual motor command。
- [ ] 有 20 kHz PWM 及 boot/fault/reversal 的 STBY/AIN/CCR 儀器截圖。

全部通過仍只代表離架台架整合。改成 12 V 前，要另立一輪電流、溫度、轉速、負載、行程、制動、過衝與 fault-injection 驗證。
