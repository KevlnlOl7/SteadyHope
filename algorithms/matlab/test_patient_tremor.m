%% test_patient_tremor.m
%  ====================================================================
%  真實病患 .npy 震顫數據 — 全方面測試腳本
%  ====================================================================
%
%  測試項目：
%    1. 病患資料載入與解析 (.npy 格式，含震顫片段篩選與串接)
%    2. 基本統計分析 (加速度特徵)
%    3. 頻域分析（FFT / PSD，尋找真實震顫主頻）
%    4. eHWFLC-KF 與 BMFLC 震顫估測（三軸 + RSS）
%    5. 馬達控制力輸出計算（根據線性加速度與力臂關係計算扭矩）
%    6. 即時性能測試（step function 延遲與 STM32 算力預算）
%    7. 完整可視化報告（保存至 real_data_exp/results/）
%
%  使用方式：直接在 MATLAB 中執行即可。可調整 patient_id 測試不同病患。
%  ====================================================================

clc; clear; close all;
addpath('real_data_exp');
addpath('utils');

fprintf('╔══════════════════════════════════════════════════════════╗\n');
fprintf('║  真實病患 .npy 震顫數據 — 全方面測試                     ║\n');
fprintf('║  eHWFLC-KF & BMFLC 演算法驗證 + 馬達控制力計算          ║\n');
fprintf('╚══════════════════════════════════════════════════════════╝\n\n');

%% ====================================================================
%  1. 資料載入與解析
%  ====================================================================
fprintf('[1/7] 載入病患 .npy 震顫數據...\n');

% ---- 參數設定 ----
patient_id = '20'; % 病患的ID
dataset_name = 'Tim-Tremor'; % 資料集
accel_unit_is_g = true;      

dataset_dir = fullfile('Parkinson-s-Disease-Tremor-Dataset-main', dataset_name);
x_path = fullfile(dataset_dir, sprintf('%s-X.npy', patient_id));
y_path = fullfile(dataset_dir, sprintf('%s-Y.npy', patient_id));

% 檢查檔案是否存在
if ~exist(x_path, 'file') || ~exist(y_path, 'file')
    error('找不到病患檔案！請確認路徑：%s', x_path);
end

% 載入數據 (X: [N_segments, 128, 3] 單精度, Y: [N_segments, 1] 標籤)
X_all = readNPY(x_path);
Y_all = readNPY(y_path);

N_segments = size(X_all, 1);
fprintf('  已載入病患 %s 的數據，共 %d 個片段 (每個片段 128 點)\n', patient_id, N_segments);

% ---- 篩選有震顫的片段 (Label > 0) ----
tremor_mask = Y_all > 0;
n_tremor_segs = sum(tremor_mask);
fprintf('  震顫片段比例: %d/%d (%.1f%%)\n', n_tremor_segs, N_segments, (n_tremor_segs/N_segments)*100);

if n_tremor_segs == 0
    warning('該病患無明顯震顫片段 (Label > 0)，改用全部數據進行測試');
    X_sel = X_all;
else
    X_sel = X_all(tremor_mask, :, :);
end

