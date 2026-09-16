# BNO055 設定指南 — 切到 raw gyro、跑穩 100 Hz

給負責韌體/I2C 這一側的人。目標：讓 BNO055 用**非融合模式只出陀螺儀**，
以 **100 Hz、單軸、°/s** 穩定餵給顫抖抑制演算法。照這份做完，你就完全掌握感測器端。

> 這份只講「感測器 + I2C」。演算法怎麼呼叫看 [INTEGRATION.md](INTEGRATION.md)，介面契約看 [README.md](README.md)。

---

## 0. 為什麼要切成 gyro-only（先懂目的，才好控制）

- 演算法要的是**單軸陀螺儀角速度（°/s）**，跟 9 軸融合（orientation）無關。
- 融合模式（NDOF）要一次讀 ~26 bytes，又會被 BNO055 的 clock-stretching 拖 → 有效取樣率只剩 **~37 Hz**。
- 改成 **GYROONLY 只讀 6 bytes**：即使 100 kHz I2C 也 < 1 ms，**100 Hz 輕鬆達成**（400 kHz 更寬裕）。

換句話說：**慢不是因為 I2C 不行，是因為讀太多、又用融合模式。** 換 gyro-only 就解掉。

---

## 1. 一頁規格（你要做的六件事）

| # | 動作 | 值 |
|---|---|---|
| 1 | 進 CONFIGMODE | `OPR_MODE(0x3D) = 0x00`，**等 19 ms** |
| 2 | 確認在 page 0 | `PAGE_ID(0x07) = 0x00` |
| 3 | 切 GYROONLY | `OPR_MODE(0x3D) = 0x03`，**等 ≥7 ms（保險 30 ms）** |
| 4 | 讀資料 | 從 `GYR_DATA_X_LSB(0x14)` 連讀 **6 bytes**（X/Y/Z，int16 LE）|
| 5 | 換算 | `dps = raw_int16 / 16.0`，取**一軸** |
| 6 | 提速 + 定拍 | I2C **400 kHz**；用 **100 Hz 硬體 timer** 觸發讀取，別在 ISR 阻塞 |

⚠️ 第 1、3 步的延遲**不能省**：BNO055 換模式需要時間，沒等就讀 = 拿到舊模式的髒資料。

---

## 2. 暫存器速查

| 暫存器 | 位址(page 0) | 用途 |
|---|---|---|
| `PAGE_ID` | 0x07 | 0 = 主暫存器區（資料/模式都在這） |
| `OPR_MODE` | 0x3D | 操作模式（見下） |
| `UNIT_SEL` | 0x3B | 單位選擇；gyro 預設 dps（bit1=0），**保持預設** |
| `GYR_DATA_X_LSB` | 0x14 | X 軸低位（X:0x14/15, Y:0x16/17, Z:0x18/19） |

`OPR_MODE` 常用值：`CONFIGMODE=0x00`、**`GYROONLY=0x03`**、`AMG=0x07`、`NDOF=0x0C`（融合，就是我們要離開的）。

I2C 位址：預設 **0x28**（7-bit）；若板子的 **COM3/ADR** 腳被拉高則是 **0x29**。
HAL 用 8-bit 位址 → `0x28<<1 = 0x50`。

---

## 3. 程式：切換 + 讀取

```c
#define BNO055_ADDR      (0x28 << 1)   /* COM3 拉高改 0x29 */
#define REG_PAGE_ID      0x07
#define REG_OPR_MODE     0x3D
#define REG_GYR_X_LSB    0x14
#define MODE_CONFIG      0x00
#define MODE_GYROONLY    0x03

/* 開機呼叫一次：融合/未知模式 → GYROONLY */
void bno055_switch_to_gyro(I2C_HandleTypeDef *h) {
    uint8_t v;
    v = MODE_CONFIG;    HAL_I2C_Mem_Write(h, BNO055_ADDR, REG_OPR_MODE, 1, &v, 1, 30);
    HAL_Delay(19);                                    /* → CONFIG 需 19 ms */
    v = 0x00;           HAL_I2C_Mem_Write(h, BNO055_ADDR, REG_PAGE_ID,  1, &v, 1, 30);
    v = MODE_GYROONLY;  HAL_I2C_Mem_Write(h, BNO055_ADDR, REG_OPR_MODE, 1, &v, 1, 30);
    HAL_Delay(30);                                    /* → 操作模式 需 ≥7 ms */
}

/* 讀一軸 → °/s（以 X 為例；要哪軸看裝置擺放/顫抖最明顯那軸） */
double bno055_read_gyro_x_dps(I2C_HandleTypeDef *h) {
    uint8_t b[6];
    HAL_I2C_Mem_Read(h, BNO055_ADDR, REG_GYR_X_LSB, 1, b, 6, 20);
    int16_t raw = (int16_t)((b[1] << 8) | b[0]);      /* little-endian, X */
    return raw / 16.0;                                /* ★ 16 LSB/dps，必除 16 */
}
```

