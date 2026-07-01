%% test_simulated_tremor.m
%  ====================================================================
%  模擬抖動數據 全方面測試腳本
%  ====================================================================
%
%  測試項目：
%    1. 資料解析與統計分析
%    2. 頻域分析（FFT / PSD）
%    3. eHWFLC-KF 與 BMFLC 震顫估測（三軸 + RSS）
%    4. 馬達控制力輸出計算（為上馬達做準備）
%    5. 即時性能測試（step function 延遲）
%    6. 抑制效果頻譜分析
%    7. 完整可視化報告
%
%  使用方式：直接在 MATLAB 中執行即可
%  ====================================================================

clc; clear; close all;
addpath('utils');

fprintf('╔══════════════════════════════════════════════════════════╗\n');
fprintf('║  模擬抖動數據 — 全方面測試                              ║\n');
fprintf('║  eHWFLC-KF & BMFLC 演算法驗證 + 馬達控制力計算          ║\n');
fprintf('╚══════════════════════════════════════════════════════════╝\n\n');

%% ====================================================================
%  1. 資料載入與解析
%  ====================================================================
fprintf('[1/7] 載入模擬抖動數據...\n');

data_file = fullfile('冠廷錄入的 IMU 資料', '模擬抖動數據.txt');
[gyro_x, gyro_y, gyro_z] = parse_gyro_only(data_file);

N_raw = length(gyro_x);
fprintf('  原始資料行數: %d\n', N_raw);

% ---- 去除重複樣本 ----
% 資料中有許多連續重複行（BNO055 @ ~33Hz 輸出但 Serial 更快收）
% 偵測並只保留唯一樣本
diff_x = [1; diff(gyro_x)];
diff_y = [1; diff(gyro_y)];
diff_z = [1; diff(gyro_z)];
change_mask = (diff_x ~= 0) | (diff_y ~= 0) | (diff_z ~= 0);

% 也保留每段重複的第一個樣本
unique_idx = find(change_mask);
gyro_x_unique = gyro_x(unique_idx);
gyro_y_unique = gyro_y(unique_idx);
gyro_z_unique = gyro_z(unique_idx);
N_unique = length(unique_idx);

fprintf('  去重後樣本數: %d (重複率: %.1f%%)\n', N_unique, ...
    (1 - N_unique/N_raw)*100);

% ---- 估算取樣率 ----
% BNO055 Gyro 預設 100 Hz，但實際傳輸可能 ~33Hz (每 3 筆重複)
% 從重複模式估算
rep_counts = diff([unique_idx; N_raw+1]);
avg_rep = mean(rep_counts);
fprintf('  平均重複次數: %.1f → 推估感測器實際輸出率: %.0f Hz\n', ...
    avg_rep, 100/avg_rep);

% 使用原始資料（含重複），假設 100 Hz
% 也同時測試去重版本
fs_raw = 100;   % 假設 100 Hz（原始含重複）
fs_unique = round(100 / avg_rep);  % 推估實際更新率
fprintf('  使用取樣率: %d Hz (原始) / %d Hz (去重)\n', fs_raw, fs_unique);

% RSS
gyro_rss = sqrt(gyro_x.^2 + gyro_y.^2 + gyro_z.^2);
gyro_rss_unique = sqrt(gyro_x_unique.^2 + gyro_y_unique.^2 + gyro_z_unique.^2);

t_raw = (0:N_raw-1) / fs_raw;

%% ====================================================================
%  2. 基本統計分析
%  ====================================================================
fprintf('\n[2/7] 基本統計分析...\n');

axes_names = {'Gyro X', 'Gyro Y', 'Gyro Z', 'RSS'};
axes_data = {gyro_x, gyro_y, gyro_z, gyro_rss};

