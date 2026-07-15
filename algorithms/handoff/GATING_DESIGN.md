# 馬達 gating 設計 — 只在病徵頻率作動（給韌體組）

> 2026-07-09。回答的問題：**「IMU 一動馬達就跟著轉」怎麼修？馬達是否應該只在
> 病徵頻率（4–6 Hz 顫抖帶）才作動？**
>
> 結論：**要，但不能用 `freqEstimate` 判斷頻率**（已被模擬實證推翻，見 §3），
> 改用**雙頻帶能量比**（§4），純 main.c 層修改、不動估測器 C、預估半天到一天可完成。

---

## 1. 現況與根因

現行韌體（`Ryan/stm32-motor-control` 的 `CM7/Core/Src/main.c`）的觸發條件只有：

```c
controlValue = -(MOTOR_GAIN * tremorEstimate);        // MOTOR_GAIN=1.0
if (controlValue >  MOTOR_THRESHOLD) → MOTOR_FORWARD  // MOTOR_THRESHOLD=5.0
if (controlValue < -MOTOR_THRESHOLD) → MOTOR_REVERSE
```

問題分四層：

1. eHWFLC-KF 的前置帶通是 **2–20 Hz**，不是 4–6 Hz——約 2 Hz 的自主動作
   及其諧波（4 Hz、6 Hz…）都在帶內，不會被濾掉。
2. `tremorEstimate` 是**帶內訊號的重建量**，反映任何 2–20 Hz 週期性動作的振幅，
   不是「顫抖專屬」的量。
3. `freqEstimate` 有被算出來，但**控制決策從未引用它**。
4. 所以只要帶內動作重建振幅 > 5 deg/s 就會驅動馬達——這正是實測
   「一動就轉」的原因。合成訊號模擬中，2 Hz 自主動作下現行邏輯誤觸發
   duty 高達 **89%**。

## 2. Debug 截圖數據解讀（2026-07-09 Live Expressions）

| 讀值 | 判讀 |
|---|---|
| `gyroX=0.3125` (=5/16) | 靜置量化級距的小偏置，正常（raw int16 ÷16 → deg/s）。 |
| `tremorEstimate=-0.108` | 靜置殘餘噪聲，遠低於門檻 → 靜置不動作，正確。 |
| `freqEstimate=3.212 Hz` | **不是偵測到 3.2 Hz 顫抖**。機制（經獨立移植 WFLC 迴圈實測驗證）：先前的搬動/自主動作（~2 Hz，低於 omega_min=3）把 omega 一路拖到 3.0 Hz clamp 地板；靜置後殘差≈0、omega 更新≈0，**凍結**在地板上方 ~0.2 Hz 游移。注意：純靜置本身不會讓 omega 沉底（開機後完全不動會凍在初值 5 Hz），這個讀值恰好證明 omega 曾被拖到地板——見 §3 的致命後果。 |
| `algo_time_us=1439.9` | 真實值、量測窗只含 `eHWFLC_KF_step()`（不含 I2C）。慢的主因：SYSCLK 走 HSI **64 MHz**（非 PLL 480 MHz）+ 全 double 運算含 ~12 次 sin/cos + 疑似 I/D-cache 未開（main.c 未見 `SCB_EnableICache/DCache`）。64 MHz 換算 ≈ 92k cycles。**佔 10 ms 預算 14.4%，目前可用**，之後開 cache / 上 PLL 可大幅下降。 |
| counters 全部 ~50,6xx、彼此差 ≤6、`imu_read_error_count=0` | 100 Hz 管線 1:1:1:1 無掉拍、無 I2C 錯誤（差值是 Live Expressions 非同時取樣）。GYROONLY 遷移成功，**跑了約 8.4 分鐘穩定**。 |

注意：TIM6 的 100.000 Hz（Prescaler=6399, Period=99）是**以 TIM6CLK=64 MHz 算的**。
日後若把 SYSCLK 切到 PLL 提速，**必須同步改 TIM6 prescaler**，否則 tick 率會偏移、
與演算法寫死的 dt=0.01 失配。

## 3. 為什麼不能用 `freqEstimate` 做頻率窗（V1，已推翻）

直覺方案是 `gate = (4.0 ≤ freqEstimate ≤ 6.5) ∧ 振幅 ∧ 持續性`。
四情境合成訊號模擬（`algorithms/validation/gating_check.py`，fs=100 Hz）結果：

