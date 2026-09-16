# SteadyHope 顫抖抑制演算法 — 韌體交接包

**演算法組 → STM32 韌體組**。本包目的：讓韌體組能把顫抖抑制演算法編進 STM32，
並**先在數值上驗證移植正確、再去信任硬體結果**。

> 🔧 **要動手把程式碼放進 STM32CubeIDE 專案，看 [INTEGRATION.md](INTEGRATION.md)**（加檔案、include path、CM7/FPU、BNO055 raw gyro 讀法、100 Hz 時序、常見坑）。本檔是介面契約與驗證流程。

兩個顫抖估測器，加上一個獨立的馬達啟用判斷模組：

| | BMFLC | eHWFLC-KF |
|---|---|---|
| 結構 | 38-weight NLMS（19 頻率 × sin/cos） | 6-state Kalman + WFLC 頻率追蹤 |
| 頻帶 | 3–12 Hz 固定多頻帶 | 以 WFLC 追蹤基頻（3–12 Hz）+ 3 階諧波 |
| 前處理 | 2–20 Hz 帶通 | 2–20 Hz 帶通 |
| 輸出 | `tremor_est` | `tremor_est` + `freq_hz` |

> 兩者可同時跑、各自獨立，韌體可先用其中一個驗證流程，再比較。

`src/gating/tremor_gate.c/.h` 是 V2 雙頻帶 gating：直接讀同一筆 raw gyro，
比較 4–6 Hz 顫抖帶與 1–3 Hz 自主動作帶，輸出 `enabled`。它只決定馬達
「能不能動」；馬達方向與輸出大小仍由 `tremor_est` 決定。設計與上板驗收見
[GATING_DESIGN.md](GATING_DESIGN.md)。

PWM 比例控制、N20 loaded bandwidth test、actuator 選型門檻與實測紀錄格式見
[ACTUATOR_CONTROL.md](ACTUATOR_CONTROL.md)。目前 `control_sim.m` 實作是 P-only；取得
真實 actuator gain／頻寬／延遲前，不應直接加入 `Ki/Kd` 或照抄模擬 `Kp`。
目前已整合的 powered-bench 接線、Gate→演算法→PWM 路徑、單一調參入口與 CubeIDE build
指令以 [`firmware/algo/README.md`](../../firmware/algo/README.md) 為準；encoder/SetZero 在此
profile 為 telemetry-only，不是 PWM veto。

---

## 1. 介面契約（API）

```c
/* src/bmflc/BMFLC_step.h */
double BMFLC_step(double signal_sample);   /* 回傳 tremor_est (°/s) */
void   BMFLC_step_init(void);

/* src/ehwflc/eHWFLC_KF_step.h */
void   eHWFLC_KF_step(double signal_sample, double *tremor_est, double *freq_hz);
void   eHWFLC_KF_step_init(void);

/* src/gating/tremor_gate.h */
TremorGateConfig TremorGate_DefaultConfig(void);
void TremorGate_Init(TremorGate *gate, const TremorGateConfig *config);
uint8_t TremorGate_Update(TremorGate *gate, double raw_gyro_dps);
```

| 項目 | 契約 |
|---|---|
| **輸入** `signal_sample` | 單軸**陀螺儀角速度，單位 °/s**。不是加速度——模型參數是以 gyro °/s 校的，換物理量要重新確認 scale 與頻帶。 |
| **取樣率** | **寫死 fs = 100 Hz**（`dt`、帶通係數都是 100 Hz）。改取樣率**必須重產生 C**，不能只改韌體餵入頻率，否則頻率追蹤全錯。 |
| **初始化** | 首次呼叫 `*_step` 會自動 init；要重置狀態（換使用者、重新開始）才需顯式呼叫 `*_init()`。 |
| **狀態** | file-scope `static` → **單例，只能跑一軸**。多軸需多份實例或以 reentrant 模式重產生。 |
| **輸出** `tremor_est` | 估測出的**顫抖分量**（°/s），即「要被抵銷的東西」。`voluntary = signal − tremor_est` 是要保留的自主動作。 |
| **輸出** `freq_hz` | **已知不可靠，禁止用於 gating 或 App biomarker。**它可能被自主動作拖到 3 Hz 下限後無法追回顫抖頻率；保留此輸出只為相容既有 Coder API。頻率回報改用 raw gyro 的短窗 FFT 或 4–6 Hz 帶通過零率。 |
| **gating 輸出** `enabled` | `uint8_t`；0 表示馬達必須停止，1 表示允許抑震控制。它不是 PWM duty，也不代表馬達方向。 |
| 型別 / 記憶體 | 全程 `double`（M7 有 DP FPU）。無動態配置、無遞迴、堆疊用量小（< 1 KB）。 |