> 若你原本已有讀 BNO055 的程式：找到寫 `OPR_MODE = 0x0C (NDOF)` 那行改成 `bno055_switch_to_gyro()`，
> 把讀 Euler/quaternion 改成讀 `0x14` 起 6 bytes。改動很小。

---

## 4. 把 I2C 提到 400 kHz（CubeMX / CubeIDE）

1. 開 `.ioc` → **Connectivity → I2Cx**。
2. **Parameter Settings → I2C Speed Mode = Fast Mode**，**Speed Frequency = 400 kHz**。
3. 存檔讓 CubeMX 重算 `TIMINGR`，重新生成程式。
4. 硬體確認 SDA/SCL 有 **pull-up（2.2k–4.7kΩ）**、線越短越好。BNO055 支援到 400 kHz。

---

## 5. 用 100 Hz timer 定拍（關鍵，別靠 I2C 自己的節奏）

演算法假設每次呼叫剛好隔 **10 ms（均勻）**。所以「定拍」交給硬體 timer，I2C 只負責在該拍前把資料送到：

```c
/* 一個 TIM 設 100 Hz 溢位（如 TIM6） */
volatile uint8_t tick_flag = 0;
void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim) {
    if (htim->Instance == TIM6) tick_flag = 1;
}

/* main while(1)：看到 flag 才讀 + 跑演算法（bring-up 用阻塞讀即可，6 bytes ~0.2ms @400k） */
while (1) {
    if (tick_flag) {
        tick_flag = 0;
        double g = bno055_read_gyro_x_dps(&hi2c1);
        double tremor, freq;
        eHWFLC_KF_step(g, &tremor, &freq);
        actuator_drive(-(float)(GAIN * tremor));
    }
}
```

- **Bring-up**：上面這樣阻塞讀就好，先求跑起來。
- **正式版**：改 DMA / 中斷式 I2C 讀，讀完的 callback 再跑演算法，完全不佔 ISR。
- **不要**把演算法或 I2C 阻塞塞進 timer ISR 本體。

---

## 6. 兩個一定要「量」出來的確認

理論說得通，但 BNO055 的 clock-stretching 只有實測才準。上板後做這兩件：

**(A) 真的是 100 Hz 嗎？**
在讀取那段翻一支 GPIO，示波器看是不是穩定 100 Hz 方波；或數 10 秒收到幾筆（應 ≈1000）。

**(B) 一次讀多久？會不會偶爾爆？**
```c
CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
DWT->CYCCNT = 0;  DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
uint32_t t0 = DWT->CYCCNT;
bno055_read_gyro_x_dps(&hi2c1);
uint32_t us = (DWT->CYCCNT - t0) / (SystemCoreClock / 1000000u);
/* 預期幾百 µs；若偶發接近 ms 級，改 DMA/中斷式讀 */
```

**(C) scale 對不對？**（最容易被忽略）
把板子以已知角速度轉（或先在融合模式記一組 gyro 值當基準），比對 GYROONLY 讀值 `÷16` 對不對得上。
歪掉表示忘了 `÷16` 或 gyro range 被動到 → `tremor_est` 振幅會整個錯。

---

## 7. 讀不到 / 值不對 —— 除錯速查表

| 症狀 | 可能原因 |
|---|---|
| 讀回全 `0x00` 或 `0xFF` | I2C 位址錯（0x28 vs 0x29）、沒切到操作模式、切模式後沒等延遲、pull-up 缺 |
| `HAL` 回 `BUSY`/`TIMEOUT`、bus lockup | pull-up 不對/線太長、速度太快、clock-stretching 撞到 HAL timeout（把 timeout 調大一點測） |
| 值固定不動 | 還停在 CONFIGMODE、`PAGE_ID` 不是 0、讀錯暫存器 |
| 值有動但尺度怪 | 忘了 `÷16`、range 被改、餵成了加速度而非 gyro |
| 偶爾重複值 / 掉樣本 | gyro 內部更新率不足或撞拍（page 1 `GYR_CONFIG_0` 調高頻寬）、ISR 被 I2C 阻塞 |
| 抑制效果時好時壞 | 取樣不是穩定 100 Hz（先過第 6 點 A）、相位延遲太大 |

> 進階（可選）：擔心撞拍就到 **page 1** 的 `GYR_CONFIG_0(0x0A)` 把 gyro 頻寬設高（如 116 Hz）。
> 但改前先寫 `PAGE_ID=1`、改完寫回 0；**改到 range 會影響 scale**，改完要重做第 6(C) 點。
> 暫存器 bit 定義以 BNO055 datasheet Table 3-9 為準。

---

## 8. 完成標準（打勾才算 OK）
- [ ] `OPR_MODE` 讀回 `0x03`（真的在 GYROONLY）。
- [ ] 三軸 gyro 讀值合理、靜止時接近 0、轉動時對應。
- [ ] `÷16` 後單位是 °/s，scale 驗過。
- [ ] GPIO/計數確認穩定 **100 Hz**。
- [ ] 單次讀取耗時幾百 µs、無偶發爆表。
- [ ] 交給演算法的是**單一軸**的 °/s。
