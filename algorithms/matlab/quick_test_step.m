%% quick_test_step.m
%  快速測試 step function（不需要 Simulink）
%  直接在 MATLAB for 迴圈中逐樣本呼叫 step function
%  用來確認 step function 本身是否正確

clc; clear; close all;
addpath('utils');

fprintf('========================================\n');
fprintf('  Step Function 快速驗證（無 Simulink）\n');
fprintf('========================================\n\n');

%% 產生測試訊號
fs = 100; duration = 10; dt = 1/fs;
[signal, tremor_true, voluntary_true, ~, t] = ...
    generate_synthetic_tremor('fs', fs, 'duration', duration, ...
        'f_tremor', 5, 'tremor_amps', [2.0, 0.8, 0.3], ...
        'tremor_phases', [0, pi/4, pi/3], 'vol_amps', [5, 3], ...
        'vol_freqs', [0.5, 1.2], 'noise_std', 0.2, 'freq_drift', 0.3);

N = length(signal);

%% 測試 BMFLC_step
fprintf('[1/2] 測試 BMFLC_step...\n');
clear BMFLC_step  % 清除 persistent 變數
tremor_bmflc_step = zeros(1, N);
for k = 1:N
    tremor_bmflc_step(k) = BMFLC_step(signal(k));
end

%% 測試 eHWFLC_KF_step
fprintf('[2/2] 測試 eHWFLC_KF_step...\n');
clear eHWFLC_KF_step  % 清除 persistent 變數
tremor_ehwflc_step = zeros(1, N);
freq_ehwflc_step   = zeros(1, N);
for k = 1:N
    [tremor_ehwflc_step(k), freq_ehwflc_step(k)] = eHWFLC_KF_step(signal(k));
end

%% 效能計算
transient = fs * 2;
eval_idx = (transient+1):N;

[pwr_ehwflc, ~, ~] = compute_tremor_power(...
    tremor_true(eval_idx), tremor_ehwflc_step(eval_idx), ...
    voluntary_true(eval_idx), signal(eval_idx));
[pwr_bmflc, ~, ~] = compute_tremor_power(...
    tremor_true(eval_idx), tremor_bmflc_step(eval_idx), ...
    voluntary_true(eval_idx), signal(eval_idx));

rmse_ehwflc = sqrt(mean((tremor_true(eval_idx) - tremor_ehwflc_step(eval_idx)).^2));
rmse_bmflc  = sqrt(mean((tremor_true(eval_idx) - tremor_bmflc_step(eval_idx)).^2));

fprintf('\n  Step Function 直接測試結果：\n');
fprintf('  ┌───────────────────┬────────────┬──────────┐\n');
fprintf('  │ 指標               │ eHWFLC-KF  │ BMFLC    │\n');
fprintf('  ├───────────────────┼────────────┼──────────┤\n');
fprintf('  │ 震顫功率降低 (%%)   │   %5.1f%%    │  %5.1f%%   │\n', pwr_ehwflc, pwr_bmflc);
fprintf('  │ RMSE (°/s)         │   %5.3f    │  %5.3f   │\n', rmse_ehwflc, rmse_bmflc);
fprintf('  └───────────────────┴────────────┴──────────┘\n\n');

%% 也跑一下離線版做對照
fprintf('  離線版對照：\n');
[tremor_ehwflc_off, ~, ~, ~] = eHWFLC_KF(signal, fs);
[tremor_bmflc_off, ~, ~]     = BMFLC(signal, fs);

[pwr_ehwflc_off, ~, ~] = compute_tremor_power(...
    tremor_true(eval_idx), tremor_ehwflc_off(eval_idx), ...
    voluntary_true(eval_idx), signal(eval_idx));
[pwr_bmflc_off, ~, ~] = compute_tremor_power(...
    tremor_true(eval_idx), tremor_bmflc_off(eval_idx), ...
    voluntary_true(eval_idx), signal(eval_idx));

fprintf('  ┌───────────────────┬────────────┬──────────┐\n');
fprintf('  │ 指標               │ eHWFLC-KF  │ BMFLC    │\n');
fprintf('  ├───────────────────┼────────────┼──────────┤\n');
fprintf('  │ 震顫功率降低 (%%)   │   %5.1f%%    │  %5.1f%%   │\n', pwr_ehwflc_off, pwr_bmflc_off);
fprintf('  └───────────────────┴────────────┴──────────┘\n\n');

%% 繪圖比較
figure('Name', 'Step vs 離線', 'Position', [100, 200, 1200, 700]);

subplot(3,1,1);
plot(t, tremor_true, 'k', 'LineWidth', 1.2); hold on;
plot(t, tremor_ehwflc_step, 'b', 'LineWidth', 1);
plot(t, tremor_ehwflc_off, 'b--', 'LineWidth', 1);
legend('真實震顫', 'eHWFLC-KF (step)', 'eHWFLC-KF (離線)');
title('eHWFLC-KF: Step vs 離線');
xlabel('時間 (s)'); ylabel('°/s'); grid on; xlim([0 10]);

subplot(3,1,2);
plot(t, tremor_true, 'k', 'LineWidth', 1.2); hold on;
plot(t, tremor_bmflc_step, 'r', 'LineWidth', 1);
plot(t, tremor_bmflc_off, 'r--', 'LineWidth', 1);
legend('真實震顫', 'BMFLC (step)', 'BMFLC (離線)');
title('BMFLC: Step vs 離線');
xlabel('時間 (s)'); ylabel('°/s'); grid on; xlim([0 10]);

subplot(3,1,3);
plot(t, freq_ehwflc_step, 'b', 'LineWidth', 1.2);
xlabel('時間 (s)'); ylabel('頻率 (Hz)');
title('eHWFLC-KF 頻率追蹤 (step)');
grid on; xlim([0 10]); ylim([3 8]);

sgtitle('Step Function vs 離線版 比較', 'FontSize', 14, 'FontWeight', 'bold');

fprintf('  ※ 如果 step 結果差但離線版好 → step function 有 bug\n');
fprintf('  ※ 如果兩者都差 → 測試訊號或參數有問題\n');
fprintf('  ※ 如果兩者都好 → Simulink 資料傳輸有問題\n');