- 情境 A（純自主動作 2 Hz + 4 Hz 諧波 + reach 瞬態）：誤觸發 0.83% ✓
- 情境 B（靜置 5 s → 5 Hz 顫抖）：duty 98.6%、onset 210 ms ✓
- **情境 C（顫抖 → 自主動作 → 顫抖恢復）：失效 ✗**——強自主動作把 WFLC 的
  omega 拖到 3 Hz clamp 下限後**卡死**（WFLC pull-in range 限制），顫抖恢復後
  4 秒 `freqEstimate` 仍停在 3.00–3.16 Hz，永遠回不到帶內 → gate 無法
  re-engage，顫抖段 duty 只剩 43.6%。

獨立的對抗性審查（忠實移植 `eHWFLC_KF_step.m` 的 WFLC 頻率迴圈後實測）
進一步量化了失效機制：

- **捕捉範圍不對稱**：對乾淨的 5 Hz 顫抖（A=15），omega 起始 ≥4.7 Hz 才會鎖上
  5 Hz；起始 ≤4.5 Hz 反而**系統性地被推到 3.0 Hz 地板**。捕捉帶僅約 [4.6, >7] Hz。
- **拖到地板很快**：2 Hz 自主動作 A=5 deg/s 約 7 s、A=15 約 1 s、A=40 約 0.27 s
  就把 omega 釘到地板。
- **回不來**：卡地板後餵 60 秒連續 5 Hz 顫抖，`freqEstimate` 從未達到 4.0 Hz。

實機靜置 `freqEstimate=3.21` 印證 omega 已被拖到過地板。穿戴情境下自主動作
必然先發生，所以「顫抖發作時 freqEstimate 卡在 ~3 Hz」是常態而非邊角——
用它當硬性頻率窗會**在最需要抑震的時刻拒絕作動**（false negative），比現況更糟。

**但估測器的抑震輸出不受影響**（重要）：omega 卡地板時 KF 權重（Q=0.01 相對大）
會快速旋轉補償基底失配，情境 C 兩段顫抖的 `tremorEstimate` 重建相關係數
0.975 vs 0.974、振幅比皆 0.91，幾乎無差。結論：**只有 `freqEstimate` 壞掉**，
內層驅動照用 `tremorEstimate`、估測器一行都不用改。附帶影響：`freqEstimate`
同樣**不可用於 App 端震顫頻率記錄**（digital biomarkers 會被寫入錯的 ~3 Hz），
頻率回報請改用 4–6 Hz 帶通輸出的過零率或短窗 FFT（見 NEXT_STEPS）。

## 4. 建議方案 V2：雙頻帶能量比（已驗證）

對 **raw gyroX**（不是 tremorEstimate）各跑一個 2 階 Butterworth 帶通：

- 顫抖帶 4–6 Hz → envelope `env_t`
- 自主帶 1–3 Hz → envelope `env_v`

三條件 AND + 持續性 hysteresis：

```
ratio = env_t / (env_t + env_v)
啟動：env_t ≥ 6.0 ∧ ratio ≥ 0.55，連續 20 tick（200 ms ≈ 1 個顫抖週期）
維持：env_t ≥ 3.0 ∧ ratio ≥ 0.45；不滿足連續 15 tick（150 ms）才關閉
```

### 驗證結果（合成訊號，fs=100 Hz，seed=0）

| 情境 | V1 freq 窗 | **V2 頻帶比** | 現行韌體 |
|---|---|---|---|
| A 純自主動作誤觸發 | 0.83% | **0.00%** | 89.4% |
| B 顫抖 duty / onset | 98.6% / 210 ms | **97.2% / 420 ms** | — |
| C 自主→顫抖 re-engage | ✗ 永久失效（43.6%） | **610 ms 恢復（89.9%）** | — |
| C 顫抖→自主 釋放 | 210 ms | **250 ms** | — |
| D 顫抖疊加大幅自主 | 不作動 | 不作動（見 §7 限制） | — |

> 這些是**合成訊號設計值**，不可當實測成效引用；`AMP_ON/AMP_OFF` 與病患顫抖
> 振幅、gyro 標度、配戴朝向相關，上板後須實測校調。

## 5. C 程式碼（可直接整合進 main.c）

交付包現已提供可直接加入 CubeIDE 的獨立模組：

- `src/gating/tremor_gate.h`
- `src/gating/tremor_gate.c`
- `test/test_tremor_gate.c`（PC 端基本行為測試）

正式整合請優先使用上述模組；下方程式保留作為設計說明。模組採 instance-based
`TremorGate` 狀態，不依賴 STM32 HAL，也不修改 eHWFLC-KF。每個 100 Hz tick 將同一筆
raw gyro（`double`、°/s）分別送入 `TremorGate_Update()` 與估測器即可。