### 致動器接法（控制律由硬體組校）
`tremor_est` 是要抵銷的顫抖估測。致動器以**反相**抵銷：

```c
actuator_drive( -(GAIN * tremor_est) );   // GAIN / 符號 / 相位延遲需在硬體上校正
```

GAIN、致動器極性、機械相位延遲屬硬體標定，本包不預設；演算法只負責給出 `tremor_est`。

---

## 2. 兩個已解決的關鍵點（記錄，供理解設計）

1. **eHWFLC-KF 原本的 Coder C 內含 x86 SSE2（`<emmintrin.h>`/`__m128d`），ARM 編不過。**
   已用「ARM 目標 + 關閉 SIMD」重新產生解決（見 §4 / `../matlab/codegen_arm.m`）。
   現在 `src/` 的 C **已是 ARM-safe 純量版，無 SSE2**，且與模型逐點等價（§5 已 PASS）。

2. **取樣率鎖定 100 Hz。** fs 寫死在 C 裡（`dt`、帶通係數）；裝置端須確實以 100 Hz
   餵 raw gyro（見 §3）。改 fs 必須重產生（`../matlab/codegen_arm.m`），不能只改韌體。

---

## 3. 韌體須知：用 raw gyro 餵 100 Hz（避開 I2C 瓶頸）

CLAUDE.md 記的「BNO055 有效取樣率 ~37 Hz」是**融合模式下，讀整批融合暫存器（~26 bytes）
被 I2C clock-stretching 拖慢**的結果。本演算法要的是 **raw gyro（角速度 °/s）**，
跟融合無關：

- 用**非融合模式**讀 gyro，每筆只讀 `GYR_DATA` **6 bytes**。即使 100 kHz standard-mode I2C，
  單次也才 ~0.8 ms（< 10 ms 預算的 8%）；切 **400 kHz fast-mode** 更寬裕 → **100 Hz 穩定可行**。
- `UNIT_SEL` 保持 gyro 為 **°/s**（預設 dps），別切 rad/s，否則尺度全錯。
- `GYR_CONFIG` 頻寬設 ≥ 顫抖帶（如 47 或 116 Hz），確保每個 100 Hz tick 都有新樣本。
- **單軸**：先挑顫抖最明顯那一軸（單例狀態限制）。
- **別在 ISR 裡阻塞等 I2C**：用 100 Hz timer 觸發 DMA / 中斷式 I2C 讀，
  資料到齊的 callback 再跑 `*_step`。

### ISR 骨架
```c
/* 100 Hz timer / I2C-complete callback */
void on_new_gyro_sample(float gyro_dps_axis) {
    double tr, fr;
    eHWFLC_KF_step((double)gyro_dps_axis, &tr, &fr);   /* 或 BMFLC_step */
    actuator_drive(-(float)(GAIN * tr));
}
```

---

## 4. 如何（重新）產生 ARM-safe C

**已自動化**：在 `../matlab/` 開 MATLAB → 執行 `codegen_arm.m`，它用下列設定重產生、
自動覆蓋 `src/bmflc`、`src/ehwflc`，並提示跑 §5 Stage 1。

