# PWM映射與真實抑震率驗證

日期：2026-07-30

本文件定義演算法端可交付的控制命令與Motor OFF／ON比較方法。它不代表N20已通過
4–6 Hz負載測試，也不代表裝置已有患者成效。

## 1. PWM輸入與輸出

輸入：

- `enabled`：V2 gating輸出，0時必須立即停止。
- `tremor_estimate_dps`：eHWFLC-KF估測波形，正負決定反相方向。
- `sensor_valid`、`driver_fault`：任一異常都必須停止。

輸出：

- `duty_percent`：0–100%的PWM request，不等於力、位移或速度。
- `direction`：-1、0、1；和實際拉索方向的對應需由硬體標定。

第一版採P-only、deadband、上限與每tick變化限制。參考行為：
`algorithms/validation/pwm_control_reference.py`。內建30%上限只供低功率bench bring-up示例，
不是最終安全值；硬體組需依供電、driver、負載、電流與溫度另行設定。

反轉時先將PWM降到0，下一個100 Hz tick才切方向。gate關閉、感測器無效、driver fault或
輸入NaN時不使用slew limit，直接輸出0。

## 2. PWM bench紀錄

不接人體，以實際spool、拉索、預張力與代表性負載測4、5、6 Hz，每個條件至少重複3次。
每次保存：

- command頻率、`tremor_estimate`、`enabled`、duty與方向。
- 實際位移、拉力或第二顆IMU角速度。
- command到motion延遲、missed reversal、backlash與cable slack。
- 電壓、電流、driver fault及溫度。

只有證明負載下能穩定換向，才進入通電配戴測試。

## 3. 真實抑震率需要第二顆獨立IMU

控制用BNO055的資料已進入閉迴路，不適合單獨證明效果。第二顆IMU固定在要評估的手部
位置，不參與控制，只記錄100 Hz三軸raw gyro。Motor OFF與ON必須使用相同固定方式、
動作條件、時間長度及分析程式，每個條件至少重複3次並保留個別結果。

執行：

```powershell
python algorithms/validation/suppression_metrics.py `
  --motor-off motor_off.csv --motor-on motor_on.csv `
  --output-json suppression.json
```

主要指標使用三軸4–6 Hz PSD power的中位數：

```text
TPSR (%) = 100 × (Power_OFF - Power_ON) / Power_OFF
```

- 正值：Motor ON的4–6 Hz power較低。
- 0：沒有改變。
- 負值：Motor ON反而增加震動。

工具同時輸出RMS振幅下降百分比與X/Y/Z個別power。如果某軸下降、另一軸上升超過10%，
會標示`axis_transfer_warning`，避免把「震動換方向」誤寫成抑震成功。

## 4. 報告限制

- 合成訊號結果、健康者模擬抖動、非人體負載與患者測試必須分開報告。
- 單次最好結果不能當整體成效；需報告各次結果與變異。
- TPSR只描述量測位置、量測頻帶與當次條件，不等於治療效果或臨床改善。
