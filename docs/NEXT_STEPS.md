# SteadyHope 工作規劃（2026-07-09 修訂：雙里程碑版）

> 兩個里程碑是**接力，不是並行**——9 月的 bench 物理證據，正是 1 月 IRB 申請書的
> 可行性背書。9 月證明「手套物理上能抑震」（不需病患），1 月才申請倫理去碰真實病患。
>
> 衡量基準：**9 月＝做出「會抑震的手套」＋ bench 證據**，不是兌現計畫書 100%。
> 誠實降級的項目見文末，照團隊一貫不灌水風格框定即可。

---

## ⚠ 兩個 lead-time 敏感項——這週就要啟動（拖不得，非技術債）

這兩項不是「排幾天就能做完」的工程債，而是**採購/製造前置時間**卡在關鍵路徑上，
晚一週啟動 = 9 月少一週：

- **L1 機構列印 + 組裝**（機構組）：目前只有 3D 設計圖，尚未列印。9 月主證據
  （bench 抑震量測）需要一隻「能戴、線纜拉得動、壓得住抖動」的實體手套，從圖到
  可穿戴實體整條沒開始：列印 PETG 框體 → 裝 STM32/IMU/馬達/電池 → 接線纜牽引 →
  調到能穩定傳力。**這是 M4 的硬前置，且電子端所有工作最終都要在這隻實體上跑。**
- **L2 採購第二顆 IMU**（獨立量測用）：bench 量測必須用一顆
  **不在控制迴路裡**的 IMU 貼在被抑震的手指/手掌端，否則就是拿演算法的殘差自己
  證明自己（球員兼裁判），TPSR 不可信。幾百元、幾天到貨，全隊投報率最高的採購。
  控制端 BNO055 已在 GYROONLY 100 Hz 實測成立，9 月前保留；第二顆可沿用 BNO055，
  若重新採購並重視低 noise、明確 ODR／latency，可評估 ICM-42688-P 或 BMI270 breakout，
  但須先確認電壓、介面、driver 成熟度與交期，不把換 sensor 併入控制主線。
  掛法兩選項：(A) 由 STM32H745 目前閒置的 **M4 核心**讀（給獨立 I2C 匯流排、
  CubeMX 把該周邊分配給 CM4），用上雙核架構；(B) 完全獨立的擷取系統（另一顆
  MCU 或直接接電腦），量測工具與受測系統物理隔離、不動現有韌體。**關鍵不在掛哪，
  而在第二顆 IMU 的資料絕不能經過抑震演算法**——要 raw、獨立算功率/振幅。
  9 月純驗證用途建議 (B) 較省事；想展現雙核運用則 (A) 加分。

═══════════════════════════════════════════════════════════════
## 里程碑 1：9 月專題發表 —— 交付「會抑震的手套」＋ bench 證據
═══════════════════════════════════════════════════════════════

**驗收標準**：在 bench 上證明手套能抑震（機械振動源 / 健康受試者，**不需病患**）。

### 主線（must-have，按依賴序）

