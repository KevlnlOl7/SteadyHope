# `src/` — 演算法 C 原始碼（MATLAB Coder 產生，ARM-safe）

兩個演算法的 C 實作，給 STM32 韌體直接編譯：

```
src/
├── bmflc/     BMFLC（38-weight NLMS）
└── ehwflc/    eHWFLC-KF（6-state Kalman）
```

每個資料夾自含 `rtwtypes.h`（型別定義，無外部相依）。

## 狀態：已是 ARM-safe，且與模型逐點等價

- 以 **ARM Cortex-M 為目標、關閉 SIMD** 重新產生（見 [../README.md](../README.md) §4 /
  `../../matlab/codegen_arm.m`）→ **無 x86 SSE2（無 `<emmintrin.h>`/`__m128d`）**，
  純 scalar，可直接在 STM32 上編譯。
- 跑 `../test/build_and_run.sh` 對 golden 為 **`max|err| = 0`（逐位元等於 MATLAB 模型）**。
- `fs` 寫死 **100 Hz**（`dt`、帶通係數）；前處理為 **2–20 Hz 帶通**。

> 要重新產生（改參數/改 fs）：在 `../../matlab/` 執行 `codegen_arm.m`，它會自動覆蓋這裡並自檢。

## 介面（完整契約見 [../README.md](../README.md)）

```c
/* bmflc/BMFLC_step.h */
double BMFLC_step(double signal_sample);   /* 回傳 tremor_est (°/s) */
void   BMFLC_step_init(void);              /* 重置狀態（可選；首次呼叫會自動 init） */

/* ehwflc/eHWFLC_KF_step.h */
void eHWFLC_KF_step(double signal_sample, double *tremor_est, double *freq_hz);
void eHWFLC_KF_step_init(void);
```

- **輸入** `signal_sample`：單軸**陀螺儀角速度，單位 °/s**（不是加速度）。
- **取樣率**：**寫死 fs = 100 Hz**。改取樣率必須重產生，不能只改韌體餵入頻率。
- **狀態**：file-scope `static` → **單例**，只能跑一軸。多軸需多份實例或 reentrant 重產生。
- 全程 `double`；H745 Cortex-M7 有 DP FPU，OK。無動態配置（無 malloc）。

## 編譯所需檔案（每個演算法）

- BMFLC：`BMFLC_step.c` + `BMFLC_step_data.c` + `BMFLC_step_initialize.c`（+ headers）
- eHWFLC：`eHWFLC_KF_step.c` + `eHWFLC_KF_step_data.c` + `eHWFLC_KF_step_initialize.c` + `eye.c`（+ headers）
- `_terminate.c` 僅作收尾，ISR 流程用不到，可不連結。
- include path 需含 `bmflc/`、`ehwflc/`。

> 型別備註：目前 Coder 產生的 `rtwtypes.h` 為自含，不需 `tmwtypes.h`。若換 MATLAB 版本
> 重產生後 `rtwtypes.h` 又去 `#include "tmwtypes.h"`，補回 MATLAB 內附的 `tmwtypes.h`
> （或在 Coder 設定產自含型別）即可。