`codegen_arm.m` 內含的關鍵設定：
```matlab
cfg = coder.config('lib');
cfg.TargetLang = 'C';
cfg.HardwareImplementation.ProdHWDeviceType = 'ARM Compatible->ARM Cortex-M'; % ★ 不再產生 SSE2
cfg.InstructionSetExtensions = 'None';           % 額外保險
cfg.EnableDynamicMemoryAllocation = false;       % 新版 API（舊 DynamicMemoryAllocation 已淘汰、會讓 codegen 報錯）
codegen -config cfg BMFLC_step     -args {0.0}   % 單參數入口 → fs 寫死 100
codegen -config cfg eHWFLC_KF_step -args {0.0}
```

重產生後 `codegen_arm.m` 會自檢 `eHWFLC_KF_step.c` 是否已無 `emmintrin`。

> 若改 fs（例如真的只能 50 Hz）：`.m` 已內建 50 Hz 帶通係數，但 100 Hz 的驗證數據會作廢、
> 且 37 Hz 以下帶通上限會超過 Nyquist（需重設計）。建議維持 100 Hz。

---

## 5. 驗證流程（三階段，順序不能跳）

### Stage 1 — 數值等價性（離線，PC 或板上）★ 先過這關
證明「要燒的 C」逐點等於 MATLAB 模型。**沒過這關，任何硬體結果都無法解讀。**

```sh
cd handoff
sh test/build_and_run.sh        # Windows: test\build_and_run.bat
```
預期：`ALL PASS`，三個輸出 `max|err| < 1e-6`。
（目前重產生的 ARM 純量 C 對 golden 為 **`max|err| = 0`（逐位元相同）**；
golden 另與獨立 Python 重實作交叉比對為 ~1e-14。）

> Windows 中文路徑下 MinGW linker 可能無法寫出 .exe——把整包複製到純 ASCII 路徑再 build 即可
> （ARM toolchain / CI 無此問題）。

### Stage 2 — 在板即時性（on-device）
量單步耗時，確認在 10 ms 預算內（100 Hz）：

```c
CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
DWT->CYCCNT = 0;  DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
uint32_t t0 = DWT->CYCCNT;
eHWFLC_KF_step(sample, &tr, &fr);
uint32_t cyc = DWT->CYCCNT - t0;   /* 時間(us) = cyc / (SystemCoreClock/1e6) */
```
不要用 clock 比例粗估耗時。請在實機記錄 clock、cache、build configuration 與輸入範圍，
並確認最壞情況小於 10 ms；不同設定的量測不能直接互相代用（現有紀錄見
[GATING_DESIGN.md](GATING_DESIGN.md) §2）。
另：把 `golden/input.csv` 存成陣列在板上跑，輸出對 `golden/*.csv` 比對，
確認 ARM build 也數值一致。

再使用 `test_vectors/gating_frequency/` 的1～8 Hz固定向量，
斷開馬達後注入同一個100 Hz tick。1–3與7–8 Hz應維持`enabled=0`，4–6 Hz應啟動後
再於訊號停止時關閉。這是在驗證板上gating，不是以人工手抖取代標準訊號。

### Stage 3 — 閉迴路抑制（硬體）= 真正回答「演算法有沒有用」
gyro（單軸 °/s, 100 Hz）→ `*_step` → `tremor_est` → 致動器反相。
用已知顫抖源（shaker 或病患）量「抑制前/後」的 gyro 功率，算顫抖功率降低率。
**只有 Stage 1–2 過了，這個結果才可信。**

---

## 6. 指標的誠實邊界（引用數據務必分清）
- **RMSE / 功率降低（合成訊號）** 與 **ETVM（真實病患）** 是不同量、**不可直接互相比較**。
- 報告時標清楚是哪一種、哪個資料來源、哪個 fs，避免誤導性對照。

---

