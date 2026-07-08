# SteadyHope 工作規劃（2026-07-09 更新）

> 背景：韌體組已完成第一次「感測 → 估測 → 致動」實機串接（`Ryan/stm32-motor-control`
> 的 algo 專案，eHWFLC-KF 上線，100 Hz 迴路 8 分鐘無掉拍、無 I2C 錯誤），
> 但「IMU 一動馬達就轉」——gating 設計與驗證見
> [`algorithms/handoff/GATING_DESIGN.md`](../algorithms/handoff/GATING_DESIGN.md)。
> 距 9 月專題發表約 8 週。

## 第一優先：本週（韌體閉迴路品質）

| # | 事項 | 負責 | 預估 | 說明 |
|---|---|---|---|---|
| 1 | **修 main.c 絕對路徑 include**（阻斷項） | 硬體組 | 10 分鐘 | L27-28 指向 `C:/Users/banny/...`，其他人無法編譯。演算法標頭已在 `CM7/Core/Algo/`，改相對路徑 + include path。 |
| 2 | **實作 V2 gating（只在病徵頻率作動）** | 硬體組＋演算法組支援 | 0.5–1 天 | 照 GATING_DESIGN.md §5 貼 C、§6 板上驗證。合成訊號已驗證：自主動作誤觸發 89% → 0%。 |
| 3 | **實測取樣率**：確認真 100 Hz 且樣本不重複 | 硬體組 | 半天 | 連續樣本 diff==0 的比例應 ≈0；或 GPIO toggle 量 tick。這是所有演算法數字成立的前提（交接包 fs 寫死 100 Hz）。 |
| 4 | **開 I-Cache / D-Cache** | 硬體組 | 半天 | `SCB_EnableICache(); SCB_EnableDCache();` 後量 `algo_time_us`（現 1440 µs @ HSI 64 MHz，預期大幅下降）。注意 DMA 一致性目前不影響（I2C 讀取是 blocking）。 |
| 5 | Ryan 把含 debug counters 的本地版 main.c commit 上來 | 硬體組 | — | 截圖韌體比 branch 上的新（多了 `tim6_irq_count` 等儀器），先入庫再改 gating，保留可回退點。 |

## 近期：2–3 週

| # | 事項 | 負責 | 說明 |
|---|---|---|---|
| 6 | MATLAB 跑 `gating_sim.m` 重現 + 參數校調 | 演算法組 | 本機無 MATLAB 未實跑，先重現再用真人 bench 資料掃 `AMP_ON/OFF`（與配戴朝向、gyro 標度相關）。 |
| 7 | bang-bang → PWM 比例控制 | 硬體組＋演算法組 | 原 roadmap 既定項。接 `control_sim.m` 的 PID/半主動阻尼參數；gate 決定「何時」，PWM 解決「多少力」。 |
| 8 | 桌上 TPSR/ETVM 量測 protocol | 演算法組＋機構組 | 2 Hz 大幅（自主）vs 5 Hz 小幅（顫抖）標準動作，量閉迴路實機 TPSR 對照理論基準線 66.8%。**引用數字時分清：合成訊號 RMSE ≠ 真實病患 ETVM**。 |
| 9 | **App 震顫頻率欄位改用穩健頻率** | 軟體組＋演算法組 | `freqEstimate` 會被自主動作拖到 ~3 Hz 卡死（GATING_DESIGN.md §3），**不可直接寫進 `tremor_data.tremorFrequency`**（digital biomarkers 會記錄錯的頻率）。改用 4–6 Hz 帶通輸出的過零率或短窗 FFT。 |
| 10 | Repo 衛生 | 全組 | (a) `hardware/mechanical/stl/algo|motor1`、`hardware/bno055` 搬到 `firmware/` 樹下；(b) .gitignore 排除 HAL/CMSIS vendor 樹（各 ~19 萬行）；(c) commit type 與內容對齊（fd3f173 標 docs 實為 feat）。 |

## 中期：暑假（對齊系統文件 §5.2.13 / §6.2）

- **BMFLC 路徑接上實機**：目前只有 eHWFLC-KF 上線，BMFLC 已 include 未呼叫。
  兩演算法實機 TPSR 對照是答辯的好素材。
- **eHWFLC-KF 效能餘裕**：1440 µs 已知成因（64 MHz + double + cache），開 cache
  後重量測；若要上 PLL 記得同步改 TIM6 prescaler（GATING_DESIGN.md §2）。
- **DTW + gating_classifier 真實資料重訓**：處理 action/postural tremor
  （顫抖疊加自主動作時 V2 gating 不作動的已知限制）。
- **freqEstimate 修復（若需要）**：omega re-seed 機制或 BMFLC 權重頻譜法。
  目前抑震與 gating 都不依賴它，優先級低；但 App 頻率回報（#9）先繞開。
- Simulink Embedded Coder 流程、GAN 資料增強 + RF 動作分類（既定 roadmap）。

## 提醒（既有文件的已知過時處）

- `CLAUDE.md` 的「eHWFLC-KF 仍保留 low-pass filter」與現行交接包（兩演算法統一
  2–20 Hz 帶通，見 `algorithms/matlab/README.md` 開頭）不一致——**待 Kevin 確認後更新**，
  避免後人誤判。
- codegen 產出 C 檔頂端註解宣稱支援動態 fs_in，實際 fs 寫死 100 Hz。
- 「BNO055 有效取樣率約 37 Hz」是 NDOF 模式的舊觀測；GYROONLY 遷移後實機
  counters 顯示 100 Hz 管線成立（待 #3 正式量測後更新 CLAUDE.md）。
