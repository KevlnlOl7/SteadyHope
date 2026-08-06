# STM32 V2 gating延伸測試交接

日期：2026-08-06

這份文件把PC離線強健性模擬轉成可執行的板上工作。務必區分：演算法組已完成測試
資料、C/reference與預期結果，不等於STM32、馬達或人體測試已完成。

## 1. 目前狀態

| 測試 | 演算法端交付 | STM32尚需完成 |
|---|---|---|
| 7 Hz／10、15、20 deg/s | 三組CSV、C header、逐筆golden、C測試均完成 | 注入三組並回傳逐筆log |
| 1～8 Hz × 2～20 deg/s | 56組單一CSV、C header、逐筆golden、C測試均完成 | 略過已測的7組15 deg/s後注入其餘49組 |
| 2 Hz＋5 Hz混合 | 四個代表case的CSV、C header、逐筆golden、C測試均完成 | 注入四組並回傳逐筆log |
| 95／100／105 Hz | 九組離線摘要完成 | 實際改timer pacing並記錄tick |
| 取樣jitter | 20組可重現離線模擬完成 | 記錄真實相鄰tick，不用假裝raw陣列等於jitter |
| dropout | 三種掉點×四種policy離線比較完成 | 決定並實作`sensor_valid=0`時的policy |

## 2. 第一優先：7 Hz三振幅

交付目錄：`test_vectors/gating_7hz_boundary/`。

```text
vector 0 = 7 Hz / 10 deg/s
vector 1 = 7 Hz / 15 deg/s
vector 2 = 7 Hz / 20 deg/s
```

設計上7 Hz在4–6 Hz目標頻帶外，三組都應關閉；但目前PC與C reference已確認
20 deg/s會開啟361/400筆。板上若重現，不是資料輸入失敗，而是確認演算法邊界。

回傳欄位：

```text
test_case_id,amplitude_peak_dps,sample_index,sample_tick_ms,gyro_x_dps,
tremor_envelope,voluntary_envelope,tremor_ratio,enabled
```

## 3. 第二優先：完整頻率×振幅邊界

交付目錄：`test_vectors/gating_amplitude_sweep/`。共56組、39,200筆；上週已完成
1～6 Hz與8 Hz的15 deg/s，因此板上可略過這七組，補測其餘49組。每組仍要
完整Reset、輸入700筆並回傳摘要，不可把56組連續輸入同一個gate狀態。

`gating_amplitude_sweep_vectors.h`只在一個測試`.c`檔include，因為raw與reference
約占118 KB Flash。板上結果必須同時報告逐筆`mismatch_count`與功能邊界；
7 Hz/20 deg/s即使`mismatch_count=0`，仍是已知的設計誤開。

## 4. 第三優先：混合訊號

交付目錄：`test_vectors/gating_mixed_boundary/`。四個case分別驗證單獨5 Hz、兩頻帶
同強度、震顫較強及強自主動作漏判。這是逐筆演算法注入，不是健康組員動作資料。

## 5. 取樣率測試不能只換CSV

filter係數固定按100 Hz設計，因此要驗證95／105 Hz，必須真的讓`TremorGate_Update()`
分別以約10.526／10／9.524 ms間隔執行，並同步記錄`sample_tick_ms`。每個call rate再測
4、5、6 Hz／15 deg/s。只在100 Hz loop中餵一個「標示為105 Hz」的陣列，不能證明
timer偏差對實機的影響。

## 6. Jitter測試以真實tick為主

先連續記錄至少60秒的`sample_tick_ms`，輸出相鄰差值的min、max、mean及超出8–12 ms
的筆數。離線±1／±2／±4 ms只是壓力情境；真正的結論必須來自STM32 timer與I2C
實際紀錄。

## 7. Dropout安全策略

第一版建議：任一筆`sensor_valid=0`時立即輸出`enabled=0`並清除on/off debounce
計數，同時回報fault給App。不要默默沿用上一筆資料。測試時用韌體測試模式注入：

- 週期性2%無效資料。
- 震顫段隨機5%無效資料（固定seed以便重現）。
- 連續20筆、共200 ms無效資料。

回傳`sequence`、tick、`sensor_valid`、enabled與fault。這項測試需要韌體實作policy，
演算法組不能只靠CSV宣稱板上完成。

## 8. 安全順序與驗收

1. 所有注入測試先禁止H-bridge，只觀察命令。
2. 每個case前重設gate與sample index。
3. 先逐筆比對golden enabled，再看摘要。
4. 通過後才可接非人體負載；沒有穩定雛形前不做人體通電測試。
5. `enabled`一致只代表gating判斷一致，不代表馬達能跟隨或已產生抑震。

PC完整驗證：

```powershell
python -m unittest discover -s algorithms/validation -p "test_*.py"
algorithms\handoff\test\build_and_run.bat
```
