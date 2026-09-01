# STM32H745I-DISCO 雙核心韌體專案

這個目錄是 `STM32H745I-DISCO` 的 STM32CubeIDE 專案。CM7 負責 BNO055、100 Hz
控制鏈、encoder 與 TB6612FNG；CM4 只做雙核心啟動 handshake，之後保持 idle。此專案
不是 Nucleo pinout，也不能直接改成其他 H745 開發板後沿用接線結論。

## 目前狀態：可建置，但預設刻意不讓馬達通電

目前版本的 CM7/CM4 `Debug` 與 `Release` 都應能由 repo 內原始碼重新建置；這只代表
target compile/link 通過，不代表已燒錄或馬達實機驗證。安全基線固定
`MOTOR_BENCH_CONFIG_APPROVED=0`、HAL 的 `MOTOR_MAX_ACTIVE_CCR=0`，mapper、position guard
與 driver 的台架參數也是零值，
而且 runtime ARM 與 encoder `SetZero` 沒有可由 App 觸發的正式協定。因此正常現象是：

- `STBY=LOW`
- PWM `CCR=0`
- `motor_output_active=0`
- App 傳入長度或強度也不能繞過安全鎖

這不是把巨集改成 `1` 就能處理的問題。必須先在最終馬達、減速箱、線軸、供電與機構上
量出並 review duty、方向、encoder、行程、timeout、電流與溫升限制，再建立專用的
powered-bench build。未完成前不得接在人手上測試。

完整安全與台架契約請先讀
[`algorithms/handoff/stm32_motor_control_20260823/README.md`](../../algorithms/handoff/stm32_motor_control_20260823/README.md)。

## D2–D7 到底是什麼

`D2`、`D3` 等名稱是 STM32H745I-DISCO 板上 Arduino 相容接頭的 silk/header label，
不是 MCU GPIO 名稱。程式真正設定的是斜線後的 port/pin：

| 功能 | 板上標籤 | MCU pin / peripheral | 外部端 |
|---|---|---|---|
| AIN1 | D2 | PG3 GPIO | TB6612 `AIN1` |
| AIN2 | D3 | PA6 GPIO | TB6612 `AIN2` |
| STBY | D4 | PK1 GPIO | TB6612 `STBY`，約 10 kΩ pulldown，禁止硬接 3V3 |
| PWM | D5 | PA8 / TIM1_CH1 | TB6612 `PWMA` |
| Encoder A | D6 | PE6 EXTI | encoder C1 / A |
| Encoder B | D7 | PI8 EXTI | encoder C2 / B |
| Motor supply | — | 不接 STM32 3V3/5V | TB6612 `VM`，只接外部限流台架電源 |
| Ground | GND | common ground | STM32、TB6612、encoder、台架電源共地 |

`D5` 才是硬體 PWM 輸出；`D2`/`D3` 是方向，`D4` 是 bridge enable，`D6`/`D7`
是 encoder。若實際板子的型號或 silk 不同，先停止接線並查該板原理圖，不能照表猜。

## 原始碼 ownership

CM7 target 內保留並直接編譯下列 target-local mirror；validator 會和 canonical handoff
來源比對，不能再另外加入同名 `.c`：

- `CM7/Core/Algo/bmflc/`
- `CM7/Core/Algo/ehwflc/`
- `CM7/Core/Src/tremor_gate.c` 與 `CM7/Core/Inc/tremor_gate.h`

其餘控制與致動器模組透過 Eclipse linked resources 直接編譯下列 canonical handoff 原始碼：

- `algorithms/handoff/src/control/`
- `algorithms/handoff/src/actuator/`
- `algorithms/handoff/stm32_motor_control_20260823/src/actuator/`

所以必須從完整 repo 根目錄使用本專案；不要只複製 `firmware/algo`。CM7 的
`Core/Src/main.c` 必須與 canonical `reference/main.c` 保持一致，靜態 validator 會檢查。
Target 的 estimator 與 `tremor_gate.c/.h` 都是受 validator 約束的 mirror。

## 建置

已安裝 STM32CubeIDE 2.2.0 時，在 repo 根目錄執行：

```powershell
powershell -ExecutionPolicy Bypass -File firmware/algo/build_headless.ps1
```

腳本會使用全新的 Eclipse workspace，依序 clean-build：

1. `algo_CM7/Debug`
2. `algo_CM4/Debug`
3. `algo_CM7/Release`
4. `algo_CM4/Release`

它除了檢查程序 exit code，也會掃描 CubeIDE 的 false-success 錯誤文字、確認四個 ELF/MAP
都是本次產物，並確認 CM7 Release map 真的包含 suppression、mapper、position guard、
driver 與 HAL symbol。CubeIDE 的 `Debug/`、`Release/`、`.settings/` 是 local/generated
state，已由 `.gitignore` 排除，不能 commit。

若 CubeIDE 不在預設路徑：

```powershell
powershell -ExecutionPolicy Bypass -File firmware/algo/build_headless.ps1 `
  -CubeIdeHeadless 'D:\ST\STM32CubeIDE\STM32CubeIDE\headless-build.bat'
```

## 燒錄與實機驗證邊界

STM32H745 是雙核心，必須同時使用相符版本的：

- `firmware/algo/CM7/Debug/algo_CM7.elf`（或 Release）
- `firmware/algo/CM4/Debug/algo_CM4.elf`（或 Release）

目前不提供未經實板驗證的 `.launch`；請在確認 STM32CubeIDE dual-core programming
流程後建立並 review。不能把只燒其中一個 image 稱為完整驗證。每次上板都要記錄 board
revision、ST-LINK serial、兩個 ELF SHA-256、電源限流、scope/logic-analyzer trace 與
fault 測試。本版在沒有可用 ST-LINK 的機器上只能完成 target build；不得把它寫成
「馬達已轉」或「實機閉迴路已通過」。

## 開啟 powered bench 前仍須處理

- 從同一份 reviewed、build-bound motor config 明確記錄 HAL integer `max_active_ccr`；它必須
  不大於 driver 允許的 CCR cap。不得在 integration glue 以浮點四捨五入臨時計算，零值仍
  代表 HAL motor lock。
- 由實測決定單一 reversal deadtime owner，或證明 mapper + driver 兩層總延遲仍可覆蓋
  4–6 Hz 命令；目前不能用猜的常數。
- 建立具 CRC、framing、sequence、freshness、ARM、DISARM、E-STOP 與 keepalive 的本機
  service protocol；現有 raw 2-byte App/UART command 不得取得 bridge authority。
- position guard 的 no-motion、wrong-direction 與 active-timeout 要用最終 encoder/負載驗收；
  換向 SAFE window 不得讓 fault surveillance 永遠重置。
- 補 `min_effective_duty` 或受限啟動策略，以及硬體電流、溫度、機械 end-stop 保護。
- 若用 CubeMX 重新產碼，必須保留 CM4 的 HSEM/STOP handshake 與 idle-only ownership，
  並重新跑 validator、host tests 與四組 target builds。
