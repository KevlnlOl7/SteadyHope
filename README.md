# 🧤 SteadyHope - 帕金森氏症避震手套專案

![Project Status](https://img.shields.io/badge/Status-Developing-blue)
![Platform](https://img.shields.io/badge/Platform-STM32%20%7C%20Python-green)

## 📌 專案簡介
SteadyHope 是一款專為帕金森氏症患者設計的智慧型避震手套。透過感測器捕捉手部震顫頻率，並利用演算法控制致動器產生補償力量，藉此減緩手部抖動，協助患者重拾日常生活品質。

---

## 📂 專案架構 (Project Structure)
為了避免開發衝突，請組員將程式碼放置於對應的資料夾：

SteadyHope/
├── firmware/                # 【嵌入式系統】ESP32 核心程式
│   ├── src/                 # 原始碼 (.cpp, .ino)
│   │   ├── main.cpp         # 程式入口與多執行緒排程
│   │   ├── IMU_Handler.cpp  # MPU6050 數據讀取與校準
│   │   └── Motor_Control.cpp# PWM 致動器控制邏輯
│   ├── lib/                 # 第三方或自定義函式庫 (如 KalmanFilter)
│   └── include/             # 標頭檔 (定義引腳、PID 參數常數)
├── software/                # 【軟體系統】iOS 與 雲端後端
│   ├── iOS-App/             # Swift 原生開發應用程式
│   │   ├── SteadyHope/      
│   │   │   ├── Models/      # 數據模型 (患者資訊、震顫紀錄)
│   │   │   ├── ViewModels/  # MVVM 邏輯層 (處理 BLE 通訊與 API 請求)
│   │   │   ├── Views/       # SwiftUI 介面 (Dashboard, Setting)
│   │   │   └── Services/    # 核心服務 (NetworkManager, BluetoothManager)
│   │   └── SteadyHope.xcodeproj
│   └── backend/             # Oracle Cloud (OCI) 伺服器端
│       ├── src/             # API 邏輯 (Node.js/Express 或 Python/FastAPI)
│       ├── db/              # Oracle DB Schema 與 SQL 腳本
│       ├── Dockerfile       # 容器化部署設定
│       └── .env.example     # 環境變數範本 (防止密碼外洩)
├── algorithms/              # 【演算法】研究與數據模擬
│   ├── datasets/            # 震顫測試原始數據 (CSV/JSON)
│   ├── notebooks/           # Jupyter Notebooks (演算法驗證與圖表)
│   └── filter_logic/        # 核心濾波演算法實作
├── hardware/                # 【硬體設計】機構與電路
│   ├── mechanical/          # 3D 列印相關
│   │   ├── stl/             # 最終輸出列印檔 (預覽用)
│   │   └── source/          # 原始設計檔 (Fusion 360 / SolidWorks)
│   └── circuits/            # 電路設計
│       ├── schematics/      # 電路圖 (PDF/KiCad)
│       └── bom/             # 材料清單 (Bill of Materials)
├── docs/                    # 【專案文件】
│   ├── api_spec.md          # RESTful API 規範說明
│   ├── ble_protocol.md      # 藍牙封包傳輸協議定義
│   └── reports/             # 畢業專題進度報告與補助申請書
├── .gitignore               # 排除 Xcode 暫存檔、OS 系統檔、環境變數
└── README.md                # 專案總入口文件

---

## 🤝 開發規範 (Contribution Guide)
為了確保程式碼整潔並避免檔案衝突，請組員遵守以下規範：

### 1. 分支管理 (Branching)
* **禁止直接 Push 到 `main` 分支。**
* **分支命名格式：** `個人名字/功能描述`
  * 範例：`kevin/imu-filter` 或 `wilson/glove-cad-v2`
  * 指令：`git checkout -b 名字/功能名稱`
* **合併流程：** 功能開發完成並測試無誤後，請發起 **Pull Request (PR)**，由負責人進行合併。

### 2. 提交紀錄 (Commit Message)
請使用簡單明確的標籤開頭，方便追蹤進度：
* `feat`: 新增功能 (例如：`feat: 加入 MPU6050 讀取功能`)
* `fix`: 修復錯誤 (例如：`fix: 修正濾波器參數偏差`)
* `docs`: 修改文件 (例如：`docs: 更新 README 開發流程`)
* `cad`: 3D 模型更新 (例如：`cad: 手套掌心殼體 v2`)
* `refactor`: 重構程式碼 (不影響功能的結構調整)

### 3. 保持同步 (Sync)
* **先 Pull 再開發：** 每次開始工作前，請務必先執行 `git pull origin main` 同步最新進度。
* **解決衝突：** 若合併時發生 Conflict，請主動聯繫相關組員共同討論保留的版本。

---

## 🛠️ 環境配置
* **Hardware:** ESP32, MPU6050, 震動致動器。
* **Firmware:** Arduino IDE / PlatformIO。
* **Software:** Python 3.x (數據分析), Flutter (App)。

---

## 📅 目前進度與待辦事項
- [x] 專案初期構想與技術選型
- [ ] 3D 手套原型設計 (v1)
- [ ] 震顫感測數據採集與分析
- [ ] 即時補償演算法優化
- [ ] 畢業專題補助申請提交

---

## ✉️ 聯絡資訊
如果有任何技術問題或檔案衝突，請直接在討論群組提出。

**SteadyHope Team @ 淡江大學 資訊管理學系**