# SteadyHope App 事件判定：GitHub 程式核對

核對日期：2026-09-12。

本文件位於 GitHub repository 根目錄下的 `algorithms/handoff/APP_EVENT_REVIEW_20260912.md`。
配套文件：[App FFT／PSD 實作規格](APP_PSD_IMPLEMENTATION.md)、
[震顫頻率與資料規格](TREMOR_FREQUENCY.md)。文件中的 repo 路徑不再加外層 `SteadyHope/`。

文件修訂：2026-09-12，已補給軟體組的轉貼說明、修改順序及驗收清單；並更正前版
將 `motor_on_fraction` 誤寫為 400 筆的描述。**原規格一直是最近 50 筆平均**，
本次不變更為 400 筆。App／硬體程式尚未因本次 MD 修訂而修改。
同日追加：硬體 Gate 的完整規則及 App「資料與判斷方式」文案，見
[APP_PSD_IMPLEMENTATION.md](APP_PSD_IMPLEMENTATION.md) §11。
控制觸發的設計優先序更新為「優先減少需要介入時的漏觸發，容許部分額外觸發」，
評估方法見同文件 §11.4；這是目標補充，未變更現行門檻或宣稱患者效能已驗證。

GitHub repository：`KevlnlOl7/SteadyHope`。App 分支：`fan/import-app-history`。已透過 GitHub branches API 確認本次分支最新提交為 `56805c93c46af81fb922af7780a8841a07258b39`（2026-09-09）。本機 Git object 與遠端 SHA 相同；以下連結固定到該提交。

本次為唯讀靜態程式核對，未修改 App／硬體／後端，也未執行 iOS build 或實機測試。尚未確認使用者手機安裝版本與此提交相同。主分支 `main` 的軟體目錄只有保留檔；App 實作位於上述獨立分支。

## 發布基準與命令旗標語意

本次發布以遠端 `kevin/v2-gating-handoff` 的 `0117ca0a85579f0c5c52b026f40b67c67a84c94b`
為基準，保留其已更新的介面定義。先前本機工作樹較舊，將 `motor_enabled` 解讀為
Gate 的文字不適用於這個遠端版本，這裡一併更正。

- BLE `motor_enabled` 是歷史 wire 名稱，目前代表 `motor_output_active`：完整控制鏈
  成功套用非零馬達命令。它不是原始 Gate，也不證明馬達已移動或抑震有效。
- 規範彙總欄位是 `motor_command_active_fraction`，取最近 50 筆平均。App 原碼的
  `motorOnFraction`／舊文件 `motor_on_fraction` 須與後端明訂映射或版本；不能只改
  一端名稱。以下引用 App 程式時保留原始名稱，便於定位。
- 若要記錄 Gate 升降沿，需獨立 Gate 資料；不能從這個 wire 旗標直接推算。