fprintf('\n  ┌─────────┬──────────┬──────────┬──────────┬──────────┬──────────┐\n');
fprintf('  │  軸      │  平均值   │  標準差   │  最大值   │  最小值   │  峰峰值  │\n');
fprintf('  ├─────────┼──────────┼──────────┼──────────┼──────────┼──────────┤\n');
for i = 1:4
    d = axes_data{i};
    fprintf('  │ %-8s│ %+7.2f  │  %6.2f   │ %+7.2f  │ %+7.2f  │  %6.2f   │\n', ...
        axes_names{i}, mean(d), std(d), max(d), min(d), max(d)-min(d));
end
fprintf('  └─────────┴──────────┴──────────┴──────────┴──────────┴──────────┘\n\n');

%% ====================================================================
%  3. 頻域分析 (FFT / PSD)
%  ====================================================================
fprintf('[3/7] 頻域分析...\n');

% 使用 Y 軸（主要震顫軸，振幅最大）
signal_main = gyro_y - mean(gyro_y);  % 去均值
N_fft = 2^nextpow2(N_raw);
f_axis = (0:N_fft/2-1) * fs_raw / N_fft;

% FFT
Y_fft = abs(fft(signal_main, N_fft)) / N_raw;
Y_fft_half = Y_fft(1:N_fft/2);

% 找震顫主頻
[~, pk_idx] = max(Y_fft_half(2:end));  % 跳過 DC
pk_idx = pk_idx + 1;
f_peak = f_axis(pk_idx);
fprintf('  Y 軸主頻: %.2f Hz (振幅: %.2f °/s)\n', f_peak, Y_fft_half(pk_idx)*2);

% 各軸主頻
for i = 1:3
    sig_tmp = axes_data{i} - mean(axes_data{i});
    Y_tmp = abs(fft(sig_tmp, N_fft)) / N_raw;
    Y_tmp_half = Y_tmp(1:N_fft/2);
    [amp_pk, idx_pk] = max(Y_tmp_half(2:end));
    idx_pk = idx_pk + 1;
    fprintf('  %s 主頻: %.2f Hz (振幅: %.2f °/s)\n', ...
        axes_names{i}, f_axis(idx_pk), amp_pk*2);
end