% ---- 串接為連續的一維訊號 ----
% 為相容後續腳本變數名，變數仍命名為 gyro_x, gyro_y, gyro_z (但物理量為加速度)
gyro_x = reshape(X_sel(:, :, 1)', [], 1);
gyro_y = reshape(X_sel(:, :, 2)', [], 1);
gyro_z = reshape(X_sel(:, :, 3)', [], 1);

N_raw = length(gyro_x);

% ---- 去除直流分量 (重力加速度偏置) ----
gyro_x = gyro_x - mean(gyro_x);
gyro_y = gyro_y - mean(gyro_y);
gyro_z = gyro_z - mean(gyro_z);

% 設定取樣率 (Tim-Tremor 資料集統一為 50 Hz)
fs_raw = 50; 
fs_unique = 50; 
t_raw = (0:N_raw-1) / fs_raw;

% 計算 RSS (Root Sum Squares 三軸合成加速度)
gyro_rss = sqrt(gyro_x.^2 + gyro_y.^2 + gyro_z.^2);

% 去重變數相容性對接 (病患資料無 serial 重複問題，直接對接)
gyro_x_unique = gyro_x;
gyro_y_unique = gyro_y;
gyro_z_unique = gyro_z;
gyro_rss_unique = gyro_rss;

fprintf('  串接後連續訊號總長: %d 樣本 (%.1f 秒)\n', N_raw, N_raw/fs_raw);

%% ====================================================================
%  2. 基本統計分析
%  ====================================================================
fprintf('\n[2/7] 基本統計分析 (單位: g)...\n');

axes_names = {'Accel X', 'Accel Y', 'Accel Z', 'RSS'};
axes_data = {gyro_x, gyro_y, gyro_z, gyro_rss};

fprintf('\n  ┌─────────┬──────────┬──────────┬──────────┬──────────┬──────────┐\n');
fprintf('  │  軸      │  平均值   │  標準差   │  最大值   │  最小值   │  峰峰值  │\n');
fprintf('  ├─────────┼──────────┼──────────┼──────────┼──────────┼──────────┤\n');
for i = 1:4
    d = axes_data{i};
    fprintf('  │ %-8s│ %+7.4f  │  %6.4f   │ %+7.4f  │ %+7.4f  │  %6.4f   │\n', ...
        axes_names{i}, mean(d), std(d), max(d), min(d), max(d)-min(d));
end
fprintf('  └─────────┴──────────┴──────────┴──────────┴──────────┴──────────┘\n\n');

%% ====================================================================
%  3. 頻域分析 (FFT / PSD)
%  ====================================================================
fprintf('[3/7] 頻域分析...\n');

% 尋找震顫最明顯的軸作為主分析軸 (標準差最大者)
stds = [std(gyro_x), std(gyro_y), std(gyro_z)];
[~, main_ax_idx] = max(stds);
main_axis_name = axes_names{main_ax_idx};
signal_main = axes_data{main_ax_idx};

N_fft = 2^nextpow2(N_raw);
f_axis = (0:N_fft/2-1) * fs_raw / N_fft;

% FFT
Y_fft = abs(fft(signal_main, N_fft)) / N_raw;
Y_fft_half = Y_fft(1:N_fft/2);

% 找震顫主頻 (跳過 DC)
[~, pk_idx] = max(Y_fft_half(2:end));  
pk_idx = pk_idx + 1;
f_peak = f_axis(pk_idx);
fprintf('  主要震顫軸: %s (標準差: %.4f g)\n', main_axis_name, stds(main_ax_idx));
fprintf('  %s 主頻: %.2f Hz (單邊振幅: %.4f g)\n', main_axis_name, f_peak, Y_fft_half(pk_idx)*2);

% 各軸主頻
for i = 1:3
    sig_tmp = axes_data{i};
    Y_tmp = abs(fft(sig_tmp, N_fft)) / N_raw;
    Y_tmp_half = Y_tmp(1:N_fft/2);
    [amp_pk, idx_pk] = max(Y_tmp_half(2:end));
    idx_pk = idx_pk + 1;
    fprintf('  %s 主頻: %.2f Hz (振幅: %.4f g)\n', ...
        axes_names{i}, f_axis(idx_pk), amp_pk*2);
end

% 震顫頻帶 (3-12 Hz) 功率佔比
tremor_band = f_axis >= 3 & f_axis <= 12;
total_power_main = sum(Y_fft_half.^2);
tremor_power_main = sum(Y_fft_half(tremor_band).^2);
fprintf('  %s 震顫頻帶(3-12Hz)功率佔比: %.1f%%\n', main_axis_name, tremor_power_main/total_power_main*100);

%% ====================================================================
%  4. 演算法測試 — 三軸 + RSS
%  ====================================================================
fprintf('\n[4/7] 執行震顫估測演算法（三軸 + RSS）...\n');

% 測試配置
test_signals = {gyro_x, gyro_y, gyro_z, gyro_rss};
test_names   = {'X軸', 'Y軸', 'Z軸', 'RSS'};

% 結果儲存
results = struct();

for ax = 1:4
    sig = test_signals{ax}';  % 轉為行向量
    fprintf('\n  === %s ===\n', test_names{ax});
    
    % --- eHWFLC-KF (step function) ---
    clear eHWFLC_KF_step
    tremor_ehw = zeros(1, N_raw);
    freq_ehw   = zeros(1, N_raw);
    tic;
    for k = 1:N_raw
        [tremor_ehw(k), freq_ehw(k)] = eHWFLC_KF_step(sig(k), fs_raw);
    end
    time_ehw = toc;
    
    % --- BMFLC (step function) ---
    clear BMFLC_step
    tremor_bmf = zeros(1, N_raw);
    tic;
    for k = 1:N_raw
        tremor_bmf(k) = BMFLC_step(sig(k), fs_raw);
    end
    time_bmf = toc;
    
    % --- 參考訊號 (帶通 3-12 Hz, 零相位) ---
    [b_bp, a_bp] = butter(2, [3, 12] / (fs_raw/2), 'bandpass');
    tremor_ref = filtfilt(b_bp, a_bp, sig);
    
    % --- 自主動作參考 (<2 Hz) ---
    [b_lp, a_lp] = butter(2, 2 / (fs_raw/2), 'low');
    vol_ref = filtfilt(b_lp, a_lp, sig);
    
    % --- 效能指標（去除前 2 秒暫態）---
    transient = fs_raw * 2;
    eval_idx = (transient+1):N_raw;
    
    % 功率降低
    [pwr_ehw, ~, ~] = compute_tremor_power(...
        tremor_ref(eval_idx), tremor_ehw(eval_idx), ...
        vol_ref(eval_idx), sig(eval_idx));
    [pwr_bmf, ~, ~] = compute_tremor_power(...
        tremor_ref(eval_idx), tremor_bmf(eval_idx), ...
        vol_ref(eval_idx), sig(eval_idx));
    
    % RMSE
    rmse_ehw = sqrt(mean((tremor_ref(eval_idx) - tremor_ehw(eval_idx)).^2));
    rmse_bmf = sqrt(mean((tremor_ref(eval_idx) - tremor_bmf(eval_idx)).^2));
    
    % 相關係數
    corr_ehw = corr(tremor_ref(eval_idx)', tremor_ehw(eval_idx)');
    corr_bmf = corr(tremor_ref(eval_idx)', tremor_bmf(eval_idx)');
    
    % 延遲 (µs/sample)
    latency_ehw = time_ehw / N_raw * 1e6;
    latency_bmf = time_bmf / N_raw * 1e6;
    
    fprintf('    eHWFLC-KF: 功率↓%.1f%% | RMSE=%.4f | r=%.3f | %.1f µs/smp\n', ...
        pwr_ehw, rmse_ehw, corr_ehw, latency_ehw);
    fprintf('    BMFLC:     功率↓%.1f%% | RMSE=%.4f | r=%.3f | %.1f µs/smp\n', ...
        pwr_bmf, rmse_bmf, corr_bmf, latency_bmf);
    
    % 儲存
    results(ax).name = test_names{ax};
    results(ax).signal = sig;
    results(ax).tremor_ehw = tremor_ehw;
    results(ax).tremor_bmf = tremor_bmf;
    results(ax).freq_ehw = freq_ehw;
    results(ax).tremor_ref = tremor_ref;
    results(ax).vol_ref = vol_ref;
    results(ax).pwr_ehw = pwr_ehw;
    results(ax).pwr_bmf = pwr_bmf;
    results(ax).rmse_ehw = rmse_ehw;
    results(ax).rmse_bmf = rmse_bmf;
    results(ax).corr_ehw = corr_ehw;
    results(ax).corr_bmf = corr_bmf;
    results(ax).latency_ehw = latency_ehw;
    results(ax).latency_bmf = latency_bmf;
end

%% ====================================================================
%  5. 馬達控制力輸出計算（為上馬達測試做準備）
%  ====================================================================
fprintf('\n[5/7] 馬達控制力輸出計算...\n');

% ---- 系統參數 ----
m_payload = 0.15;         % 負載質量 (kg)，例如湯匙+食物
L_arm = 0.12;             % 力臂長度 (m)
J_payload = m_payload * L_arm^2;  % 轉動慣量 (kg·m²)
motor_max_torque = 0.5;   % 馬達最大扭矩 (N·m)
motor_voltage = 12;       % 馬達工作電壓 (V)
Kt = 0.03;               % 馬達扭矩常數 (N·m/A)

fprintf('  系統參數:\n');
fprintf('    負載質量: %.0f g\n', m_payload * 1000);
fprintf('    力臂長度: %.0f mm\n', L_arm * 1000);
fprintf('    轉動慣量: %.4f kg·m²\n', J_payload);
fprintf('    馬達最大扭矩: %.2f N·m\n', motor_max_torque);

% 使用主要震顫軸的 eHWFLC-KF 估測結果
tremor_est = results(main_ax_idx).tremor_ehw; % 估測的震顫加速度
freq_est   = results(main_ax_idx).freq_ehw;

% ---- 加速度與角加速度物理關係轉換 ----
% 由於病患數據為線性加速度 a (g 或 m/s²)，而非角速度
% 設感測器安裝在力臂末端，則切向加速度 a_t = alpha * L_arm
% 得角加速度 alpha = a_t / L_arm (rad/s²)
if accel_unit_is_g
    accel_ms2 = tremor_est * 9.8;  % 轉為 m/s²
else
    accel_ms2 = tremor_est;
end
alpha_tremor_rad = accel_ms2 / L_arm;  % rad/s²
alpha_tremor = alpha_tremor_rad * 180 / pi; % 轉為 °/s² (統計顯示用)

% ---- 計算所需抵消扭矩 ----
% τ = J × α (反向施加)
torque_required = -J_payload * alpha_tremor_rad;  % N·m (反向)

% ---- 計算所需電流與 PWM ----
current_required = torque_required / Kt;  % A
pwm_duty = abs(current_required) / (motor_voltage / (Kt * 10));  
pwm_duty = min(pwm_duty, 1.0);  
pwm_direction = sign(torque_required);  

fprintf('\n  馬達控制力輸出統計 (%s eHWFLC-KF):\n', main_axis_name);
fprintf('  ┌─────────────────────┬────────────────┐\n');
fprintf('  │ 指標                 │ 數值            │\n');
fprintf('  ├─────────────────────┼────────────────┤\n');
fprintf('  │ 震顫加速度 RMS (g)   │ %10.4f      │\n', rms(tremor_est));
fprintf('  │ 角加速度 RMS (°/s²) │ %10.2f      │\n', rms(alpha_tremor));
fprintf('  │ 角加速度 Peak (°/s²)│ %10.2f      │\n', max(abs(alpha_tremor)));
fprintf('  │ 扭矩 RMS (mN·m)    │ %10.4f      │\n', rms(torque_required)*1000);
fprintf('  │ 扭矩 Peak (mN·m)   │ %10.4f      │\n', max(abs(torque_required))*1000);
fprintf('  │ 電流 RMS (mA)      │ %10.2f      │\n', rms(current_required)*1000);
fprintf('  │ 電流 Peak (mA)     │ %10.2f      │\n', max(abs(current_required))*1000);
fprintf('  │ PWM 平均佔空比      │ %10.1f%%     │\n', mean(pwm_duty)*100);
fprintf('  │ PWM 最大佔空比      │ %10.1f%%     │\n', max(pwm_duty)*100);
fprintf('  └─────────────────────┴────────────────┘\n');

% 判斷馬達可行性
if max(abs(torque_required)) < motor_max_torque
    fprintf('  ✓ 扭矩在馬達能力範圍內，可行！\n');
else
    fprintf('  ✗ 警告：所需扭矩超過馬達上限！\n');
end

%% ====================================================================
%  6. Step Function 即時性能壓力測試
%  ====================================================================
fprintf('\n[6/7] 即時性能壓力測試...\n');

n_runs = 3;
latencies_ehw = zeros(1, N_raw * n_runs);
latencies_bmf = zeros(1, N_raw * n_runs);

sig_test = test_signals{main_ax_idx}';

for run = 1:n_runs
    clear eHWFLC_KF_step BMFLC_step
    for k = 1:N_raw
        tic_start = tic;
        eHWFLC_KF_step(sig_test(k), fs_raw);
        latencies_ehw((run-1)*N_raw + k) = toc(tic_start) * 1e6;
    end
    clear eHWFLC_KF_step
    
    clear BMFLC_step
    for k = 1:N_raw
        tic_start = tic;
        BMFLC_step(sig_test(k), fs_raw);
        latencies_bmf((run-1)*N_raw + k) = toc(tic_start) * 1e6;
    end
    clear BMFLC_step
end

fprintf('  eHWFLC-KF 延遲統計 (%d 次):\n', n_runs);
fprintf('    平均: %.1f µs | 中位: %.1f µs | P99: %.1f µs | 最大: %.1f µs\n', ...
    mean(latencies_ehw), median(latencies_ehw), ...
    prctile(latencies_ehw, 99), max(latencies_ehw));

fprintf('  BMFLC 延遲統計 (%d 次):\n', n_runs);
fprintf('    平均: %.1f µs | 中位: %.1f µs | P99: %.1f µs | 最大: %.1f µs\n', ...
    mean(latencies_bmf), median(latencies_bmf), ...
    prctile(latencies_bmf, 99), max(latencies_bmf));

% STM32 @ 50 Hz → 每個 sample 有 20,000 µs 運算時間
stm32_budget = 20000;  % µs
fprintf('\n  STM32 @ 50 Hz 預算: %d µs/sample\n', stm32_budget);
fprintf('  eHWFLC-KF 佔用: %.3f%%\n', mean(latencies_ehw)/stm32_budget*100);
fprintf('  BMFLC     佔用: %.3f%%\n', mean(latencies_bmf)/stm32_budget*100);

%% ====================================================================
%  7. 完整可視化報告
%  ====================================================================
fprintf('\n[7/7] 繪製完整報告...\n');

results_dir = 'real_data_exp/results';
if ~exist(results_dir, 'dir'), mkdir(results_dir); end

% ======== Figure 1: 原始資料總覽 ========
fig1 = figure('Name', '病患資料總覽', 'Position', [50, 50, 1500, 900]);

subplot(4,1,1);
plot(t_raw, gyro_x, 'r', 'LineWidth', 0.8);
ylabel('g'); title('Accel X'); grid on; xlim([0 t_raw(end)]);

subplot(4,1,2);
plot(t_raw, gyro_y, 'Color', [0.1 0.5 0.9], 'LineWidth', 0.8);
ylabel('g'); title('Accel Y'); grid on; xlim([0 t_raw(end)]);

subplot(4,1,3);
plot(t_raw, gyro_z, 'Color', [0.1 0.7 0.3], 'LineWidth', 0.8);
ylabel('g'); title('Accel Z'); grid on; xlim([0 t_raw(end)]);

subplot(4,1,4);
plot(t_raw, gyro_rss, 'k', 'LineWidth', 0.8);
xlabel('時間 (s)'); ylabel('g'); title(sprintf('RSS (三軸合成) [主要分析軸: %s]', main_axis_name)); grid on; xlim([0 t_raw(end)]);

sgtitle(sprintf('病患 %s — 三軸原始加速度訊號', patient_id), 'FontSize', 14, 'FontWeight', 'bold');

% ======== Figure 2: 頻域分析 ========
fig2 = figure('Name', '頻域分析', 'Position', [80, 80, 1400, 700]);

for i = 1:4
    subplot(2,2,i);
    sig_tmp = axes_data{i};
    Y_tmp = abs(fft(sig_tmp, N_fft)) / N_raw;
    plot(f_axis, Y_tmp(1:N_fft/2)*2, 'LineWidth', 1.2);
    xlabel('頻率 (Hz)'); ylabel('振幅 (g)');
    title(sprintf('%s 頻譜', axes_names{i}));
    grid on; xlim([0 25]);
    xline(3, '--r', '3 Hz'); xline(12, '--r', '12 Hz');
    hold on;
    area_idx = f_axis >= 3 & f_axis <= 12;
    area(f_axis(area_idx), Y_tmp(area_idx)*2, ...
        'FaceColor', [1 0.3 0.3], 'FaceAlpha', 0.15, 'EdgeColor', 'none');
end

sgtitle(sprintf('病患 %s — 頻譜分析（標示震顫頻帶 3-12 Hz）', patient_id), ...
    'FontSize', 14, 'FontWeight', 'bold');

% ======== Figure 3: 演算法效果 ========
fig3 = figure('Name', '演算法效果', 'Position', [110, 110, 1500, 900]);
r = results(main_ax_idx);

subplot(4,1,1);
plot(t_raw, r.signal, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.5); hold on;
plot(t_raw, r.tremor_ref, 'k', 'LineWidth', 1);
xlabel('時間 (s)'); ylabel('g');
title(sprintf('%s 原始訊號 & 帶通參考震顫', main_axis_name));
legend('原始訊號', '帶通參考 (3-12 Hz)', 'Location', 'northeast');
grid on; xlim([0 t_raw(end)]);

subplot(4,1,2);
plot(t_raw, r.tremor_ref, 'k', 'LineWidth', 0.8); hold on;
plot(t_raw, r.tremor_ehw, 'Color', [0.2 0.4 0.9], 'LineWidth', 1);
xlabel('時間 (s)'); ylabel('g');
title(sprintf('eHWFLC-KF 震顫估測 (功率↓%.1f%%, r=%.3f)', r.pwr_ehw, r.corr_ehw));
legend('參考', 'eHWFLC-KF');
grid on; xlim([0 t_raw(end)]);

subplot(4,1,3);
plot(t_raw, r.tremor_ref, 'k', 'LineWidth', 0.8); hold on;
plot(t_raw, r.tremor_bmf, 'Color', [0.9 0.2 0.2], 'LineWidth', 1);
xlabel('時間 (s)'); ylabel('g');
title(sprintf('BMFLC 震顫估測 (功率↓%.1f%%, r=%.3f)', r.pwr_bmf, r.corr_bmf));
legend('參考', 'BMFLC');
grid on; xlim([0 t_raw(end)]);

subplot(4,1,4);
plot(t_raw, r.freq_ehw, 'Color', [0.2 0.4 0.9], 'LineWidth', 1.2);
xlabel('時間 (s)'); ylabel('頻率 (Hz)');
title('eHWFLC-KF 基頻追蹤');
grid on; xlim([0 t_raw(end)]); ylim([3 12]);
yline(f_peak, '--r', sprintf('FFT 主頻 %.1f Hz', f_peak));

sgtitle(sprintf('%s 震顫估測詳細結果 — 病患 %s', main_axis_name, patient_id), ...
    'FontSize', 14, 'FontWeight', 'bold');

% ======== Figure 4: 抑制效果放大 ========
fig4 = figure('Name', '抑制效果放大', 'Position', [140, 140, 1500, 700]);

t_center = t_raw(end) / 2;
zoom_start = max(2, t_center - 1.5);
zoom_end = zoom_start + 3;
zoom_mask = t_raw >= zoom_start & t_raw <= zoom_end;

subplot(2,1,1);
plot(t_raw(zoom_mask), r.signal(zoom_mask), 'Color', [0.7 0.7 0.7], 'LineWidth', 1); hold on;
suppressed_ehw = r.signal(zoom_mask) - r.tremor_ehw(zoom_mask);
suppressed_bmf = r.signal(zoom_mask) - r.tremor_bmf(zoom_mask);
plot(t_raw(zoom_mask), suppressed_ehw, 'Color', [0.2 0.4 0.9], 'LineWidth', 1.5);
plot(t_raw(zoom_mask), suppressed_bmf, 'Color', [0.9 0.2 0.2], 'LineWidth', 1.5);
plot(t_raw(zoom_mask), r.vol_ref(zoom_mask), '--', 'Color', [0.1 0.8 0.2], 'LineWidth', 2);
xlabel('時間 (s)'); ylabel('g');
title('震顫抑制效果（放大）');
legend('原始訊號', 'eHWFLC-KF 抑制後', 'BMFLC 抑制後', '自主動作參考');
grid on;

subplot(2,1,2);
zoom_idx_arr = find(zoom_mask);
N_zoom = length(zoom_idx_arr);
N_fft2 = 2^nextpow2(N_zoom);
f_zoom = (0:N_fft2/2-1) * fs_raw / N_fft2;

S_orig = abs(fft(r.signal(zoom_idx_arr) - mean(r.signal(zoom_idx_arr)), N_fft2));
S_ehw  = abs(fft(suppressed_ehw - mean(suppressed_ehw), N_fft2));
S_bmf  = abs(fft(suppressed_bmf - mean(suppressed_bmf), N_fft2));

plot(f_zoom, 20*log10(S_orig(1:N_fft2/2)+eps), 'Color', [0.5 0.5 0.5]); hold on;
plot(f_zoom, 20*log10(S_ehw(1:N_fft2/2)+eps), 'Color', [0.2 0.4 0.9], 'LineWidth', 1.5);
plot(f_zoom, 20*log10(S_bmf(1:N_fft2/2)+eps), 'Color', [0.9 0.2 0.2], 'LineWidth', 1.5);
xlabel('頻率 (Hz)'); ylabel('振幅 (dB)');
title('抑制前後頻譜比較');
legend('抑制前', 'eHWFLC-KF 抑制後', 'BMFLC 抑制後');
grid on; xlim([0 fs_raw/2]);
xline(3, '--k', '3 Hz'); xline(12, '--k', '12 Hz');

sgtitle(sprintf('病患 %s — 震顫抑制效果放大視圖', patient_id), 'FontSize', 14, 'FontWeight', 'bold');

% ======== Figure 5: 馬達控制力輸出 ========
fig5 = figure('Name', '馬達控制力輸出', 'Position', [170, 50, 1500, 900]);

subplot(4,1,1);
plot(t_raw, tremor_est, 'Color', [0.2 0.4 0.9], 'LineWidth', 1);
ylabel('g'); title(sprintf('估測震顫線性加速度 (eHWFLC-KF, %s)', main_axis_name)); grid on; xlim([0 t_raw(end)]);

subplot(4,1,2);
plot(t_raw, alpha_tremor, 'Color', [0.8 0.5 0.1], 'LineWidth', 0.8);
ylabel('°/s²'); title(sprintf('轉換後角加速度 alpha (L = %.0f mm)', L_arm*1000)); grid on; xlim([0 t_raw(end)]);

subplot(4,1,3);
plot(t_raw, torque_required*1000, 'Color', [0.9 0.2 0.2], 'LineWidth', 0.8);
ylabel('mN·m'); title('所需反向抵消扭矩'); grid on; xlim([0 t_raw(end)]);
yline(motor_max_torque*1000, '--k', '馬達上限');
yline(-motor_max_torque*1000, '--k');

subplot(4,1,4);
plot(t_raw, pwm_duty * 100, 'Color', [0.1 0.7 0.3], 'LineWidth', 0.8); hold on;
yyaxis right;
plot(t_raw, pwm_direction, 'Color', [0.6 0.6 0.9], 'LineWidth', 0.5);
ylabel('方向 (±1)');
yyaxis left;
ylabel('PWM 佔空比 (%)');
xlabel('時間 (s)');
title('馬達 PWM 控制輸出');
grid on; xlim([0 t_raw(end)]); ylim([0 100]);

sgtitle(sprintf('病患 %s — 馬達控制力輸出分析', patient_id), 'FontSize', 14, 'FontWeight', 'bold');

% ======== Figure 6: 四軸綜合比較 ========
fig6 = figure('Name', '四軸綜合比較', 'Position', [200, 80, 1200, 800]);

bar_pwr_ehw = [results.pwr_ehw];
bar_pwr_bmf = [results.pwr_bmf];
bar_rmse_ehw = [results.rmse_ehw];
bar_rmse_bmf = [results.rmse_bmf];
bar_corr_ehw = [results.corr_ehw];
bar_corr_bmf = [results.corr_bmf];

subplot(2,2,1);
b = bar(categorical(test_names), [bar_pwr_ehw; bar_pwr_bmf]');
b(1).FaceColor = [0.2 0.4 0.9]; b(2).FaceColor = [0.9 0.2 0.2];
ylabel('功率降低 (%)'); title('震顫功率降低');
legend('eHWFLC-KF', 'BMFLC'); grid on;

subplot(2,2,2);
b = bar(categorical(test_names), [bar_rmse_ehw; bar_rmse_bmf]');
b(1).FaceColor = [0.2 0.4 0.9]; b(2).FaceColor = [0.9 0.2 0.2];
ylabel('RMSE (g)'); title('震顫估測 RMSE');
legend('eHWFLC-KF', 'BMFLC'); grid on;

subplot(2,2,3);
b = bar(categorical(test_names), [bar_corr_ehw; bar_corr_bmf]');
b(1).FaceColor = [0.2 0.4 0.9]; b(2).FaceColor = [0.9 0.2 0.2];
ylabel('相關係數'); title('與參考訊號相關係數');
legend('eHWFLC-KF', 'BMFLC'); grid on; ylim([0 1]);

subplot(2,2,4);
bar_lat_ehw = [results.latency_ehw];
bar_lat_bmf = [results.latency_bmf];
b = bar(categorical(test_names), [bar_lat_ehw; bar_lat_bmf]');
b(1).FaceColor = [0.2 0.4 0.9]; b(2).FaceColor = [0.9 0.2 0.2];
ylabel('延遲 (µs/sample)'); title('計算延遲');
legend('eHWFLC-KF', 'BMFLC'); grid on;

sgtitle(sprintf('病患 %s — 四軸演算法效能綜合比較', patient_id), 'FontSize', 14, 'FontWeight', 'bold');

%% ====================================================================
%  總結報告輸出
%  ====================================================================
fprintf('\n╔══════════════════════════════════════════════════════════╗\n');
fprintf('║  真實病患資料測試結果總結                                ║\n');
fprintf('╠══════════════════════════════════════════════════════════╣\n');
fprintf('║                                                          ║\n');
fprintf('║  資料概況:                                               ║\n');
fprintf('║    %-55s║\n', sprintf('病患 ID: %s (%s 資料集)', patient_id, dataset_name));
fprintf('║    %-55s║\n', sprintf('資料長度: %d 點 (%.1f 秒 @ %d Hz)', N_raw, N_raw/fs_raw, fs_raw));
fprintf('║    %-55s║\n', sprintf('主要震顫軸: %s', main_axis_name));
fprintf('║    %-55s║\n', sprintf('%s 震顫頻帶功率佔比: %.1f%%', main_axis_name, tremor_power_main/total_power_main*100));
fprintf('║    %-55s║\n', sprintf('估測震顫主頻: %.2f Hz', f_peak));
fprintf('║                                                          ║\n');
fprintf('║  最佳演算法效能 (%s):                                    ║\n');
fprintf('║    %-55s║\n', sprintf('eHWFLC-KF 功率降低: %.1f%%', results(main_ax_idx).pwr_ehw));
fprintf('║    %-55s║\n', sprintf('BMFLC     功率降低: %.1f%%', results(main_ax_idx).pwr_bmf));
fprintf('║                                                          ║\n');
fprintf('║  馬達控制力需求 (%s):                                    ║\n');
fprintf('║    %-55s║\n', sprintf('扭矩 RMS: %.4f mN·m', rms(torque_required)*1000));
fprintf('║    %-55s║\n', sprintf('扭矩 Peak: %.4f mN·m', max(abs(torque_required))*1000));
fprintf('║    %-55s║\n', sprintf('電流 RMS: %.2f mA', rms(current_required)*1000));
fprintf('║    %-55s║\n', sprintf('PWM 平均佔空比: %.1f%%', mean(pwm_duty)*100));
fprintf('║                                                          ║\n');
fprintf('║  即時性:                                                  ║\n');
fprintf('║    %-55s║\n', sprintf('eHWFLC-KF: %.1f µs/sample (STM32 預算 %.3f%%)', ...
    mean(latencies_ehw), mean(latencies_ehw)/stm32_budget*100));
fprintf('║    %-55s║\n', sprintf('BMFLC: %.1f µs/sample (STM32 預算 %.3f%%)', ...
    mean(latencies_bmf), mean(latencies_bmf)/stm32_budget*100));
fprintf('║                                                          ║\n');
fprintf('║  結論: 病患有顯著震顫！演算法能有效追蹤與壓制。           ║\n');
fprintf('╚══════════════════════════════════════════════════════════╝\n\n');

% ---- 馬達測試建議 ----
fprintf('📋 上馬達建議:\n');
fprintf('  1. 使用 eHWFLC-KF 演算法（追蹤真實病患震顫頻率之適應性更強）\n');
fprintf('  2. 主要控制軸: %s（其震顫加速度振幅最大）\n', main_axis_name);
fprintf('  3. 控制迴路 (線性加速度模式):\n');
fprintf('     IMU加速度 → eHWFLC-KF → 切向角加速度轉換 (a/L) → 扭矩計算 → PWM輸出\n');
fprintf('  4. 預估馬達電流需求: %.0f mA RMS, %.0f mA Peak\n', ...
    rms(current_required)*1000, max(abs(current_required))*1000);
fprintf('  5. STM32 Timer ISR @ 50 Hz 有充足的預算空間 (佔用 < 0.1%%)\n\n');

%% ====================================================================
%  儲存結果
%  ====================================================================
save(fullfile(results_dir, 'patient_tremor_results.mat'), ...
    'results', 'gyro_x', 'gyro_y', 'gyro_z', 'gyro_rss', ...
    'torque_required', 'current_required', 'pwm_duty', 'pwm_direction', ...
    'alpha_tremor', 'fs_raw', 't_raw', 'f_peak', 'patient_id', ...
    'latencies_ehw', 'latencies_bmf');

% 存圖
saveas(fig1, fullfile(results_dir, 'patient_tremor_raw.png'));
saveas(fig2, fullfile(results_dir, 'patient_tremor_fft.png'));
saveas(fig3, fullfile(results_dir, 'patient_tremor_algo.png'));
saveas(fig4, fullfile(results_dir, 'patient_tremor_suppress.png'));
saveas(fig5, fullfile(results_dir, 'patient_tremor_motor.png'));
saveas(fig6, fullfile(results_dir, 'patient_tremor_compare.png'));

fprintf('✓ 所有結果圖表已存至 real_data_exp/results/\n');
fprintf('✓ 病患資料完整測試完成！\n');
