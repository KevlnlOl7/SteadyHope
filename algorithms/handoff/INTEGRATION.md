# STM32CubeIDE 整合教學 — 把演算法放進韌體

給 STM32 組。目標：把 [src/](src/) 的 C 接進 CubeIDE 專案、在 100 Hz 呼叫、餵對輸入。
先讀本檔照著放，再照 [README.md](README.md) §5 的三階段驗證。

> `src/` 的 C 已是 **ARM-safe 版**（以 ARM 目標重產生、無 x86 SSE2），BMFLC 與 eHWFLC 都可直接編。
> 日後改演算法/參數要重新產生時，見 [README.md](README.md) §4（`../matlab/codegen_arm.m` 一鍵）。

---

## 0. 大前提：放進 **CM7** 核專案（不是 CM4！）

STM32H745 是雙核，CubeIDE 會生 `*_CM7` 與 `*_CM4` 兩個子專案。
演算法全程用 `double`：

- **CM7 有雙精度 FPU（FPv5-D16）** → `double` 硬體加速。
- **CM4 只有單精度 FPU** → `double` 會變**軟體模擬**，慢 10–50×，等於白做。

👉 **一定放 `*_CM7` 專案。** 下面所有步驟都在 CM7 專案上操作。

---

## 1. 把檔案加進專案

1. 在 CM7 專案下建一個資料夾，例如 `Core/Algo/`。
2. 把這兩個資料夾整包複製進去：`src/bmflc/`、`src/ehwflc/`（各自已含 `rtwtypes.h`，自含型別，不需 common/）。
   （CubeIDE：直接把資料夾拖進 Project Explorer，選 **Copy files**。）
3. 確認這些 `.c` 會被編譯（在 Project Explorer 裡不是灰色/被 exclude）：
   - `bmflc/`：`BMFLC_step.c`、`BMFLC_step_data.c`、`BMFLC_step_initialize.c`
   - `ehwflc/`：`eHWFLC_KF_step.c`、`eHWFLC_KF_step_data.c`、`eHWFLC_KF_step_initialize.c`、`eye.c`
   - `_terminate.c` 用不到，可留著不影響。

## 2. 設 include path

Project 上右鍵 → **Properties** → **C/C++ General → Paths and Symbols** → **Includes** 頁 → 選 **GNU C** →
**Add…** 把三個資料夾加進來（勾 *Add to all configurations*、可勾 *Is a workspace path*）：

```
Core/Algo/bmflc
Core/Algo/ehwflc
```

存檔後 Clean + Build 一次，確認 `#include "BMFLC_step.h"` 找得到。

## 3. 確認 FPU 與數學庫

- **Properties → C/C++ Build → Settings → Tool Settings → MCU Settings**：
  - Floating-point unit：**FPv5-D16**（雙精度）
  - Floating-point ABI：**Hard**
  - 這是 H745 CM7 的預設值，但務必確認（若被改成 SP 或 soft，`double` 會爆慢或連結錯誤）。
- `sin`/`cos`（double）來自 newlib 的 `libm`，CubeIDE 預設會連，不用額外設定。
- 演算法本身不需 `printf`；若你要用 `printf("%f")` 除錯，才需在 Linker flags 加 `-u _printf_float`。

## 4. 呼叫演算法

```c
#include "BMFLC_step.h"
#include "eHWFLC_KF_step.h"

/* 開機時（可選；首次呼叫 *_step 也會自動 init）——換使用者/重來才需要顯式呼叫 */
eHWFLC_KF_step_init();
/* BMFLC_step_init();  // 若也要用 BMFLC */

/* 每個 100 Hz tick 呼叫一次： */
void tremor_tick(double gyro_dps_one_axis) {
    double tremor, freq;
    eHWFLC_KF_step(gyro_dps_one_axis, &tremor, &freq);  /* 或 BMFLC_step(...) */
    actuator_drive(-(float)(GAIN * tremor));            /* 反相抵銷；GAIN/極性硬體校 */
}
```

> **單例**：`eHWFLC_KF_step` / `BMFLC_step` 內部是 file-scope `static` 狀態，
> **只能餵一軸**。不要同一顆同時對 X 和 Y 呼叫同一個 step，狀態會互相污染。

## 5. 餵對輸入：BNO055 **raw gyro**（單軸 °/s）

> 📗 感測器端完整版（切模式序列、400 kHz 設定、確認真 100 Hz、除錯速查表）獨立成
> [BNO055_GYRO_SETUP.md](BNO055_GYRO_SETUP.md)，給負責 I2C 那位直接照做。以下是精簡版。

演算法要的是**單軸陀螺儀角速度 °/s**，跟融合無關。用非融合模式只讀 6 bytes：

