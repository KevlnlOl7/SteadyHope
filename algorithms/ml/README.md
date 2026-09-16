# `algorithms/ml/` — 資料驅動的辨識/分類 (Python)

演算法組的**機器學習 / 資料分析**管線(用 Python,符合專案分工:MATLAB 做 DSP、Python 做資料分析)。

| 檔案 | 用途 |
|---|---|
| `severity_rf.py` | 用真實 PD 資料訓練「震顫嚴重度 0-3」Random Forest；含不平衡擴增比較(SMOTE / GAN)與 gating 對應。 |

## `severity_rf.py`

**輸入**:4 個真實 PD 資料集(TIM-Tremor / PdAssist / IMU-Wild / PD-BioStamp),
加速度 `[n,128,3]` @ 50Hz,標籤 0-3(0=無震顫)。約 24,000 視窗。

**流程**:三軸加速度視窗 → 震顫帶頻譜特徵(9 維)→ RF 分類 →(接 `../matlab/control_sim.m` 的)gating。

**實測**(segment-level split 防洩漏;測試集不擴增):

| 擴增 | 平衡acc | 有無震顫(平衡) | 少數類 recall 1/2/3 |
|---|---|---|---|
| 無 | 48.7 | 71.8 | 23/37/37 |
| **SMOTE(推薦)** | **60.2** | **81.1** | **50/52/56** |
| GAN(特徵) | 49.0 | 72.8 | 26/36/37 |

**重點 / 誠實邊界**:
- **不平衡是主要問題**;SMOTE 明顯改善少數類與有無震顫偵測(71.8→81.1%)。
- **特徵空間 GAN 未勝過 SMOTE**——對 9 維特徵向量,SMOTE 是更對的工具。
  GAN 的真正定位是**生成原始震顫訊號(128×3)**(計畫書「模擬病理性震顫非平穩特徵」),
  屬 **raw-signal time-series GAN**,是後半段進階,本檔未實作。
- **感測器/取樣落差**:此資料是**加速度 @50Hz**;裝置抑震用 gyro @100Hz,分類器用
  raw **accel @50Hz**(BNO055 非融合 ACCGYRO 模式,兩流分工)。若之後要跨到 gyro,
  需 domain adaptation(資料集原論文 *Time Series Adaptation Network* 即研究此問題)。
- **DTW-RAM 特徵不適用此資料**(rest/postural tremor,無 RAM 動作);DTW 是給
  RAM 動作辨識那條線用的(見 `../matlab/dtw_features.m`)。

## 資料位置

資料集**未入庫**(大、二進位、非本團隊產生),在專案根目錄的
`Copy/Parkinson-s-Disease-Tremor-Dataset-main/`。`severity_rf.py` 的 `BASE` 預設指向該處;
搬移請改 `BASE`。

## 執行

```bash
pip install numpy scikit-learn torch      # torch 僅 GAN 比較用, 可省
python severity_rf.py
```

## 後半段接續
- raw-signal GAN(生成 128×3 訊號)擴增少數嚴重類。
- accel→gyro domain adaptation / 錄少量 gyro 資料 fine-tune。
- 把定案的 RF 匯出成 STM32 可跑的 C(m2cgen / emlearn 或 MATLAB Coder)。