不動 `eHWFLC_KF_step` 的任何檔案。估測器照跑（`tremorEstimate` 仍决定馬達方向），
gate 只決定「何時允許作動」。**濾波器狀態請保持 `double`**：這兩個窄帶 IIR 的
極點離單位圓很近（|z|≈0.915），float 累積誤差有數值風險；CM7 有雙精度 FPU，
每 tick 多兩個 4 階濾波約僅數百 cycles。

```c
/* ===== Tremor-band gating (V2 雙頻帶能量比) =====
 * 設計依據/驗證: algorithms/handoff/GATING_DESIGN.md
 *   Python: algorithms/validation/gating_check.py  MATLAB: algorithms/matlab/gating_sim.m */
#include <math.h>

#define GATE_AMP_ON     6.0f   /* 啟動 envelope 門檻 (deg/s) — 上板實測校調 */
#define GATE_AMP_OFF    3.0f   /* 關閉 envelope 門檻 (hysteresis) */
#define GATE_RATIO_ON   0.55f  /* 啟動頻帶比門檻 */
#define GATE_RATIO_OFF  0.45f  /* 維持頻帶比門檻 */
#define GATE_ENV_DECAY  0.94f  /* envelope 衰減 (tau≈160 ms @100 Hz) */
#define GATE_N_ON       20     /* 連續 200 ms 才啟動 (≈1 顫抖週期) */
#define GATE_N_OFF      15     /* 連續 150 ms 才關閉 */
#define DRIVE_TH        1.0    /* gate 開啟後, 內層 bang-bang 死區 (取代原 MOTOR_THRESHOLD 判斷) */

/* 2 階 Butterworth 帶通 @ fs=100 Hz (scipy/MATLAB butter 同一組) */
static const double gate_bt[5] = { 0.0036216815149286408, 0.0, -0.0072433630298572816, 0.0, 0.0036216815149286408 };
static const double gate_at[5] = { 1.0, -3.6427871266953296, 5.1461877540722814, -3.3324758952732241, 0.83718165125602273 };
static const double gate_bv[5] = { 0.0036216815149286382, 0.0, -0.0072433630298572764, 0.0, 0.0036216815149286382 };
static const double gate_av[5] = { 1.0, -3.8000503652844575, 5.4393397877934069, -3.4763426471814802, 0.83718165125602251 };

static double   gate_zt[4] = {0}, gate_zv[4] = {0};
volatile float  gate_env_t = 0.0f, gate_env_v = 0.0f, gate_ratio = 0.0f; /* 加進 Live Expressions */
volatile uint8_t motor_enabled = 0;
static uint16_t gate_on_count = 0, gate_off_count = 0;

static double gate_df2t(double x, const double b[5], const double a[5], double z[4])
{
    double y = b[0]*x + z[0];
    z[0] = b[1]*x - a[1]*y + z[1];
    z[1] = b[2]*x - a[2]*y + z[2];
    z[2] = b[3]*x - a[3]*y + z[3];
    z[3] = b[4]*x - a[4]*y;
    return y;
}

/* 每個 100 Hz tick 呼叫一次; raw_gyro = 未濾波的 gyroX (deg/s) */
static uint8_t Gate_Update(double raw_gyro)
{
    float yt = (float)fabs(gate_df2t(raw_gyro, gate_bt, gate_at, gate_zt));
    float yv = (float)fabs(gate_df2t(raw_gyro, gate_bv, gate_av, gate_zv));
    float dt_ = gate_env_t * GATE_ENV_DECAY;
    float dv_ = gate_env_v * GATE_ENV_DECAY;
    gate_env_t = (yt > dt_) ? yt : dt_;
    gate_env_v = (yv > dv_) ? yv : dv_;
    gate_ratio = gate_env_t / (gate_env_t + gate_env_v + 1e-9f);

    if (motor_enabled) {
        uint8_t hold = (gate_env_t >= GATE_AMP_OFF) && (gate_ratio >= GATE_RATIO_OFF);
        if (hold) { gate_off_count = 0; }
        else if (++gate_off_count >= GATE_N_OFF) { motor_enabled = 0; gate_on_count = 0; }
    } else {
        uint8_t trig = (gate_env_t >= GATE_AMP_ON) && (gate_ratio >= GATE_RATIO_ON);
        if (trig) { if (++gate_on_count >= GATE_N_ON) { motor_enabled = 1; gate_off_count = 0; } }
        else { gate_on_count = 0; }
    }
    return motor_enabled;
}
```

`Tremor_Algorithm()` 內的接法（估測器呼叫不變，只改判斷段）：

```c
uint8_t gate = Gate_Update(inputGyro);       /* 用 raw gyro, 在估測器呼叫之後或之前皆可 */

if (!gate) return MOTOR_STOP;                /* gate 關 → 不作動 */

double controlValue = -(MOTOR_GAIN * tremorEstimate);   /* gate 開 → 原本的反向邏輯 */
if (controlValue >  DRIVE_TH) return MOTOR_FORWARD;
if (controlValue < -DRIVE_TH) return MOTOR_REVERSE;
return MOTOR_STOP;
```

