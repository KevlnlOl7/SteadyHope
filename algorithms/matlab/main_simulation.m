%% main_simulation.m
%  主模擬腳本：比較 eHWFLC-KF 與 BMFLC 震顫估測演算法
%
%  此腳本模擬帕金森氏症震顫（含多諧波）+ 自主動作 + 感測器雜訊，
%  使用兩種演算法分別進行即時震顫估測，並比較其表現。
%
%  作者: 專題組
%  參考: Zhou et al., IEEE TNSRE, 2022

clc; clear; close all;

% 加入工具函式路徑
addpath('utils');

fprintf('========================================\n');
fprintf('  帕金森震顫估測演算法模擬比較\n');
fprintf('  eHWFLC-KF vs BMFLC\n');
fprintf('========================================\n\n');

%% ============================================================
%  1. 參數設定
%  ============================================================
fs = 100;          % 取樣頻率 (Hz) — 與 BNO055 一致
duration = 10;     % 模擬時間 (s)
f_tremor = 5;      % 震顫基頻 (Hz) — 帕金森典型 4-6 Hz

%% ============================================================
%  2. 產生合成測試訊號
%  ============================================================
fprintf('[1/5] 產生合成測試訊號...\n');

[signal, tremor_true, voluntary_true, noise, t] = ...
    generate_synthetic_tremor(...
        'fs', fs, ...
        'duration', duration, ...
        'f_tremor', f_tremor, ...
        'tremor_amps', [2.0, 0.8, 0.3], ...       % 基頻 + 2nd + 3rd 諧波
        'tremor_phases', [0, pi/4, pi/3], ...
        'vol_amps', [5, 3], ...                    % 自主動作振幅
        'vol_freqs', [0.5, 1.2], ...               % 自主動作頻率
        'noise_std', 0.2, ...                      % 感測器雜訊
        'freq_drift', 0.3);                        % 頻率漂移 ±0.3 Hz

N = length(signal);
fprintf('  訊號長度: %d 樣本 (%.1f 秒 @ %d Hz)\n', N, duration, fs);
fprintf('  震顫: %.1f Hz (基頻) + %.1f Hz + %.1f Hz (諧波)\n', ...
    f_tremor, 2*f_tremor, 3*f_tremor);
fprintf('  自主動作: 0.5 Hz + 1.2 Hz\n');
fprintf('  頻率漂移: ±0.3 Hz\n\n');

%% ============================================================
%  3. 執行 eHWFLC-KF
%  ============================================================
fprintf('[2/5] 執行 eHWFLC-KF...\n');

tic;
[tremor_ehwflc, freq_ehwflc, w_ehwflc, dbg_ehwflc] = eHWFLC_KF(signal, fs, ...
    'M', 3, ...                    % 3 階諧波
    'omega_init', 2*pi*5, ...      % 初始 5 Hz
    'mu_w', 0.01, ...              % 權重學習率
    'mu_omega', 0.005, ...         % 頻率學習率
    'Q', 1e-2, ...                 % KF 過程雜訊（關鍵參數）
    'R', 0.05, ...                 % KF 觀測雜訊
    'P0', 1, ...                   % 初始協方差
    'fc_lp', 2, ...                % 低通截止 2 Hz
    'omega_min', 2*pi*3, ...       % 最小頻率 3 Hz
    'omega_max', 2*pi*12);         % 最大頻率 12 Hz
time_ehwflc = toc;

fprintf('  執行時間: %.3f 秒\n', time_ehwflc);
fprintf('  平均每樣本: %.1f μs\n\n', time_ehwflc/N*1e6);

%% ============================================================
%  4. 執行 BMFLC
%  ============================================================
fprintf('[3/5] 執行 BMFLC...\n');

tic;
[tremor_bmflc, w_bmflc, dbg_bmflc] = BMFLC(signal, fs, ...
    'f_low', 3, ...                % 頻帶下限 3 Hz
    'f_high', 12, ...              % 頻帶上限 12 Hz
    'delta_f', 0.5, ...            % 頻率間距 0.5 Hz
    'mu', 0.5, ...                 % NLMS 正規化學習率
    'fc_lp', 2);                   % 低通截止 2 Hz
time_bmflc = toc;