| # | 事項 | 負責 | 預估 | 說明 |
|---|---|---|---|---|
| M1 | ✅ CubeIDE target portable integration | 硬體組 | 已完成（待上板） | `firmware/algo` 已移除個人絕對路徑，整合 canonical CM7 + idle CM4，並提供 static validator 與四組 headless build；仍缺 dual-core flash/board evidence。 |
| M2 | V2 gating 上板測資比對 | 硬體組＋演算法組 | 0.5–1 天 | Target source/compile 已整合；下一步保持 VM 斷開，燒錄 CM7+CM4，跑 committed boundary vectors 逐筆比對。慢揮/快抖只能作補充觀察，不能以「馬達有轉」當 gate 驗收。 |
| M3 | **N20 loaded bandwidth test → PWM/P control** | 硬體組＋演算法組 | 數天–1.5 週 | ★ 先補齊 N20 型號、gear ratio、供電、H-bridge、spool/線纜規格；裝實際負載測 4/5/6 Hz gain、phase、延遲、backlash、電流與溫升。通過才調 PWM/P gain；失敗先換 actuator/transmission。`control_sim.m` 目前是 P-only，實測 plant 前不直接加 Ki/Kd。詳見 `algorithms/handoff/ACTUATOR_CONTROL.md`。 |
| M4 | **bench 抑震量測 protocol + 執行** | 演算法組＋機構組 | 1–2 週 | ★**9 月主證據**。見下方「量測 protocol」。前置：L1 實體手套、L2 第二顆 IMU。 |
| M5 | 機構手套實體（承 L1） | 機構組 | 持續 | 列印→組裝→線纜牽引可動→調校。9 月 demo 硬體本體，關鍵路徑。 |
| M6 | 建 integration 分支 + 鎖 BLE 封包格式 | 全隊 | 本週起 | main 凍結三個月、5 分支零 merge，需終結孤島開發；先鎖韌體↔App 最小欄位契約。 |

### 加分（nice-to-have）

| # | 事項 | 負責 | 說明 |
|---|---|---|---|
| M7 | device→App 最小資料流 | 硬體＋軟體組 | 單向上傳一個數字、畫一條即時波形線，展示醫病資料橋雛形。 |
| M8 | 開 I/D cache | 硬體組 | `SCB_EnableICache/DCache()` 後重量 `algo_time_us`（現 1440 µs @ HSI 64 MHz，預期大降），回收裕度給 PWM/PID。 |
| M9 | Ryan 本地 debug 版 main.c 入庫 | 硬體組 | 截圖韌體含 `tim6_irq_count` 等儀器、比 branch 新，先入庫保留回退點。 |

### M3 actuator/PWM 驗收門檻

- 「N20」不是完整型號；PWM 調參前必須記錄額定／供電電壓、gear ratio、空載 rpm、
  continuous torque、stall current、encoder、H-bridge current rating、spool 半徑與線纜預張力。
- loaded test 必須包含實際 spool、線纜與代表性手套負載，不接受只測空載 rpm／stall torque。
- 4–6 Hz 要能穩定換向，無 missed reversal／明顯 cable slack，gain/phase 可重複，且不超過
  continuous current／temperature。`≤15 ms` 是現有模擬設計目標，須量測後回填模型，
  不是 N20 已達成的規格。
- 控制第一版為 `gate → command=-tremor_est → P gain → saturation → PWM/H-bridge`；
  sensor timeout、gate off 或 driver fault 時 CCR 必須立即歸零。PWM carrier 與 100 Hz control
  update 是兩個不同頻率。
- 若 actuator 物理頻寬不足，停止堆 PID；優先評估低減速比、帶 encoder 的 coreless DC，
  第二代再考慮 voice-coil 或低減速比 BLDC/direct drive。

### 9 月 bench 抑震量測 protocol（M4 細節）

**抖動源**（兩者搭配）：
- 黃金對照（算數字用）：健康受試者手上綁**小振動器/偏心馬達**（頻率振幅固定，4–6 Hz）。
  外部強制振動源可重複 → 開/關兩次抖動一致 → TPSR 才可信。純自主裝抖每次不一樣，
  無法算嚴謹 TPSR。
- 說服力展示（demo 用）：受試者純自主裝抖，現場給看「揮手不壓、抖動才壓」，只當趨勢。

**量測點**：用 L2 的第二顆 IMU（不在控制迴路裡）貼手指/手掌端量殘餘抖動。
控制迴路那顆（手腕上方）不能兼任驗證器。

**條件對照**（各重複 N 次取平均 ± 標準差）：
- A 抖動源開、手套關 → `P_before`
- B 抖動源開、手套開 → `P_after` → **TPSR =(1 − P_after/P_before)×100%**
- C 無抖動、受試者自主動作、手套開 → 驗證 gating 不誤觸發、不干擾（＝ ETVM）

