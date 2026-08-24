# 給瑋哲：今天先照這份操作

目標：把 8/18 branch 的舊 3–8 Hz gate 換成 hardened 4–6 Hz gate，先做 **馬達斷電的板上逐筆驗證**。

1. 確認 repo HEAD：

   ```powershell
   git rev-parse HEAD
   ```

   必須是 `9e51e56bfcaf70ca1c140b3f37e1977935c534e5`。

2. 拔除馬達／H-bridge 電源，不可戴在人手上。

3. 在本資料夾跑：

   ```powershell
   .\run_host_tests.bat
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\verify_package.ps1
   ```

4. 先 dry-run，再安裝 gate：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_gate_only.ps1 `
     -ProjectRoot "你的 Ryan repo 路徑"

   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install_gate_only.ps1 `
     -ProjectRoot "你的 Ryan repo 路徑" -Apply
   ```

5. 對 Ryan repo 套用 `ryan_9e51_shadow_only.patch`，先 `git apply --check` 再 `git apply`。

6. STM32CubeIDE 執行 Project > Clean，再完整 rebuild CM7。確認只有一份 `tremor_gate.c/.h` 被編入。

7. 用 `target_test/` 跑 21 組、14,700 筆測資；不要在 timer ISR 逐筆 blocking printf，請先放 RAM buffer。

8. 回傳：

   - `stm32_6to7_trace.csv`
   - `stm32_6to7_comparison.json`
   - build ID、ELF/MAP hash
   - 100 Hz timing log
   - AIN1/AIN2/PWMA 全程 LOW 的 logic-analyzer 證據

注意：CSV 一定要分開寫 `gate_enabled`；舊 packet 的 `motor_enabled` 不是 gate。本輪 `actuation_authority` 和 `motor_output_active` 必須全程為 0。

完整細節與欄位格式請看 `README.md`。
