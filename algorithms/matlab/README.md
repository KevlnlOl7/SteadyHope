# `algorithms/matlab/` — 演算法 MATLAB 原始碼（source of truth）

顫抖抑制演算法的**權威 MATLAB 原始碼**。C 交付物由這裡 codegen 產生。

> 這裡的 `*_step.m` 是**帶通版**（前處理 = 2–20 Hz 帶通）。這是經合成訊號效能比較後
> 選定的部署版本——對自主動作穩健。低通-相減版（原 `Copy - Claude Ver/`）在有明顯自主
> 動作時會把 <2 Hz 動作 leak 進估測，已不採用。詳見 [../../docs](../../docs) 的濾波器選擇說明（若已建立）。

## 檔案

| 檔案 | 用途 |
|---|---|
| `BMFLC_step.m` / `eHWFLC_KF_step.m` | **即時單樣本版**（codegen 目標）。fs 預設 100 Hz。 |
| `BMFLC.m` / `eHWFLC_KF.m` | 離線完整版（向量輸入），供 `main_simulation.m` 比較用。 |
| `main_simulation.m` | 合成訊號驗證：跑兩演算法、算 RMSE / 功率降低、繪圖。 |
| `plot_results.m` | 繪圖輔助。 |
| `quick_test_step.m` | 快速跑一下 step 版。 |
| `test_simulated_tremor.m` / `test_patient_tremor.m` | 額外測試腳本。 |
| `utils/` | `generate_synthetic_tremor.m`、`compute_tremor_power.m`、`butter_lowpass.m`。 |
| **`codegen_arm.m`** | ★ 一鍵：以 ARM 為目標重產生 C，並覆蓋到 `../handoff/src/`。 |
| **`control_sim.m`** | 抑震「控制律」閉迴路模擬：PID / 半主動阻尼 / 延遲敏感度（TPSR、ETVM + 圖）。plant 為標稱值，待硬體實測校調。 |
| **`dtw_features.m`** | DTW 動作偏離特徵擷取（辨識/gating 用）：RAM 軌跡 vs 健康模板 → DTW 距離。驗證速度不變性與嚴重度可分。需 Signal Processing Toolbox。 |
| **`gating_classifier.m`** | 辨識→gating 骨架：特徵(DTW+震顫帶)→ Random Forest 判定狀態 → 選 PID 模式。合成資料驗證(~94%)，後半段接真實 RAM + GAN。需 Statistics and ML Toolbox。 |
| **`gating_sim.m`** | 馬達 gating（何時作動）驗證：V1 freqEstimate 頻率窗 vs V2 雙頻帶能量比。V1 被情境 C 實證推翻（omega 卡 clamp 地板），V2 為建議方案。與 `../validation/gating_check.py` 逐行對應。需 Signal Processing Toolbox。 |

## 產生 STM32 用的 C（給韌體組）

```
在本資料夾開 MATLAB → 執行 codegen_arm.m
     → 自動輸出到 ../handoff/src/{bmflc,ehwflc}
     → 跑 ../handoff/test/build_and_run.sh 確認 ALL PASS
```

`codegen_arm.m` 已內含 ARM-safe 設定（關 SIMD、fs=100）。細節見 [../handoff/README.md](../handoff/README.md) §4。

## 沒有搬過來的東西（仍在專案根目錄的 `Copy/`）

- **Simulink 模型** `tremor_suppression_sim.slx` 與 `slprj/`（二進位、路徑敏感）。
- **真實資料實驗** `real_data_exp/` 與 `Parkinson-s-Disease-Tremor-Dataset-main/`（資料集很大、路徑相依）。
- 這些要用時仍回 `Copy/` 跑；本資料夾專注在「產生與驗證交付 C」所需的最小集合。