兩個小提醒（來自對抗性審查）：

- 內層死區從 5.0 降到 `DRIVE_TH=1.0`，gate 開啟期間 bang-bang 的**切換頻率約增 5 倍**
  （H-bridge/GPIO duty 上升）。這是刻意的——gate 已負責「該不該動」，內層死區只防
  過零抖動；若馬達/驅動級發熱明顯，可把 DRIVE_TH 上調。
- 原 `MOTOR_THRESHOLD` macro 改完後就沒人用了，直接刪除避免誤導。

## 6. 板上驗證步驟

1. Live Expressions 加入 `gate_env_t`、`gate_env_v`、`gate_ratio`、`motor_enabled`。
2. **慢速大幅揮動**（模擬自主動作，~1–2 Hz）：`gate_env_v` 應明顯 > `gate_env_t`、
   `motor_enabled` 維持 0、馬達不轉。
3. **小幅快速抖動**（模擬顫抖，~5 Hz，可用手腕快速左右擺）：`gate_env_t` 上升、
   `ratio` > 0.55、約 0.4–0.6 秒後 `motor_enabled=1`、馬達開始作動。
4. 揮動與抖動交替，確認 gate 能在 ~0.3–0.6 秒內正確切換（對照 §4 延遲表）。
5. 若正常人抖動測不出（振幅不夠），暫時把 `GATE_AMP_ON` 降到 3.0 測邏輯，
   測完改回，並記錄實際手部顫抖的 `gate_env_t` 量級供門檻校調。

## 7. 已知限制與後續

- **顫抖疊加大幅自主動作時不作動**（情境 D）：自主帶能量壓過比值。對 rest tremor
  臨床上可接受（rest tremor 於自主動作時自然衰減），且安全優先（寧可不動，
  不干擾自主動作、守住 ETVM < 10 deg/s）。action/postural tremor 的處理屬
  `gating_classifier.m`（RF 三狀態）後續工作。
- **單軸限制**：目前只餵 gyroX，顫抖投影量隨配戴朝向變化，門檻與朝向相關。
- **bang-bang 未解決「出多少力」**：gate 只管「何時作動」。比例控制（PWM）
  見 NEXT_STEPS。
- 4–6 Hz 帶通對 4 Hz 自主諧波仍有部分響應，靠 ratio 條件壓制（情境 A 已驗證 0%）。

## 8. 設計驗證紀錄

- **模擬驗證**：`algorithms/validation/gating_check.py`（Python，已跑通，本文件所有
  duty/延遲數字出處）與 `algorithms/matlab/gating_sim.m`（MATLAB 鏡像，供組員在
  MATLAB 環境重現與後續調參）。
- **對抗性審查**（獨立第二意見，忠實移植 WFLC 頻率迴圈實測）結論：
  - envelope + hysteresis + 持續性狀態機與 C 實作「設計紮實、無 bug、與 main.c 相容」。
  - **不會 chattering**：任何足以觸發（env ≥ 6.0）的顫抖，半週期低點的 envelope
    仍 ≥ 1.24 × AMP_OFF（最差情況 4 Hz 邊界 3.71 > 3.0），且低谷僅持續 2–4 tick，
    遠低於 N_OFF=15 的連續要求。
  - 取樣相位效應使有效 AMP_ON ≈ 6.07（比標稱高 ~1%），可忽略（門檻本來就要實測校調）。
  - freqEstimate 硬性頻率窗被否決（同 §3），與本文件 V2 結論一致。

## 9. 順帶：韌體其他待修（與 gating 無關但重要）

1. **［阻斷］`main.c` L27-28 用絕對路徑 include**（`C:/Users/banny/...`）——
   其他人機器編譯必失敗。演算法標頭已在專案內 `CM7/Core/Algo/`，改相對路徑
   並把該目錄加進 include path 即可。
2. 建議開 **I-Cache / D-Cache**（`SCB_EnableICache(); SCB_EnableDCache();`），
   `algo_time_us` 預期大幅下降；1440 µs 目前可用，但省下的裕度之後 PID/PWM 會用到。
3. codegen 產出的 C 檔頂端註解宣稱「支援動態 fs_in / 50 Hz 係數」，**實際產物
   fs 寫死 100 Hz**（要改 fs 必須重跑 codegen_arm.m）——別被註解誤導。
4. 若日後切 PLL 提速，TIM6 prescaler 要同步重算（見 §2 注意）。