```c
#define BNO055_ADDR            (0x28 << 1)   /* 7-bit 0x28 → HAL 用 8-bit；COM3 拉高則為 0x29 */
#define BNO055_PAGE_ID         0x07
#define BNO055_OPR_MODE        0x3D
#define BNO055_GYR_DATA_X_LSB  0x14          /* X:0x14/0x15  Y:0x16/0x17  Z:0x18/0x19 */

/* 一次性：切到只有 gyro 的非融合模式 */
void bno055_gyro_init(I2C_HandleTypeDef *h) {
    uint8_t v;
    v = 0x00; HAL_I2C_Mem_Write(h, BNO055_ADDR, BNO055_OPR_MODE, 1, &v, 1, 20); /* CONFIGMODE */
    HAL_Delay(25);
    v = 0x00; HAL_I2C_Mem_Write(h, BNO055_ADDR, BNO055_PAGE_ID,  1, &v, 1, 20); /* page 0 */
    /* UNIT_SEL(0x3B) bit1 = gyro 單位；預設 0 = dps，保持預設即可（別切 rps） */
    v = 0x03; HAL_I2C_Mem_Write(h, BNO055_ADDR, BNO055_OPR_MODE, 1, &v, 1, 20); /* GYROONLY */
    HAL_Delay(25);
}

/* 讀一軸 → °/s（以 X 為例） */
double bno055_read_gyro_x_dps(I2C_HandleTypeDef *h) {
    uint8_t b[6];
    HAL_I2C_Mem_Read(h, BNO055_ADDR, BNO055_GYR_DATA_X_LSB, 1, b, 6, 20);
    int16_t raw = (int16_t)((b[1] << 8) | b[0]);   /* little-endian, X 軸 */
    return raw / 16.0;                             /* ★ 16 LSB/dps，一定要除 16 */
}
```

⚠️ **最容易錯的地方**：
- 直接把 raw int16 餵進去、忘了 `/16.0` → 尺度差 16 倍，`tremor_est` 全錯。
- 餵**加速度**而非 gyro → 物理量、單位、頻帶都不對。
- I2C 位址（0x28 vs 0x29）與模式切換的 `HAL_Delay` 不能省。
- 想調 gyro 頻寬：`GYR_CONFIG_0` 在 **page 1**（先寫 PAGE_ID=1）；bring-up 階段用預設即可。
  以上暫存器**以 BNO055 datasheet register map 為準**再核對一次。

## 6. 100 Hz 時序，且**不要在 ISR 裡阻塞等 I2C**

- 設一個 TIM 溢位 **100 Hz**。
- **Bring-up（先求跑起來）**：timer ISR 只設一個 flag，主迴圈看到 flag 就
  `read gyro → step → actuator`。400 kHz I2C 讀 6 bytes ~0.2 ms，可接受。
- **正式版**：改成 DMA / 中斷式 I2C 讀，資料到齊的 callback 再跑 `step`，避免佔用 ISR。

```c
volatile uint8_t tick_flag = 0;
void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim) {
    if (htim->Instance == TIM6) tick_flag = 1;   /* 100 Hz */
}
/* main while(1): */
if (tick_flag) { tick_flag = 0; tremor_tick(bno055_read_gyro_x_dps(&hi2c1)); }
```

## 7. 量單步耗時（DWT）確認在 10 ms 預算內

```c
CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
DWT->CYCCNT = 0;  DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
uint32_t t0 = DWT->CYCCNT;
eHWFLC_KF_step(sample, &tr, &fr);
uint32_t cyc = DWT->CYCCNT - t0;
/* 微秒 = cyc / (SystemCoreClock / 1e6)；預期 ~10–30 µs @ 480 MHz */
```

## 8. 上板後先做「板上 Stage 1」再談閉迴路

把 [golden/input.csv](golden/) 轉成板上的 `const double[]`（1000 點），
餵過 `*_step`，把輸出經 SWV/printf 撈回 PC，與 [golden/golden_*.csv](golden/) 比對。
**max|err| 應 < 1e-6**（與 PC 上 `test/build_and_run.sh` 同一把尺）。
過了才代表「ARM build 的數值 == MATLAB 模型」，這時閉迴路量到的抑制率才可信。

---

## 常見坑 checklist
- [ ] 放在 **CM7**（不是 CM4）→ 否則 double 軟體模擬爆慢。
- [ ] FPU = FPv5-D16 / Hard。
- [ ] eHWFLC 已用 **ARM 目標重產生**（無 `emmintrin.h`）。
- [ ] 輸入是 **gyro °/s**，且 `raw / 16.0`。
- [ ] 真的跑 **100 Hz**（timer 與 gyro ODR 都要到）。
- [ ] 一個 step 只餵**一軸**。
- [ ] ISR 不阻塞 I2C。
- [ ] 板上 Stage 1 對 golden 過關，再看閉迴路數字。