**產出**：TPSR ± 標準差、抑震前後波形圖、頻譜對照圖。
**引用時分清**：合成訊號 RMSE ≠ 真實病患 ETVM；bench 健康受試者 ≠ 臨床病患成效。

═══════════════════════════════════════════════════════════════
## 里程碑 2：2027 年 1 月 大專生計畫 —— IRB 倫理申請
═══════════════════════════════════════════════════════════════

**驗收標準**：完成計畫申請書 + 倫理審查送件。

| # | 事項 | 說明 |
|---|---|---|
| I1 | IRB 申請書 | 受試者招募、知情同意、風險評估、資料保護。 |
| I2 | 真實 PD 病患資料收集規劃 | ← 要申請倫理才能碰病患的東西，這才是 IRB 的核心，**不屬 9 月**。 |
| I3 | DTW+RF+GAN 方法章節 | 以 9 月 bench 成果 + 現有離線骨架（`gating_classifier.m`/`severity_rf.py`）當可行性佐證。 |
| I4 | 9 月 bench 數據 → 申請書 preliminary data | 兩里程碑的接力點：9 月的物理證據撐 1 月的申請說服力。 |

═══════════════════════════════════════════════════════════════
## 誠實降級（計畫書寫了，但按里程碑框定，不在 9 月現場 claim）
═══════════════════════════════════════════════════════════════

- **辨識 F1 85%+** → 1 月申請書的「方法/預期」，9 月不 claim。repo 現無 F1 指標、
  無真實 RAM 資料、GAN 未勝 SMOTE、唯一真實資料 RF 是不同任務（嚴重度 0–3）。
- **DTW/RF 上板** → 標「規劃中」。骨架打通可講，不承諾上板（即時化 + m2cgen/emlearn
  部署鏈未建，8 週不現實）。
- **完整 biomarker 回診系統** → 9 月最小 demo（M7），完整版屬 IRB 通過後。
  頻率來源用 4–6 Hz 帶通過零率或短窗 FFT，**freqEstimate 不可用**（見下）。
- **真實病患資料** → 里程碑 2（9 月用機械源 + 健康受試者）。
- **單軸 gyroX 抑震** vs 60% 降震幅：屬設計層限制（`gy=gz=0` 寫死），真實多軸顫抖
  抑震比可能被低估。必要時計畫書用「主導軸抑震」重新框定，別讓核心 claim 最後跳票。

═══════════════════════════════════════════════════════════════
## 跨里程碑保留項（承前版）
═══════════════════════════════════════════════════════════════

- **freqEstimate 禁用**：會被自主動作拖到 ~3 Hz clamp 卡死（GATING_DESIGN.md §3），
  不可用於 gating、不可寫進 App `tremorFrequency`。`tremorEstimate` 不受影響照用。
- **FFT 頻率放後端**：原始樣本上傳後，後端每 2–4 秒視窗做 FFT/Welch 找 3–8 Hz 峰值
  （符合「邊緣即時、雲端分析」分層）；韌體端要本機顯示可用 gating 4–6 Hz 帶通的
  過零率（約 5 行，只在 gate 開時讀）。
- **Repo 衛生**：(a) `hardware/mechanical/stl/algo|motor1`、`hardware/bno055` 搬到
  `firmware/`；(b) .gitignore 排除 HAL/CMSIS vendor 樹（各 ~19 萬行）；(c) commit type
  與內容對齊（fd3f173 標 docs 實為 feat）。
- **BMFLC 實機對照**：目前只有 eHWFLC-KF 上線，BMFLC 已 include 未呼叫；兩者實機
  TPSR 對照是答辯素材。
- **CLAUDE.md 已更新**（2026-07-09）：low-pass→帶通、GYROONLY 100 Hz、freqEstimate
  警告、雙標籤空間、目錄結構。codegen 註解宣稱動態 fs_in 但實際寫死 100 Hz。
