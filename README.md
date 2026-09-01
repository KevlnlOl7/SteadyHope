# 🧤 SteadyHope - 帕金森氏症避震手套專案

![Project Status](https://img.shields.io/badge/Status-Developing-blue)
![Platform](https://img.shields.io/badge/Platform-STM32%20%7C%20Python-green)

## 📌 專案簡介
SteadyHope 是穿戴式顫抖抑制裝置的畢業專題原型，目標是以 IMU、估測演算法與主動
致動器降低 4–6 Hz 手部顫抖。目前 repo 已有 STM32H745I-DISCO 雙核心 target 專案與
motor-off／ForceSafe 控制鏈，但尚未完成燒錄、馬達台架或人體成效驗證，不能把開發版
描述成醫療產品或已證實可抑震。

> 馬達整合入口：[`firmware/algo/README.md`](firmware/algo/README.md)。`D2`–`D7` 是
> STM32H745I-DISCO 的 Arduino header label，不是 GPIO 名稱；真正接腳與目前安全鎖請以
> 該文件及 `.ioc` 為準。現在的 canonical build 刻意保持 `STBY=LOW`、`CCR=0`。


---
## 📂 專案架構 (Project Structure)
為了避免開發衝突，請組員將程式碼放置於對應的資料夾：

```
SteadyHope/
├── firmware/algo/                 # STM32H745I-DISCO CubeIDE CM7/CM4 target
│   ├── CM7/Core/Src/main.c        # 100 Hz pipeline、TIM1 PWM、GPIO/encoder glue
│   ├── CM4/Core/Src/main.c        # 雙核心 handshake，之後 idle
│   ├── algo.ioc                   # target MCU、clock、D2–D7 pin mapping
│   ├── build_headless.ps1         # CM7/CM4 Debug/Release 可重現建置
│   └── README.md                  # 接腳、build、燒錄與安全狀態（先讀）
├── algorithms/
│   ├── matlab/                    # BMFLC/eHWFLC-KF source of truth + codegen
│   ├── handoff/src/control/       # SuppressionControl 與 command mapper
│   ├── handoff/src/actuator/      # encoder、position guard、TB6612 driver
│   ├── handoff/stm32_motor_control_20260823/
│   │   └── src/actuator/          # STM32 TB6612 HAL adapter
│   └── validation/                # Python/static/cross-language validators
├── software/                      # SwiftUI iOS App + Vapor/PostgreSQL backend
├── hardware/                      # 機構、電路與歷史韌體資料
├── docs/                          # 專案規劃、協定與報告
└── README.md
```

---
## STM32 韌體驗證

在 repo 根目錄依序執行：

```powershell
python .\algorithms\validation\validate_stm32_motor_main.py `
  --main .\firmware\algo\CM7\Core\Src\main.c --skip-shadow
python .\algorithms\validation\validate_cubeide_motor_integration.py
.\algorithms\handoff\test\run_actuator_tests.bat
powershell -ExecutionPolicy Bypass -File .\firmware\algo\build_headless.ps1
```

最後一個腳本會 clean-build CM7/CM4 的 Debug 與 Release。這些 PASS 只代表 static、host
與 target compile/link；燒錄、scope、encoder、馬達負載及抑震成效必須另外留下實板證據。

---
## 團隊組成 (Team Members)
| 學號 | 中文姓名 | 英文姓名 | 負責項目|
| :--- | :--- | :--- | :--- |
| 412630153 | 張傢寧 | Kevin | 專案負責人、演算法 |
| 412631508 | 許方彥 | Ian |  | 機構設計 (3D 列印)、電路整合
| 412630781 | 陳韋恩 | Wilson | Oracle Cloud 部署 |
| 412631532 | 樊柔妤 | Fan | iOS App 開發 (Swift)、UI/UX 設計 |
| 412631474 | 范瑋哲 | Ryan |  |
| 412630906 | 李冠廷 | Eric |  | 

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
* `feat`: 新增功能 (例如：`feat: 加入 BNO055 讀取功能`)
* `fix`: 修復錯誤 (例如：`fix: 修正濾波器參數偏差`)
* `docs`: 修改文件 (例如：`docs: 更新 README 開發流程`)
* `cad`: 3D 模型更新 (例如：`cad: 手套掌心殼體 v2`)
* `refactor`: 重構程式碼 (不影響功能的結構調整)

### 3. 保持同步 (Sync)
* **先 Pull 再開發：** 每次開始工作前，請務必先執行 `git pull origin main` 同步最新進度。
* **解決衝突：** 若合併時發生 Conflict，請主動聯繫相關組員共同討論保留的版本。

---

## 🛠️ 環境配置
* **Hardware:** STM32, BNO055, 震動致動器。
* **Firmware:** STM32CubeIDE、MATLAB。
* **Software:** Python 3.x (數據分析), Swift (App)。

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
