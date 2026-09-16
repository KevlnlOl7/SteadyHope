function [tremor_est, w_final, debug] = BMFLC(signal, fs, varargin)
% BMFLC 頻帶限制多頻傅立葉線性組合器
%
%   [tremor_est, w_final, debug] = BMFLC(signal, fs)
%   [tremor_est, w_final, debug] = BMFLC(signal, fs, 'Name', Value, ...)
%
%   此函式實作論文中表現第二名的震顫估測演算法。
%   架構為兩階段：
%     1) 低通濾波分離自主動作
%     2) 固定多頻 LMS 自適應濾波
%
%   優點：不需要頻率追蹤，架構簡單、數值穩定。
%   缺點：需要預設頻帶範圍；頻率解析度受 delta_f 限制。
%
%   參考文獻:
%     Zhou et al., "Real-Time Performance Assessment of High-Order Tremor
%     Estimators Used in a Wearable Tremor Suppression Device," IEEE TNSRE, 2022.
%     Veluvolu & Ang, "Estimation of Physiological Tremor from Accelerometers
%     for Real-Time Applications," Sensors, 2011.
%
%   輸入:
%     signal - 輸入訊號 (1×N 或 N×1), 模擬陀螺儀角速度 (°/s)
%     fs     - 取樣頻率 (Hz)
%
%   名稱-值對:
%     'f_low'     - 頻帶下限 (Hz), 預設 3
%     'f_high'    - 頻帶上限 (Hz), 預設 12
%     'delta_f'   - 頻率間距 (Hz), 預設 0.5
%     'mu'        - NLMS 正規化學習率 (0~1), 預設 0.5
%                   (使用 Normalized LMS，步長自動除以 ||x_k||^2)
%     'fc_lp'     - 低通截止頻率 (Hz), 預設 2
%     'lp_order'  - 低通濾波器階數, 預設 4
%
%   輸出:
%     tremor_est - 估測震顫分量 (1×N)
%     w_final    - 最終權重向量 (2n×1)
%     debug      - 除錯結構體

    % === 輸入解析 ===
    signal = signal(:)';  % 確保為行向量
    N = length(signal);
    dt = 1 / fs;
    
    p = inputParser;
    addParameter(p, 'f_low', 3);
    addParameter(p, 'f_high', 12);
    addParameter(p, 'delta_f', 0.5);
    addParameter(p, 'mu', 0.5);
    addParameter(p, 'fc_lp', 2);
    addParameter(p, 'lp_order', 4);
    parse(p, varargin{:});
    
    f_low    = p.Results.f_low;
    f_high   = p.Results.f_high;
    delta_f  = p.Results.delta_f;
    mu       = p.Results.mu;
    fc_lp    = p.Results.fc_lp;
    lp_order = p.Results.lp_order;
    
    % 頻率集合
    freqs = f_low:delta_f:f_high;
    n_freq = length(freqs);
    omega = 2 * pi * freqs;  % 角頻率 (rad/s)
    
    dim = 2 * n_freq;  % 權重維度 (sin + cos for each freq)
    
    fprintf('BMFLC 初始化: %d 個頻率 (%.1f–%.1f Hz), 狀態維度 = %d\n', ...
        n_freq, f_low, f_high, dim);
    
    % === 第一階段：低通濾波分離自主動作 ===
    voluntary_est = butter_lowpass(signal, fc_lp, fs, lp_order);
    residual = signal - voluntary_est;  % 殘差 = 震顫 + 雜訊
    
    % === 初始化 ===
    w_k = zeros(dim, 1);  % 權重向量
    
    % 輸出陣列
    tremor_est = zeros(1, N);
    
    % Debug
    debug.error = zeros(1, N);
    debug.w_history = zeros(dim, N);
    debug.voluntary_est = voluntary_est;
    debug.residual = residual;
    debug.freqs = freqs;
    debug.spectral_power = zeros(n_freq, N);  % 各頻率分量功率
    
    % === 主迴圈 ===
    for k = 1:N
        % --- 建構參考向量 x_k ---
        % x_k = [sin(ω₁·k·Δt), ..., sin(ωₙ·k·Δt), 
        %        cos(ω₁·k·Δt), ..., cos(ωₙ·k·Δt)]'
        x_k = zeros(dim, 1);
        t_k = (k - 1) * dt;  % 當前時間
        for r = 1:n_freq
            x_k(r)           = sin(omega(r) * t_k);
            x_k(n_freq + r)  = cos(omega(r) * t_k);
        end
        
        % --- NLMS 估測與更新 ---
        % 震顫估測
        y_k = w_k' * x_k;
        
        % 誤差
        e_k = residual(k) - y_k;
        
        % 權重更新 (Normalized LMS)
        % 步長正規化：除以 ||x_k||^2 確保收斂穩定
        x_power = x_k' * x_k + 1e-8;  % 加 epsilon 防止除以零
        w_k = w_k + 2 * mu / x_power * e_k * x_k;
        
        % --- 輸出（使用更新後的權重）---
        tremor_est(k) = w_k' * x_k;
        
        % Debug 記錄
        debug.error(k) = e_k;
        debug.w_history(:, k) = w_k;
        
        % 計算各頻率分量的瞬時功率
        for r = 1:n_freq
            debug.spectral_power(r, k) = w_k(r)^2 + w_k(n_freq + r)^2;
        end
    end
    
    % 最終權重
    w_final = w_k;
end