[韌體 wire 來源：Ryan main.c](https://github.com/KevlnlOl7/SteadyHope/blob/c08bfcca1921fcfdcb5abe6127e3d36cc4e2d65a/firmware/algo/CM7/Core/Src/main.c#L901-L903)

## 主要結論

目前 App 使用的數字是 **0.20／0.30／0.45**，不是 0.20／0.55／0.45。不過三項特徵公式均與本機交付規格不同。更重要的是，`TremorEvent` 的建立條件僅為有效分析資料及超過 3 秒的保存間隔，沒有判定震顫開始、結束或持續時間。因此目前可以解讀成定期保存的分析快照，不能把筆數當成震顫次數。

## 可直接轉貼給軟體組

> 我們核對了 GitHub 的 App 分支 `56805c9`，目前事件是資料有效、距前筆超過 3 秒就保存一筆分析結果，還沒有震顫開始／結束判斷。原交付規格也沒有把事件規則寫完整，這部分需要演算法與軟體一起補齊，先把現有資料當「分析紀錄」，不要用筆數當震顫次數或更新最後震顫時間。
>
> 門檻先維持 0.20／0.30／0.45，請先對齊三個公式：去平均後的三軸整體 RMS、3–7 Hz／0.5–15 Hz 功率占比，以及主峰 ±0.5 Hz 的集中比。上傳保留實際 frequencyReliable；馬達命令比例取最近 50 筆平均，不能用有命令就填 1；規範欄位 motor_command_active_fraction 與 App 舊名的映射也要和後端對齊。
>
> 另外請一起修正 100 Hz 時間軸、斷線通知轉發及 session／buffer 處理。MD 已補上修改順序、程式位置和驗收案例；這次先完成規格對齊，沒有要求硬體跟著調 Gate 門檻，也沒有新增臨床門檻。

> 硬體標準也已補在 APP_PSD_IMPLEMENTATION.md §11：目前核對的 Ryan c08bfcc
> 使用單軸 4–6 Hz 幅度包絡與 1–3 Hz 包絡比較。啟動是包絡 ≥6 deg/s 且比例
> ≥0.55 連續 20 筆；解除是包絡 <3 deg/s 或比例 <0.45 連續 15 筆。這個包絡
> 不是 App 的 RMS，不能把 6 和 0.20 當成同一指標的新舊門檻。
>
> App 趨勢頁請增加「資料與判斷方式」入口，§11.2 有可直接使用的白話文案，
> 詳細頁再列公式、工程門檻及適用版本。motor_enabled 仍只能畫命令作用區段；
> 若需要原始 Gate 起迄，要由硬體提供獨立狀態，不能從馬達旗標反推。
> 說明頁與事件偵測是不同工作，這次並未完成患者事件判定功能。

> 老師補充的控制目標是優先避免需要介入時未啟動，因此不以健康人 Gate 越低
> 越好來決定參數。請在說明中保留「容許日常動作額外觸發」的取捨；資料紀錄
> 仍涵蓋 Gate 關閉時的有效訊號。硬體／演算法後續先檢討會擋掉混合震顫訊號的
> ratio 條件，驗收先看漏觸發、延遲及時段覆蓋。現有數值仍是已核對基準，新的
> 候選需離線比較並驗證；這次不直接改 App 的頻率可信度或硬體門檻。

## 修改順序與完成條件

| 順序 | 負責範圍 | 要修改什麼 | 完成條件 |
|---|---|---|---|
| 1 | App 分析器 | 對齊三個特徵公式及門檻比較策略 | 同一份 CSV 的中間特徵與 Python expected JSON 一致，不只比較顯示頻率 |
| 2 | App 模型／上傳／UI | 保留實際品質旗標、最近 50 筆 Motor 平均；無可靠主頻為 null，無效強度也為 null | 全零有效輸入不會上傳 frequencyReliable=true；50 筆中 1 筆啟動上傳 0.02 |
| 3 | App Bluetooth／session／時間軸 | 狀態確實轉發、分析 buffer 重置、100 Hz 時間、舊資料仍用舊 session | 重連後重新收滿 400 筆；原始／分析時間對齊，沒有 20 ms 備援或跨 session 混批 |
| 4 | App 與演算法規格 | 定期快照先作分析紀錄；獨立定案事件來源、起迄、合併、中斷與時長算法 | 不用有效視窗／保存筆數更新震顫次數或最後震顫時間；事件規則與版本可追溯 |
| 5 | App 說明頁與硬體交付 | 依 APP_PSD_IMPLEMENTATION §11 加說明入口、文案與詳細規則；核對燒錄版本、軸向及 Gate 配置 | 硬體包絡與 App RMS 分開列出；未知版本明示待確認；不以命令旗標冒充 Gate 或患者事件 |
| 介面配合 | App 與後端 | 確認品質缺口、nullable 數值與 session 語意可保存 | 不把未知補成 0／true；若 DTO 要變更，雙端一起驗收 |

上述為待修改／待驗收清單。配套修訂位於 [APP_PSD_IMPLEMENTATION.md](APP_PSD_IMPLEMENTATION.md)
§7、§9.1、§10.2、§12，以及 [TREMOR_FREQUENCY.md](TREMOR_FREQUENCY.md)。
本次沒有執行 Swift 修改或 iOS 測試；三份 MD 在同一個 repo 目錄中，可一起提交。

## 1. 特徵公式與規格不一致

交付基準：[APP_PSD_IMPLEMENTATION.md](APP_PSD_IMPLEMENTATION.md) §7 及
[tremor_frequency_reference.py](../validation/tremor_frequency_reference.py)。這是目前交付規格，不代表已經臨床驗證。

| 項目 | 交付規格 | App 實作 |
|---|---|---|
| `vector_rms` | 三軸各自去平均後，`sqrt(mean(x²+y²+z²))` | 直接使用 4–6 Hz band RMS |
| `tremor_band_fraction` | `P(3–7 Hz) / P(0.5–15 Hz)` | `P(3–7 Hz) / P(0–50 Hz)` |
| `peak_concentration` | 主峰前後 0.5 Hz 功率之和／3–7 Hz 功率 | 單一最高 bin 功率／3–7 Hz 功率 |
| 數值門檻 | 0.20／0.30／0.45 | 同三個數字，各減去 `1e-4` 容差 |

[程式：TremorAnalyzer.swift，第 109–134 行](https://github.com/KevlnlOl7/SteadyHope/blob/56805c93c46af81fb922af7780a8841a07258b39/software/iOS-App/Glove/Algorithms/TremorAnalyzer.swift#L109-L134)

相同數字套在不同特徵上，不會產生等價判斷。應先統一公式及其版本，再討論門檻調整。交付參考版的主峰 ±0.5 Hz 分子目前沒有裁切至 3–7 Hz；若要修正此邊界語意，須同步更新規格與參考程式，不應悄悄更動其中一端。

App 現有雜訊 5 Hz 測試的 `frequencyReliable` 預期為 false，與 Python 交付
fixture 的 true 不同。修正公式時需同步按參考數值更新該測試，保留 CSV 與
測試程式，不要刪掉驗收案例來消除差異。

[App 雜訊案例測試](https://github.com/KevlnlOl7/SteadyHope/blob/56805c93c46af81fb922af7780a8841a07258b39/software/iOS-App/GloveTests/TremorAnalysisTests.swift#L114-L133)

## 2. 事件建立沒有震顫起迄判斷

實際主路徑：

```text
收到分析結果
→ dataValid 為 true
→ 第一次，或距上次保存超過 3 秒
→ 建立 TremorEvent、更新最後震動時間、啟動上傳
```

這段沒有檢查 `frequencyReliable`、RMS 門檻或 Gate；有效但靜置的資料也可走到保存條件。3 秒是保存間隔，不是事件最短持續時間。`TremorEvent` 只有單一 `timestamp`，沒有事件開始、結束、duration 或中斷原因；時間取手機處理當下的 `Date()`。

[程式：DataViewModel.swift，第 463–550 行](https://github.com/KevlnlOl7/SteadyHope/blob/56805c93c46af81fb922af7780a8841a07258b39/software/iOS-App/Glove/ViewModels/DataViewModel.swift#L463-L550)

[模型：TremorEvent.swift](https://github.com/KevlnlOl7/SteadyHope/blob/56805c93c46af81fb922af7780a8841a07258b39/software/iOS-App/Glove/Models/TremorEvent.swift)

若繼續保存這些資料，應將分析快照與震顫事件分開。事件功能仍需定義判斷訊號、開始／結束、合併、中斷與時間歸屬規則；本次沒有憑空指定新的臨床門檻。

## 3. 上傳資料沒有保留真實可信度及馬達比例

`syncEventAsAnalysisRecord()` 將 `frequencyReliable` 固定寫成 `true`。即使分析結果主頻不可靠、上傳頻率為 `nil`，旗標仍為 `true`。

同一路徑將 `motorOnFraction` 寫為 `event.isMotorActive ? 1.0 : 0.0`。而事件建立時的 `isMotorActive` 取最新 50 筆中是否任一筆馬達旗標為 1；這會遺失原規格要求的**最近 50 筆啟動比例**。例如僅 1 筆啟動，應為 1/50=0.02，實作卻會上傳 1.0。

[程式：TremorRepository.swift，第 135–148 行](https://github.com/KevlnlOl7/SteadyHope/blob/56805c93c46af81fb922af7780a8841a07258b39/software/iOS-App/Glove/Repositories/TremorRepository.swift#L135-L148)

[馬達布林值來源：DataViewModel.swift，第 470 行](https://github.com/KevlnlOl7/SteadyHope/blob/56805c93c46af81fb922af7780a8841a07258b39/software/iOS-App/Glove/ViewModels/DataViewModel.swift#L470)

應保存原始品質旗標；Motor 比例依最近 50 筆合法連續旗標取平均。模型內雖另有
`motorOnFraction` 計算屬性，但它以整份 `rawWindowData` 取平均（通常 400 筆），
不符合此欄位的 50 筆契約，不能直接改呼叫該屬性就視為修正。Python 頻譜函式及
BLE reference 並未計算此欄位；其窗口依據是 App 實作規格，而非 Python 回傳值。
此比例描述命令作用時間；不能改稱 Gate 啟動比例。

## 4. 斷線狀態未轉發到分析管線

`BluetoothViewModel` 作為 manager 的 delegate，會把收到的資料轉發給 pipeline，但藍牙狀態與連線變化的回呼只更新 UI，沒有把狀態轉發給 pipeline。Pipeline 自己雖定義斷線／藍牙關閉時的 reset，不能據此認定實際 callback 路徑會執行它。

[程式：BluetoothViewModel.swift，第 232–295 行](https://github.com/KevlnlOl7/SteadyHope/blob/56805c93c46af81fb922af7780a8841a07258b39/software/iOS-App/Glove/ViewModels/BluetoothViewModel.swift#L232-L295)

[管線：TremorPipeline.swift](https://github.com/KevlnlOl7/SteadyHope/blob/56805c93c46af81fb922af7780a8841a07258b39/software/iOS-App/Glove/Services/Bluetooth/TremorPipeline.swift)

應使斷線與重新連線確實觸發窗口及 session 的中斷／重建。既有 Seq／Tick 驗證可能使跨中斷窗口無效，但不等於完整處理了事件與絕對時間軸。

session／anchor 應在資料回呼分派之前建立；首次 raw batch 是 400 筆，之後通常
50 筆，不能假設每次原始資料回呼都固定 50 筆。非同步上傳工作須攜帶該批資料的
session，不能在工作稍後執行時才讀取可能已變更的目前 session。此為跨 session
混用風險，尚未透過實機重現；不要寫成已發生的資料污染。

## 5. 原始資料時間軸存在 50／100 Hz 不一致

Analyzer 設定 100 Hz；DataViewModel 卻仍用 50 Hz 的 `rawSampleInterval = 0.02` 推算 raw 上傳批次基準時間及剩餘緩衝區時間。Repository 的 Tick 回繞備援也使用 `index * 20 ms`。應統一以實際 sample tick 與 session anchor 對齊；不能直接只靠封包抵達時間解釋取樣發生時間。

[時間基準：DataViewModel.swift，第 425–445 行](https://github.com/KevlnlOl7/SteadyHope/blob/56805c93c46af81fb922af7780a8841a07258b39/software/iOS-App/Glove/ViewModels/DataViewModel.swift#L425-L445)

[Tick 回繞：TremorRepository.swift，第 85–96 行](https://github.com/KevlnlOl7/SteadyHope/blob/56805c93c46af81fb922af7780a8841a07258b39/software/iOS-App/Glove/Repositories/TremorRepository.swift#L85-L96)

## 分工建議

- **App 組：**先對齊三項特徵公式、保留品質旗標與窗口比例、修正斷線及時間軸處理；將定期分析快照與事件模型分開，與演算法組定案事件規格。
- **演算法／規格負責人：**補齊事件狀態與中斷規則，清楚區分頻率回報、Gate 控制及患者震顫監測；所有參數標示為目前工程預設。
- **硬體組：**本次 App 查核沒有提供必須調整 Gate 門檻的證據，先維持並核對現有 Seq、Tick、Valid、Motor 欄位語意。若後續事件方案需要額外狀態，另行定義介面。

硬體補充交付：已核對 GitHub `c08bfcc` 使用 Gate 預設，但實際燒錄版本尚未核對；
請提供 build／commit、取樣率、選用軸及配置識別與參數。§11 的說明頁可以先依
參考版本製作，不能在版本未知時宣稱其門檻就是連線裝置的實際配置。

修正這些實作差異能使資料符合既定規格；仍不代表完成患者震顫偵測效能的驗證。
