# STM32 2 Hz自主動作＋5 Hz震顫代表測試包

這個測試包把離線40組混合強度掃描縮成四組最有解釋力的逐筆向量，供STM32直接
注入。所有輸入都是合成GyroX，不是患者或健康組員實測資料。

| case | 2 Hz自主動作 | 5 Hz震顫 | 目前PC reference | 用途 |
|---|---:|---:|---:|---|
| `PURE_T15` | 0 | 15 deg/s | 開啟 | 單獨震顫baseline |
| `MIX_V10_T10` | 10 | 10 deg/s | 不開啟 | 兩頻帶同振幅 |
| `MIX_V10_T20` | 10 | 20 deg/s | 開啟 | 震顫較強 |
| `MIX_V20_T20` | 20 | 20 deg/s | 不開啟 | 強自主動作造成的已知漏判情境 |

`gating_mixed_boundary_vectors.h`包含四組700筆raw輸入、case名稱與逐筆reference
`enabled`。STM32測試方式和7 Hz包相同：motor off、每10 ms送一筆、每組前重設
`TremorGate`，回傳case、sample、GyroX、兩頻帶envelope、ratio及enabled。

這四組只負責重現目前比例判斷的代表行為，不是臨床Sensitivity／Specificity。
真正配戴資料仍依`REAL_DATA_PROTOCOL.md`錄製，且`mixed`先標`scored=0`。

重新產生：

```powershell
python algorithms/validation/generate_gating_mixed_boundary_vectors.py
```
