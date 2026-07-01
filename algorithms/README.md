# `algorithms/` — 顫抖抑制演算法（演算法組地盤）

從 MATLAB 原始碼、到產生給 STM32 的 C、到交給韌體組的交付包，都在這裡。

```
algorithms/
├── matlab/     權威 MATLAB 原始碼（估測 / 控制 / DTW）+ 一鍵 codegen 腳本
├── ml/         Python 資料分析：真實 PD 資料的嚴重度 Random Forest（+ 不平衡擴增）
└── handoff/    交給 STM32 韌體組的交付包（C + 介面契約 + golden 測試 + 整合教學）
```

## 資料流

```
matlab/*.m  ──(codegen_arm.m, ARM 目標)──▶  handoff/src/*.c
                                                  │
                     handoff/test 等價性測試(對 golden) ✔
                                                  │
                                                  ▼
                               firmware/ (STM32 組把 handoff/src 拉進去)
```

- **演算法組（你）**：在 `matlab/` 改演算法、跑 `codegen_arm.m` 產生 C、確認 `handoff/test` PASS。
- **STM32 組**：從 `handoff/` 拿 C 與文件，照 `handoff/INTEGRATION.md` 接進 `../firmware/`。

## 版本 / 設計決定

- 部署版本 = **帶通版**（`*_step.m` 前處理為 2–20 Hz 帶通）。經合成訊號效能比較選定，
  對自主動作穩健；低通-相減版已淘汰（有自主動作時會 leak <2 Hz 動作進估測）。
- 取樣率 = **100 Hz**（讀 BNO055 raw gyro，見 `handoff/BNO055_GYRO_SETUP.md`）。

## 與根目錄 `Copy/` 的關係

- `Copy/` 是**早期臨時工作區**（含 Simulink、資料集、`Copy - Claude Ver/` 等），現退為
  **暫存 / 歷史**。權威 `.m` 已複製進 `matlab/`。
- 大型 / 二進位 / 路徑相依的東西（`.slx`、資料集、`real_data_exp/`）暫留 `Copy/`。
