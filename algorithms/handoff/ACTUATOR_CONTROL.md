# 致動器與 PWM 控制交付說明

本文件回答 V2 gating 之後的下一層問題：**馬達允許作動時，應該出多少力？**
目前機構組回報使用 N20 gearmotor，但尚缺完整型號、減速比與負載實測，因此本文先定義
控制介面、量測方法與選型門檻，不把 N20 或任何替代 actuator 寫成已驗證結論。

## 1. 邊界與目前狀態

- V2 gating 只輸出 `gate_enabled`，它只是完整權限鏈的一個條件，不能直接決定馬達動。
- `tremor_est` 的正負決定反相補償方向，絕對值映射為 PWM duty。
- `freq_hz` 已知不可靠，不可參與 gating、PWM 或 App biomarker。
- `control_sim.m` 目前名義上比較 PID，實作其實是 **P-only**（`Ki=Kd=0`）。在取得
  actuator gain、頻寬與延遲前，不應直接加入 integral/derivative，也不可把模擬的
  `Kp=0.8/1.2` 解讀成 80%/120% duty。

目前 authoritative 控制資料流：

```text
raw gyro → SuppressionControl(estimator + V2 gate + freshness/fault checks)
         → MotorCommandMapper → MotorPositionGuard module
         → TB6612Driver → STM32_TB6612_HAL → PWM/H-bridge
```

目前 `firmware/algo` 使用 powered-bench profile：boot armed、100% intensity、full-scale PWM，
encoder／SetZero／position guard 模組雖仍保留在程式與 telemetry 中，但不具 veto authority。
這是為了離架馬達測試；未來 wearable/guarded profile 才恢復 homing、行程與 motion fault authority。
現行接線、調參與 build 指令以 [`firmware/algo/README.md`](../../firmware/algo/README.md) 為準。

## 2. 控制律設計輸入（不可繞過 canonical safety chain）

控制迴路仍以 **100 Hz** 更新；PWM carrier 是另一個較高頻率的 timer output，起始候選可用
約 **20 kHz**，但最終值須符合 H-bridge 與馬達 driver datasheet。

舊文件曾用單一 `motor_pwm_apply()` 表示整層致動器；那只是概念圖，不能實作成繞過安全
模組的捷徑。現在每個 100 Hz fresh tick 必須由 canonical pipeline 完成：

1. `SuppressionControl` 檢查 fresh sample、estimator、gate 與 inhibit/fault。
2. mapper 套用經台架審核的 deadband、gain、saturation、slew 與方向 polarity。
3. powered-bench profile 不要求 debugger ARM 或 `SetZero`，encoder/position 只作 telemetry；未來 guarded profile 才讓它們 veto。
4. TB6612 driver 執行 duty ceiling 與 reversal safe-time；final HAL 驗證方向/AIN 並套用。
5. 任一無效狀態立即 `STBY=LOW`、`CCR=0`、`AIN1=AIN2=LOW`，必要時 latch fault。

若 driver 是 DIR+PWM、IN1/IN2 或兩顆單向線纜馬達，方向層接法不同；必須以實際 H-bridge
型號決定。PWM timer 應在開機時 start 一次，100 Hz tick 只更新 CCR，不要每 tick 重新
start/stop timer，也不要用阻塞式 `HAL_Delay()` 製造換向 dead time。

## 3. N20 規格尚缺資料

「N20」只描述約 10×12 mm 的 micro metal gearmotor 外型，不是完整型號。進行 PWM 調參前，
硬體組需補齊：

- 額定電壓與實際供電電壓
- gear ratio、空載 rpm、continuous/rated torque
- stall current（只供 driver sizing，**不可作正常工作點**）
- 是否有 encoder、encoder CPR
- H-bridge 型號、continuous/peak current 與保護機制
- spool 半徑、線纜有效行程、預張力與目標拉力
- 馬達、gearbox、spool 與手套端總重量

初步速度需求可用：

```text
peak_rpm = 60 × tremor_frequency_hz × cable_amplitude / spool_radius
```

所需 spool torque 可用：

```text
torque = cable_force × spool_radius
```

兩式只做第一輪 sizing；實際還要加入負載降速、換向加速度、摩擦、backlash、線纜彈性與
安全係數。選型應看 continuous operating region，不可用 stall torque 宣稱可行。

## 4. N20 loaded bandwidth test（先測再決定換不換）

