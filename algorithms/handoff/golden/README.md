# `golden/` — 黃金測試向量（Model-in-the-Loop 基準）

這些 CSV 是「MATLAB 模型在 fs = 100 Hz 的真值輸出」，
給 [../test/test_equivalence.c](../test/test_equivalence.c) 逐點比對，
用來證明「上板的 C」沒有改變演算法數值。

## 檔案

| 檔案 | 內容 | 格式 |
|---|---|---|
| `input.csv` | 確定性合成輸入（10 s @ 100 Hz, 1000 點） | 每行 1 個 `double` |
| `golden_bmflc.csv` | BMFLC `tremor_est` | 每行 1 個 `double` |
| `golden_ehwflc.csv` | eHWFLC-KF `tremor_est, freq_hz` | 每行 `tremor,freq` |

數值以 `%.17g` 寫出（double 全精度）。

## 輸入訊號公式（確定性、無亂數）

```
t = k / 100                              (k = 0 … 999)
voluntary = 5·sin(2π·0.5·t) + 3·sin(2π·1.2·t)              # 自主動作 < 2 Hz
tremor    = 2·sin(2π·5·t) + 0.8·sin(2π·10·t + π/4)
                          + 0.3·sin(2π·15·t + π/3)          # 5 Hz 基頻 + 2、3 次諧波
input     = voluntary + tremor + 0.1·sin(2π·37·t)           # + 高頻擾動
```

刻意不含 `rand/randn`，所以 MATLAB / C / Python 跑出來都一致，可逐位元比對。

## 目前這份的來源 & 重新產生

- **目前 CSV** 由現有 Coder C 直接跑出（功能上即 MATLAB 模型，與獨立 Python 重實作交叉
  比對誤差 ~1e-14）。
- **正式版**請在 MATLAB 執行 [gen_golden_vectors.m](gen_golden_vectors.m) 重新產生
  （以原始 `.m` 為權威來源）。它會覆寫這三個 CSV。
- 改 `fs`、改演算法參數、或改輸入公式 → 必須重跑 `gen_golden_vectors.m` 同步更新。