fprintf('  執行時間: %.3f 秒\n', time_bmflc);
fprintf('  平均每樣本: %.1f μs\n\n', time_bmflc/N*1e6);

%% ============================================================
%  5. 效能評估
%  ============================================================
fprintf('[4/5] 計算效能指標...\n\n');

% 去除暫態（前 2 秒）
transient_samples = fs * 2;  % 前 2 秒為收斂期
eval_idx = (transient_samples + 1):N;

% --- eHWFLC-KF 效能 ---
[pwr_red_ehwflc, pwr_before, pwr_after_ehwflc] = ...
    compute_tremor_power(...
        tremor_true(eval_idx), ...
        tremor_ehwflc(eval_idx), ...
        voluntary_true(eval_idx), ...
        signal(eval_idx));

rmse_ehwflc = sqrt(mean((tremor_true(eval_idx) - tremor_ehwflc(eval_idx)).^2));

% 自主動作追蹤誤差
vol_est_ehwflc = signal - tremor_ehwflc;
vol_rmse_ehwflc = sqrt(mean((voluntary_true(eval_idx) - ...
    dbg_ehwflc.voluntary_est(eval_idx)).^2));

% --- BMFLC 效能 ---
[pwr_red_bmflc, ~, pwr_after_bmflc] = ...
    compute_tremor_power(...
        tremor_true(eval_idx), ...
        tremor_bmflc(eval_idx), ...
        voluntary_true(eval_idx), ...
        signal(eval_idx));

rmse_bmflc = sqrt(mean((tremor_true(eval_idx) - tremor_bmflc(eval_idx)).^2));

vol_est_bmflc = signal - tremor_bmflc;
vol_rmse_bmflc = sqrt(mean((voluntary_true(eval_idx) - ...
    dbg_bmflc.voluntary_est(eval_idx)).^2));

% --- 頻率追蹤精度 (eHWFLC-KF only) ---
true_freq = f_tremor + 0.3 * sin(2*pi*0.1*t);  % 真實瞬時頻率
freq_error = mean(abs(freq_ehwflc(eval_idx) - true_freq(eval_idx)));

% --- 列印結果 ---
fprintf('┌────────────────────────────────────────────────────┐\n');
fprintf('│           效 能 比 較 結 果                         │\n');
fprintf('├───────────────────┬────────────┬────────────────────┤\n');
fprintf('│ 指標               │ eHWFLC-KF  │ BMFLC              │\n');
fprintf('├───────────────────┼────────────┼────────────────────┤\n');
fprintf('│ 震顫功率降低 (%%)   │  %6.1f%%    │  %6.1f%%            │\n', ...
    pwr_red_ehwflc, pwr_red_bmflc);
fprintf('│ 震顫 RMSE (°/s)   │  %6.3f     │  %6.3f              │\n', ...
    rmse_ehwflc, rmse_bmflc);
fprintf('│ 自主動作 RMSE(°/s) │  %6.3f     │  %6.3f              │\n', ...
    vol_rmse_ehwflc, vol_rmse_bmflc);
fprintf('│ 頻率追蹤誤差 (Hz)  │  %6.3f     │  N/A                │\n', ...
    freq_error);
fprintf('│ 每樣本耗時 (μs)   │  %6.1f     │  %6.1f              │\n', ...
    time_ehwflc/N*1e6, time_bmflc/N*1e6);
fprintf('└───────────────────┴────────────┴────────────────────┘\n\n');

% 判斷優勝
if pwr_red_ehwflc > pwr_red_bmflc
    fprintf('★ 結論: eHWFLC-KF 震顫功率降低較高 (%.1f%% vs %.1f%%)\n', ...
        pwr_red_ehwflc, pwr_red_bmflc);
else
    fprintf('★ 結論: BMFLC 震顫功率降低較高 (%.1f%% vs %.1f%%)\n', ...
        pwr_red_bmflc, pwr_red_ehwflc);
end

%% ============================================================
%  6. 繪圖
%  ============================================================
fprintf('\n[5/5] 繪製比較圖...\n');
plot_results(t, signal, tremor_true, voluntary_true, ...
    tremor_ehwflc, tremor_bmflc, freq_ehwflc, ...
    dbg_ehwflc, dbg_bmflc, true_freq, eval_idx);

fprintf('\n✓ 模擬完成！\n');