測試必須裝上實際 spool、線纜、預張力及代表性手套負載，不接受只測空載馬達。

### 輸入

- 4、5、6 Hz 正負交替 command
- 多個安全 duty level，由低至高
- Motor OFF baseline
- 每個條件重複至少 3 次

### 量測

- 獨立 IMU或 encoder 的實際輸出振幅與相位
- command→motion 總延遲及每次測試的變異
- 最低有效 duty、dead zone、換向空行程與 cable slack
- supply current、driver fault、馬達與 gearbox 溫升
- 連續運轉後是否出現齒隙增加、噪音或卡滯

### 判定

保留 N20 的最低條件：

- 4–6 Hz 均能穩定換向，沒有 missed reversal 或明顯 cable slack。
- gain/phase 可重複，能建立可用的 actuator model。
- 總延遲量測後回填 `control_sim.m`；目前 `≤15 ms` 僅是模擬的設計目標，不是已驗證規格。
- 在安全 continuous current/temperature 內仍有足夠輸出，不依賴 stall。
- Motor ON 相對 OFF 的獨立 IMU tremor power 確實下降，且自主動作干擾未惡化。

任一頻率出現嚴重衰減、phase 不穩、backlash 主導或熱／電流超限，就先停止調 PID，改做
actuator/transmission 選型。控制器無法補救物理頻寬不足。

## 5. 替代 actuator 的選型方向

| 選項 | 優點 | 代價／風險 | 適用時機 |
|---|---|---|---|
| 低減速比、帶 encoder 的 coreless DC | 低 rotor inertia，可沿用 PWM/H-bridge/cable 架構 | 成本較高，仍有 gearbox backlash | N20 頻寬不足時的優先替代 |
| Voice-coil linear actuator | 雙向、無 gearbox backlash、短行程反應快 | 發熱、短行程、需 current/position/force control | 第二代機構重設計 |
| 低減速比 BLDC/direct drive | 無碳刷、可高頻寬與低 backlash | 三相 driver、commutation、encoder 複雜 | 有足夠整合時間時 |
| Semi-active damper | 不易注入同相能量，安全性較高 | 機構與材料取得複雜 | 長期研究方向 |

不建議把 hobby servo、ERM vibration motor 或普通單向 solenoid 當作等價替代：它們通常
分別受限於內部控制／backlash、無法精確控制反相力、或單向與發熱問題。

## 6. IMU 決策

- **控制端暫時保留 BNO055**：GYROONLY raw gyro 100 Hz 已由韌體組實測成立，9 月前更換
  會同時改變 sensor 與 actuator 兩個變因。
- bench 的第二顆 IMU 必須獨立於控制迴路。BNO055 可沿用；若重新採購並重視低 noise、
  明確 ODR 與低 latency，可評估 ICM-42688-P 或 BMI270 breakout，但採購前仍需確認
  電壓、介面、driver 成熟度與交期。
- 第二顆 IMU 的資料不可經過抑震演算法；應輸出 raw data，由 PC 端獨立計算波形、PSD 與 TPSR。

## 7. 交付與紀錄

每次 actuator/PWM 版本至少保存：

- 完整 BOM 型號、供電、gear ratio、spool 半徑、線纜預張力
- timer clock、PSC、ARR、PWM carrier 與控制更新率
- `K_PWM`、deadband、maximum duty、方向極性
- 4/5/6 Hz gain、phase、latency、current、temperature
- Motor OFF/ON 的獨立 IMU raw CSV、分析程式與 TPSR 結果

這些資料完成後，才能把 `control_sim.m` 的標稱 `K_act`、`tau_act` 與 delay 換成實測值，
再決定是否需要 PI/PID、phase compensation 或更換 actuator。

## 8. 可執行的演算法端參考工具

- `algorithms/validation/pwm_control_reference.py`：把`enabled`與`tremorEstimate`映射成
  duty／方向，包含deadband、saturation、slew limit、反轉先歸零及異常立即停止。
- `algorithms/handoff/SUPPRESSION_VALIDATION.md`：第二顆IMU的Motor OFF／ON錄製方式。
- `algorithms/validation/suppression_metrics.py`：計算三軸4–6 Hz TPSR、RMS下降比例與
  axis transfer警告。

這些是可重現的介面與分析規格；它們不會自動決定N20的安全PWM上限或拉力。安全上限仍
必須由硬體與機構組在非人體負載下量測後填入。