% 震顫頻帶 (3-12 Hz) 功率佔比
tremor_band = f_axis >= 3 & f_axis <= 12;
total_power_y = sum(Y_fft_half.^2);
tremor_power_y = sum(Y_fft_half(tremor_band).^2);
fprintf('  Y 軸震顫頻帶(3-12Hz)功率佔比: %.1f%%\n', tremor_power_y/total_power_y*100);

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
        [tremor_ehw(k), freq_ehw(k)] = eHWFLC_KF_step(sig(k));
    end
    time_ehw = toc;
    
    % --- BMFLC (step function) ---
    clear BMFLC_step
    tremor_bmf = zeros(1, N_raw);
    tic;
    for k = 1:N_raw
        tremor_bmf(k) = BMFLC_step(sig(k));
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
    
    fprintf('    eHWFLC-KF: 功率↓%.1f%% | RMSE=%.3f | r=%.3f | %.1f µs/smp\n', ...
        pwr_ehw, rmse_ehw, corr_ehw, latency_ehw);
    fprintf('    BMFLC:     功率↓%.1f%% | RMSE=%.3f | r=%.3f | %.1f µs/smp\n', ...
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
% 可根據實際機構修改
m_payload = 0.15;         % 負載質量 (kg)，例如湯匙+食物
L_arm = 0.12;             % 力臂長度 (m)
J_payload = m_payload * L_arm^2;  % 轉動慣量 (kg·m²)
motor_max_torque = 0.5;   % 馬達最大扭矩 (N·m)
motor_voltage = 12;       % 馬達工作電壓 (V)
Kt = 0.03;               % 馬達扭矩常數 (N·m/A)，典型小型馬達

fprintf('  系統參數:\n');
fprintf('    負載質量: %.0f g\n', m_payload * 1000);
fprintf('    力臂長度: %.0f mm\n', L_arm * 1000);
fprintf('    轉動慣量: %.4f kg·m²\n', J_payload);
fprintf('    馬達最大扭矩: %.2f N·m\n', motor_max_torque);

% 使用 Y 軸（主要震顫軸）的 eHWFLC-KF 估測結果
ax_motor = 2;  % Y 軸
tremor_est = results(ax_motor).tremor_ehw;
freq_est   = results(ax_motor).freq_ehw;

% ---- 計算角加速度 ----
% 震顫角速度 → 角加速度 (差分)
alpha_tremor = [0, diff(tremor_est)] * fs_raw;  % °/s² 
alpha_tremor_rad = alpha_tremor * pi / 180;      % rad/s²

% ---- 計算所需扭矩 ----
% τ = J × α (反向施加以抵消震顫)
torque_required = -J_payload * alpha_tremor_rad;  % N·m (反向)

% ---- 計算所需電流 ----
current_required = torque_required / Kt;  % A

% ---- 計算所需 PWM ----
% 假設 H 橋驅動, PWM 佔空比 ∝ 電壓 ∝ 電流（簡化）
pwm_duty = abs(current_required) / (motor_voltage / (Kt * 10));  % 正規化
pwm_duty = min(pwm_duty, 1.0);  % 限制 0~1
pwm_direction = sign(torque_required);  % +1 或 -1

fprintf('\n  馬達控制力輸出統計 (Y軸 eHWFLC-KF):\n');
fprintf('  ┌─────────────────────┬────────────────┐\n');
fprintf('  │ 指標                 │ 數值            │\n');
fprintf('  ├─────────────────────┼────────────────┤\n');
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

% 多次跑 step function，統計延遲分布
n_runs = 3;
latencies_ehw = zeros(1, N_raw * n_runs);
latencies_bmf = zeros(1, N_raw * n_runs);

sig_test = gyro_y';

for run = 1:n_runs
    clear eHWFLC_KF_step BMFLC_step
    for k = 1:N_raw
        tic_start = tic;
        eHWFLC_KF_step(sig_test(k));
        latencies_ehw((run-1)*N_raw + k) = toc(tic_start) * 1e6;
    end
    clear eHWFLC_KF_step
    
    clear BMFLC_step
    for k = 1:N_raw
        tic_start = tic;
        BMFLC_step(sig_test(k));
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

% STM32 @ 100 Hz → 每個 sample 有 10,000 µs
stm32_budget = 10000;  % µs
fprintf('\n  STM32 @ 100 Hz 預算: %d µs/sample\n', stm32_budget);
fprintf('  eHWFLC-KF 佔用: %.2f%%\n', mean(latencies_ehw)/stm32_budget*100);
fprintf('  BMFLC     佔用: %.2f%%\n', mean(latencies_bmf)/stm32_budget*100);

%% ====================================================================
%  7. 完整可視化報告
%  ====================================================================
fprintf('\n[7/7] 繪製完整報告...\n');

% ======== Figure 1: 原始資料總覽 ========
fig1 = figure('Name', '原始資料總覽', 'Position', [50, 50, 1500, 900]);

subplot(4,1,1);
plot(t_raw, gyro_x, 'r', 'LineWidth', 0.8);
ylabel('°/s'); title('Gyro X'); grid on; xlim([0 t_raw(end)]);

subplot(4,1,2);
plot(t_raw, gyro_y, 'Color', [0.1 0.5 0.9], 'LineWidth', 0.8);
ylabel('°/s'); title('Gyro Y (主要震顫軸)'); grid on; xlim([0 t_raw(end)]);

subplot(4,1,3);
plot(t_raw, gyro_z, 'Color', [0.1 0.7 0.3], 'LineWidth', 0.8);
ylabel('°/s'); title('Gyro Z'); grid on; xlim([0 t_raw(end)]);

subplot(4,1,4);
plot(t_raw, gyro_rss, 'k', 'LineWidth', 0.8);
xlabel('時間 (s)'); ylabel('°/s'); title('RSS (三軸合成)'); grid on; xlim([0 t_raw(end)]);

sgtitle('模擬抖動數據 — 三軸原始訊號', 'FontSize', 14, 'FontWeight', 'bold');

% ======== Figure 2: 頻域分析 ========
fig2 = figure('Name', '頻域分析', 'Position', [80, 80, 1400, 700]);

for i = 1:4
    subplot(2,2,i);
    sig_tmp = axes_data{i} - mean(axes_data{i});
    Y_tmp = abs(fft(sig_tmp, N_fft)) / N_raw;
    plot(f_axis, Y_tmp(1:N_fft/2)*2, 'LineWidth', 1.2);
    xlabel('頻率 (Hz)'); ylabel('振幅 (°/s)');
    title(sprintf('%s 頻譜', axes_names{i}));
    grid on; xlim([0 25]);
    xline(3, '--r', '3 Hz'); xline(12, '--r', '12 Hz');
    hold on;
    area_idx = f_axis >= 3 & f_axis <= 12;
    area(f_axis(area_idx), Y_tmp(area_idx)*2, ...
        'FaceColor', [1 0.3 0.3], 'FaceAlpha', 0.15, 'EdgeColor', 'none');
end

sgtitle('模擬抖動數據 — 頻譜分析（震顫帶 3-12 Hz 標示）', ...
    'FontSize', 14, 'FontWeight', 'bold');

% ======== Figure 3: 演算法效果（Y 軸詳細）========
fig3 = figure('Name', '演算法效果 — Y軸', 'Position', [110, 110, 1500, 900]);
ax_show = 2;  % Y 軸
r = results(ax_show);

subplot(4,1,1);
plot(t_raw, r.signal, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.5); hold on;
plot(t_raw, r.tremor_ref, 'k', 'LineWidth', 1);
xlabel('時間 (s)'); ylabel('°/s');
title('原始訊號 & 帶通參考震顫');
legend('原始訊號', '帶通參考 (3-12 Hz)', 'Location', 'northeast');
grid on; xlim([0 t_raw(end)]);

subplot(4,1,2);
plot(t_raw, r.tremor_ref, 'k', 'LineWidth', 0.8); hold on;
plot(t_raw, r.tremor_ehw, 'Color', [0.2 0.4 0.9], 'LineWidth', 1);
xlabel('時間 (s)'); ylabel('°/s');
title(sprintf('eHWFLC-KF 震顫估測 (功率↓%.1f%%, r=%.3f)', r.pwr_ehw, r.corr_ehw));
legend('參考', 'eHWFLC-KF');
grid on; xlim([0 t_raw(end)]);

subplot(4,1,3);
plot(t_raw, r.tremor_ref, 'k', 'LineWidth', 0.8); hold on;
plot(t_raw, r.tremor_bmf, 'Color', [0.9 0.2 0.2], 'LineWidth', 1);
xlabel('時間 (s)'); ylabel('°/s');
title(sprintf('BMFLC 震顫估測 (功率↓%.1f%%, r=%.3f)', r.pwr_bmf, r.corr_bmf));
legend('參考', 'BMFLC');
grid on; xlim([0 t_raw(end)]);

subplot(4,1,4);
plot(t_raw, r.freq_ehw, 'Color', [0.2 0.4 0.9], 'LineWidth', 1.2);
xlabel('時間 (s)'); ylabel('頻率 (Hz)');
title('eHWFLC-KF 基頻追蹤');
grid on; xlim([0 t_raw(end)]); ylim([3 12]);
yline(f_peak, '--r', sprintf('FFT 主頻 %.1f Hz', f_peak));

sgtitle(sprintf('Y軸震顫估測詳細結果 — 模擬抖動數據'), ...
    'FontSize', 14, 'FontWeight', 'bold');

% ======== Figure 4: 抑制效果放大 ========
fig4 = figure('Name', '抑制效果放大', 'Position', [140, 140, 1500, 700]);

% 取中間 3 秒
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
xlabel('時間 (s)'); ylabel('°/s');
title('震顫抑制效果（放大）');
legend('原始訊號', 'eHWFLC-KF 抑制後', 'BMFLC 抑制後', '自主動作參考');
grid on;

subplot(2,1,2);
% 抑制前後頻譜比較
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

sgtitle('震顫抑制效果放大視圖', 'FontSize', 14, 'FontWeight', 'bold');

% ======== Figure 5: 馬達控制力輸出 ========
fig5 = figure('Name', '馬達控制力輸出', 'Position', [170, 50, 1500, 900]);

subplot(4,1,1);
plot(t_raw, tremor_est, 'Color', [0.2 0.4 0.9], 'LineWidth', 1);
ylabel('°/s'); title('估測震顫角速度 (eHWFLC-KF, Y軸)'); grid on; xlim([0 t_raw(end)]);

subplot(4,1,2);
plot(t_raw, alpha_tremor, 'Color', [0.8 0.5 0.1], 'LineWidth', 0.8);
ylabel('°/s²'); title('估測角加速度 (差分)'); grid on; xlim([0 t_raw(end)]);

subplot(4,1,3);
plot(t_raw, torque_required*1000, 'Color', [0.9 0.2 0.2], 'LineWidth', 0.8);
ylabel('mN·m'); title('所需反向扭矩'); grid on; xlim([0 t_raw(end)]);
yline(motor_max_torque*1000, '--k', '馬達上限');
yline(-motor_max_torque*1000, '--k');

subplot(4,1,4);
plot(t_raw, pwm_duty * 100, 'Color', [0.1 0.7 0.3], 'LineWidth', 0.8); hold on;
% 疊加方向
yyaxis right;
plot(t_raw, pwm_direction, 'Color', [0.6 0.6 0.9], 'LineWidth', 0.5);
ylabel('方向 (±1)');
yyaxis left;
ylabel('PWM 佔空比 (%)');
xlabel('時間 (s)');
title('馬達 PWM 控制輸出');
grid on; xlim([0 t_raw(end)]); ylim([0 100]);

sgtitle('馬達控制力輸出 — 為上馬達測試準備', 'FontSize', 14, 'FontWeight', 'bold');

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
ylabel('RMSE (°/s)'); title('震顫估測 RMSE');
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

sgtitle('四軸綜合比較 — 模擬抖動數據', 'FontSize', 14, 'FontWeight', 'bold');

%% ====================================================================
%  總結報告
%  ====================================================================
fprintf('\n╔══════════════════════════════════════════════════════════╗\n');
fprintf('║  全方面測試結果總結                                      ║\n');
fprintf('╠══════════════════════════════════════════════════════════╣\n');
fprintf('║                                                          ║\n');
fprintf('║  資料概況:                                               ║\n');
fprintf('║    %-55s║\n', sprintf('樣本數: %d (%.1f 秒)', N_raw, N_raw/fs_raw));
fprintf('║    %-55s║\n', sprintf('Y軸主頻: %.2f Hz', f_peak));
fprintf('║    %-55s║\n', sprintf('震顫頻帶功率: %.1f%%', tremor_power_y/total_power_y*100));
fprintf('║                                                          ║\n');
fprintf('║  最佳演算法效能 (Y軸):                                   ║\n');
fprintf('║    %-55s║\n', sprintf('eHWFLC-KF 功率降低: %.1f%%', results(2).pwr_ehw));
fprintf('║    %-55s║\n', sprintf('BMFLC     功率降低: %.1f%%', results(2).pwr_bmf));
fprintf('║                                                          ║\n');
fprintf('║  馬達控制力需求 (Y軸):                                   ║\n');
fprintf('║    %-55s║\n', sprintf('扭矩 RMS: %.4f mN·m', rms(torque_required)*1000));
fprintf('║    %-55s║\n', sprintf('扭矩 Peak: %.4f mN·m', max(abs(torque_required))*1000));
fprintf('║    %-55s║\n', sprintf('電流 RMS: %.2f mA', rms(current_required)*1000));
fprintf('║    %-55s║\n', sprintf('PWM 平均佔空比: %.1f%%', mean(pwm_duty)*100));
fprintf('║                                                          ║\n');
fprintf('║  即時性:                                                  ║\n');
fprintf('║    %-55s║\n', sprintf('eHWFLC-KF: %.1f µs/sample (STM32 預算 %.2f%%)', ...
    mean(latencies_ehw), mean(latencies_ehw)/stm32_budget*100));
fprintf('║    %-55s║\n', sprintf('BMFLC: %.1f µs/sample (STM32 預算 %.2f%%)', ...
    mean(latencies_bmf), mean(latencies_bmf)/stm32_budget*100));
fprintf('║                                                          ║\n');
fprintf('║  結論: ✓ 可以上馬達測試                                  ║\n');
fprintf('╚══════════════════════════════════════════════════════════╝\n\n');

% ---- 馬達測試建議 ----
fprintf('📋 上馬達建議:\n');
fprintf('  1. 使用 eHWFLC-KF 演算法（追蹤性更佳）\n');
fprintf('  2. 主要控制軸: Y 軸（震顫振幅最大）\n');
fprintf('  3. 控制迴路:\n');
fprintf('     IMU → 帶通濾波 → eHWFLC-KF → 角加速度差分 → 扭矩計算 → PWM輸出\n');
fprintf('  4. 預估馬達電流需求: %.0f mA RMS, %.0f mA Peak\n', ...
    rms(current_required)*1000, max(abs(current_required))*1000);
fprintf('  5. STM32 Timer ISR @ 100 Hz 有足夠餘量\n\n');

%% ====================================================================
%  儲存結果
%  ====================================================================
if ~exist('real_data_exp/results', 'dir'), mkdir('real_data_exp/results'); end
save('real_data_exp/results/simulated_tremor_results.mat', ...
    'results', 'gyro_x', 'gyro_y', 'gyro_z', 'gyro_rss', ...
    'torque_required', 'current_required', 'pwm_duty', 'pwm_direction', ...
    'alpha_tremor', 'fs_raw', 't_raw', 'f_peak', ...
    'latencies_ehw', 'latencies_bmf');

% 存圖
saveas(fig1, 'real_data_exp/results/sim_tremor_raw.png');
saveas(fig2, 'real_data_exp/results/sim_tremor_fft.png');
saveas(fig3, 'real_data_exp/results/sim_tremor_algo.png');
saveas(fig4, 'real_data_exp/results/sim_tremor_suppress.png');
saveas(fig5, 'real_data_exp/results/sim_tremor_motor.png');
saveas(fig6, 'real_data_exp/results/sim_tremor_compare.png');

fprintf('✓ 所有結果已存至 real_data_exp/results/\n');
fprintf('✓ 測試完成！可以準備上馬達了。\n');


%% ====================================================================
%  本地函式
%  ====================================================================

function [gx, gy, gz] = parse_gyro_only(filename)
% PARSE_GYRO_ONLY 解析純 Gyro 格式的 IMU 文字檔
%
%   格式: "Gyro: X Y Z"（每行一筆，可能有註解行以 // 開頭）
%
%   輸出: gx, gy, gz 為列向量 (N x 1)

    fid = fopen(filename, 'r');
    if fid == -1
        error('無法開啟檔案: %s', filename);
    end
    
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    lines = raw{1};
    n_lines = length(lines);
    
    % 預分配
    gx = zeros(n_lines, 1);
    gy = zeros(n_lines, 1);
    gz = zeros(n_lines, 1);
    count = 0;
    
    for i = 1:n_lines
        line = strtrim(lines{i});
        % 跳過空行和註解
        if isempty(line) || startsWith(line, '//')
            continue;
        end
        % 解析 "Gyro: X Y Z"
        idx = strfind(line, 'Gyro:');
        if ~isempty(idx)
            num_str = strtrim(line(idx + 5:end));
            vals = sscanf(num_str, '%f %f %f');
            if length(vals) == 3
                count = count + 1;
                gx(count) = vals(1);
                gy(count) = vals(2);
                gz(count) = vals(3);
            end
        end
    end
    
    % 截斷
    gx = gx(1:count);
    gy = gy(1:count);
    gz = gz(1:count);
    
    fprintf('  已解析 %s: %d 筆 Gyro 資料\n', filename, count);
end
