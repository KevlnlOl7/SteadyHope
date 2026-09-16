function plot_results(t, signal, tremor_true, voluntary_true, ...
    tremor_ehwflc, tremor_bmflc, freq_ehwflc, ...
    dbg_ehwflc, dbg_bmflc, true_freq, eval_idx)
% PLOT_RESULTS 繪製震顫估測演算法比較圖
%
%   共產生 4 張圖：
%     Figure 1: 時域比較（原始訊號 vs 估測震顫）
%     Figure 2: 震顫估測細節比較
%     Figure 3: 頻率追蹤（eHWFLC-KF）& 頻譜功率（BMFLC）
%     Figure 4: 收斂分析 & 誤差統計

    fs = 1 / (t(2) - t(1));
    
    % 顏色定義
    c_signal   = [0.5, 0.5, 0.5];    % 灰色
    c_true     = [0, 0, 0];           % 黑色
    c_ehwflc   = [0.2, 0.4, 0.8];    % 藍色
    c_bmflc    = [0.8, 0.2, 0.2];    % 紅色
    c_vol      = [0.2, 0.7, 0.3];    % 綠色
    
    %% ============================================================
    %  Figure 1: 時域總覽
    %  ============================================================
    figure('Name', '時域比較', 'Position', [50, 400, 1200, 700]);
    
    % 1.1 原始訊號分解
    subplot(4, 1, 1);
    plot(t, signal, 'Color', c_signal, 'LineWidth', 0.5); hold on;
    plot(t, voluntary_true, 'Color', c_vol, 'LineWidth', 1.5);
    plot(t, tremor_true, 'Color', c_true, 'LineWidth', 1.2);
    xlabel('時間 (s)'); ylabel('角速度 (°/s)');
    title('原始訊號分解');
    legend('混合訊號 (IMU)', '自主動作 (真實)', '震顫 (真實)', ...
        'Location', 'northeast');
    grid on; xlim([0, t(end)]);
    
    % 1.2 eHWFLC-KF 結果
    subplot(4, 1, 2);
    plot(t, tremor_true, 'Color', c_true, 'LineWidth', 1.2); hold on;
    plot(t, tremor_ehwflc, 'Color', c_ehwflc, 'LineWidth', 1.2);
    xlabel('時間 (s)'); ylabel('角速度 (°/s)');
    title('eHWFLC-KF 震顫估測');
    legend('真實震顫', 'eHWFLC-KF 估測', 'Location', 'northeast');
    grid on; xlim([0, t(end)]);
    
    % 1.3 BMFLC 結果
    subplot(4, 1, 3);
    plot(t, tremor_true, 'Color', c_true, 'LineWidth', 1.2); hold on;
    plot(t, tremor_bmflc, 'Color', c_bmflc, 'LineWidth', 1.2);
    xlabel('時間 (s)'); ylabel('角速度 (°/s)');
    title('BMFLC 震顫估測');
    legend('真實震顫', 'BMFLC 估測', 'Location', 'northeast');
    grid on; xlim([0, t(end)]);
    
    % 1.4 估測誤差比較
    subplot(4, 1, 4);
    err_ehwflc = tremor_true - tremor_ehwflc;
    err_bmflc  = tremor_true - tremor_bmflc;
    plot(t, err_ehwflc, 'Color', c_ehwflc, 'LineWidth', 1); hold on;
    plot(t, err_bmflc, 'Color', c_bmflc, 'LineWidth', 1);
    xlabel('時間 (s)'); ylabel('誤差 (°/s)');
    title('估測誤差比較');
    legend('eHWFLC-KF 誤差', 'BMFLC 誤差', 'Location', 'northeast');
    grid on; xlim([0, t(end)]);
    
    sgtitle('震顫估測演算法比較 — 時域', 'FontSize', 14, 'FontWeight', 'bold');
    
    %% ============================================================
    %  Figure 2: 震顫抑制效果 (放大視圖)
    %  ============================================================
    figure('Name', '震顫抑制效果', 'Position', [100, 350, 1200, 500]);
    
    % 選取穩態區間 (3-5 秒)
    zoom_idx = find(t >= 3 & t <= 5);
    
    subplot(2, 1, 1);
    plot(t(zoom_idx), signal(zoom_idx), 'Color', c_signal, 'LineWidth', 0.8); hold on;
    plot(t(zoom_idx), voluntary_true(zoom_idx), 'Color', c_vol, 'LineWidth', 2);
    
    % 模擬抑制後訊號 = 原始 - 估測震顫
    suppressed_ehwflc = signal(zoom_idx) - tremor_ehwflc(zoom_idx);
    suppressed_bmflc  = signal(zoom_idx) - tremor_bmflc(zoom_idx);
    
    plot(t(zoom_idx), suppressed_ehwflc, 'Color', c_ehwflc, 'LineWidth', 1.5);
    plot(t(zoom_idx), suppressed_bmflc, 'Color', c_bmflc, 'LineWidth', 1.5);
    xlabel('時間 (s)'); ylabel('角速度 (°/s)');
    title('震顫抑制效果 (3–5 秒放大)');
    legend('原始訊號', '真實自主動作', ...
        'eHWFLC-KF 抑制後', 'BMFLC 抑制後', 'Location', 'northeast');
    grid on;
    
    % 頻譜比較
    subplot(2, 1, 2);
    N_fft = 2^nextpow2(length(zoom_idx));
    f_axis = (0:N_fft/2-1) * fs / N_fft;
    
    S_orig = abs(fft(signal(zoom_idx) - mean(signal(zoom_idx)), N_fft));
    S_ehwflc = abs(fft(suppressed_ehwflc - mean(suppressed_ehwflc), N_fft));
    S_bmflc  = abs(fft(suppressed_bmflc - mean(suppressed_bmflc), N_fft));
    
    S_orig   = S_orig(1:N_fft/2);
    S_ehwflc = S_ehwflc(1:N_fft/2);
    S_bmflc  = S_bmflc(1:N_fft/2);
    
    plot(f_axis, 20*log10(S_orig + eps), 'Color', c_signal, 'LineWidth', 1); hold on;
    plot(f_axis, 20*log10(S_ehwflc + eps), 'Color', c_ehwflc, 'LineWidth', 1.5);
    plot(f_axis, 20*log10(S_bmflc + eps), 'Color', c_bmflc, 'LineWidth', 1.5);
    xlabel('頻率 (Hz)'); ylabel('振幅 (dB)');
    title('抑制前後頻譜比較');
    legend('抑制前', 'eHWFLC-KF 抑制後', 'BMFLC 抑制後', 'Location', 'northeast');
    grid on; xlim([0, 25]);
    
    % 標記震顫頻率
    xline(5, '--k', '5 Hz', 'LineWidth', 0.8);
    xline(10, '--k', '10 Hz', 'LineWidth', 0.8);
    xline(15, '--k', '15 Hz', 'LineWidth', 0.8);
    
    sgtitle('震顫抑制效果分析', 'FontSize', 14, 'FontWeight', 'bold');
    
    %% ============================================================
    %  Figure 3: 頻率追蹤 & 頻譜功率
    %  ============================================================
    figure('Name', '頻率分析', 'Position', [150, 300, 1200, 500]);
    
    % 3.1 eHWFLC-KF 頻率追蹤
    subplot(2, 1, 1);
    plot(t, true_freq, 'Color', c_true, 'LineWidth', 1.5); hold on;
    plot(t, freq_ehwflc, 'Color', c_ehwflc, 'LineWidth', 1.2);
    xlabel('時間 (s)'); ylabel('頻率 (Hz)');
    title('eHWFLC-KF 基頻追蹤');
    legend('真實基頻', '估測基頻', 'Location', 'northeast');
    grid on; xlim([0, t(end)]);
    ylim([3, 8]);
    
    % 3.2 BMFLC 頻譜功率分佈
    subplot(2, 1, 2);
    freqs = dbg_bmflc.freqs;
    spectral = dbg_bmflc.spectral_power;
    imagesc(t, freqs, 10*log10(spectral + eps));
    axis xy; colorbar;
    xlabel('時間 (s)'); ylabel('頻率 (Hz)');
    title('BMFLC 各頻率分量功率 (dB)');
    colormap(hot);
    
    sgtitle('頻率分析', 'FontSize', 14, 'FontWeight', 'bold');
    
    %% ============================================================
    %  Figure 4: 收斂分析
    %  ============================================================
    figure('Name', '收斂分析', 'Position', [200, 250, 1200, 600]);
    
    % 4.1 累積 RMSE
    subplot(2, 2, 1);
    cum_rmse_ehwflc = sqrt(cumsum((tremor_true - tremor_ehwflc).^2) ./ (1:length(t)));
    cum_rmse_bmflc  = sqrt(cumsum((tremor_true - tremor_bmflc).^2) ./ (1:length(t)));
    plot(t, cum_rmse_ehwflc, 'Color', c_ehwflc, 'LineWidth', 1.5); hold on;
    plot(t, cum_rmse_bmflc, 'Color', c_bmflc, 'LineWidth', 1.5);
    xlabel('時間 (s)'); ylabel('累積 RMSE (°/s)');
    title('收斂曲線');
    legend('eHWFLC-KF', 'BMFLC', 'Location', 'northeast');
    grid on; xlim([0, t(end)]);
    
    % 4.2 Kalman 增益範數
    subplot(2, 2, 2);
    plot(t, dbg_ehwflc.kalman_gain_norm, 'Color', c_ehwflc, 'LineWidth', 1);
    xlabel('時間 (s)'); ylabel('||K_k||');
    title('eHWFLC-KF Kalman 增益範數');
    grid on; xlim([0, t(end)]);
    
    % 4.3 誤差直方圖
    subplot(2, 2, 3);
    histogram(err_ehwflc(eval_idx), 50, 'FaceColor', c_ehwflc, ...
        'FaceAlpha', 0.6, 'EdgeAlpha', 0.3); hold on;
    histogram(err_bmflc(eval_idx), 50, 'FaceColor', c_bmflc, ...
        'FaceAlpha', 0.6, 'EdgeAlpha', 0.3);
    xlabel('估測誤差 (°/s)'); ylabel('次數');
    title('穩態誤差分佈 (去除暫態)');
    legend(sprintf('eHWFLC-KF (σ=%.3f)', std(err_ehwflc(eval_idx))), ...
           sprintf('BMFLC (σ=%.3f)', std(err_bmflc(eval_idx))));
    grid on;
    
    % 4.4 滑動窗口功率降低
    subplot(2, 2, 4);
    win_size = fs * 1;  % 1 秒窗口
    n_windows = floor(length(eval_idx) / win_size);
    pwr_red_win_ehwflc = zeros(1, n_windows);
    pwr_red_win_bmflc = zeros(1, n_windows);
    t_windows = zeros(1, n_windows);
    
    for w = 1:n_windows
        w_idx = eval_idx((w-1)*win_size+1 : w*win_size);
        [pwr_red_win_ehwflc(w), ~, ~] = compute_tremor_power(...
            tremor_true(w_idx), tremor_ehwflc(w_idx), ...
            voluntary_true(w_idx), signal(w_idx));
        [pwr_red_win_bmflc(w), ~, ~] = compute_tremor_power(...
            tremor_true(w_idx), tremor_bmflc(w_idx), ...
            voluntary_true(w_idx), signal(w_idx));
        t_windows(w) = t(w_idx(round(win_size/2)));
    end
    
    bar_data = [pwr_red_win_ehwflc; pwr_red_win_bmflc]';
    b = bar(t_windows, bar_data, 'grouped');
    b(1).FaceColor = c_ehwflc;
    b(2).FaceColor = c_bmflc;
    xlabel('時間 (s)'); ylabel('震顫功率降低 (%)');
    title('滑動窗口震顫功率降低 (1秒窗口)');
    legend('eHWFLC-KF', 'BMFLC', 'Location', 'southeast');
    grid on; ylim([0, 100]);
    
    sgtitle('收斂與效能分析', 'FontSize', 14, 'FontWeight', 'bold');
end