## 7. 目錄結構
```
handoff/
├── README.md                  ← 本檔（介面契約 + 驗證流程）
├── INTEGRATION.md             ← STM32CubeIDE 整合步驟教學（怎麼把 code 放進去）
├── BNO055_GYRO_SETUP.md       ← 感測器端專屬：切 raw gyro、設 400kHz、跑穩 100Hz、除錯表
├── GATING_DESIGN.md           ← V2 gating 設計、限制與板上驗收流程
├── ACTUATOR_CONTROL.md        ← PWM/P control、N20 頻寬驗證、actuator/第二顆 IMU 選型門檻
├── TREMOR_FREQUENCY.md        ← STM32/BLE欄位、FFT/PSD與App主振幅圖定案規格
├── APP_PSD_IMPLEMENTATION.md  ← App從BLE解析到FFT/PSD、RMS及圖表的逐步實作
├── REAL_DATA_PROTOCOL.md      ← 實機100 Hz錄製情境、欄位與gating門檻校調
├── STM32_ROBUSTNESS_TEST_PLAN.md ← 7 Hz、混合、timer、jitter與dropout板上交接
├── SUPPRESSION_VALIDATION.md  ← PWM request與第二顆IMU Motor OFF/ON成效驗證
├── templates/                 ← 離線/實機測試紀錄與版本追蹤空白表格
├── src/
│   ├── bmflc/                  BMFLC C（ARM-safe，純 scalar；含自含 rtwtypes.h）
│   ├── ehwflc/                 eHWFLC-KF C（ARM-safe，已重產生無 SSE2）
│   ├── gating/                 V2 雙頻帶 gating C（不依賴 HAL、instance-based）
│   └── README.md
├── test_vectors/
│   ├── gating_frequency/       1～8 Hz CSV、STM32 C陣列與逐筆golden trace
│   ├── gating_7hz_boundary/    7 Hz／10、15、20 deg/s板上輸入與逐筆golden
│   ├── gating_amplitude_sweep/ 1～8 Hz × 7振幅的56組板上輸入與逐筆golden
│   ├── gating_mixed_boundary/  2 Hz＋5 Hz代表case板上輸入與逐筆golden
│   └── gating_robustness/      完整振幅、混合、取樣率、jitter與掉點離線摘要
├── golden/
│   ├── input.csv              確定性輸入（10 s @ 100 Hz）
│   ├── golden_bmflc.csv       BMFLC 真值輸出
│   ├── golden_ehwflc.csv      eHWFLC-KF 真值輸出（tremor, freq）
│   ├── gen_golden_vectors.m   ★ 在 MATLAB 重產生權威黃金向量
│   └── README.md
└── test/
    ├── test_equivalence.c     等價性測試（讀 golden、跑 C、印 PASS/FAIL）
    ├── test_tremor_gate.c     gating基本行為與八組固定頻率向量逐筆測試
    ├── test_tremor_gate_7hz_boundary.c   7 Hz三振幅逐筆C/reference
    ├── test_tremor_gate_amplitude_sweep.c 56組頻率×振幅逐筆C/reference
    ├── test_tremor_gate_mixed_boundary.c 混合訊號逐筆C/reference
    ├── build_and_run.sh       PC build（gcc/clang）
    └── build_and_run.bat      PC build（MinGW）
```

## 8. 注意事項（設計決定，不是 bug）
- 兩演算法前處理**都採 2–20 Hz 帶通**（經合成訊號效能比較選定，對自主動作穩健；
  低通-相減版在有明顯自主動作時會把 <2 Hz 動作 leak 進估測，已淘汰）。
- 顫抖帶 4–6 Hz、自主動作 ~2 Hz；BMFLC 的頻帶選擇性就是用來區分兩者。
- `Copy/demo_c/demo_main.c` 是**另一份手寫 demo，不是交付參考**（內有死碼、且 50 Hz 模式
  仍套 100 Hz 係數）。權威來源是 `.m` 與 Coder 產生的 C。

## 9. V2 gating 延伸離線模擬

執行下列命令可重產生振幅、2 Hz + 5 Hz 混合訊號、95/100/105 Hz 取樣率、timer 取樣間隔誤差
與資料掉點測試：

```powershell
python algorithms/validation/gating_robustness_sim.py
python -m unittest discover -s algorithms/validation -p "test_gating_robustness_sim.py"
```

結果、判讀與已知限制見
[`test_vectors/gating_robustness/README.md`](test_vectors/gating_robustness/README.md)。這些都是合成資料，不能當成實機抑震率或患者成效。
