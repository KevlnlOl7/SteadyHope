function [tremor_est, freq_est, w_kf, debug] = eHWFLC_KF(signal, fs, varargin)
% eHWFLC_KF 增強型高階加權頻率傅立葉線性組合器-卡爾曼濾波器
%
%   [tremor_est, freq_est, w_kf, debug] = eHWFLC_KF(signal, fs)
%   [tremor_est, freq_est, w_kf, debug] = eHWFLC_KF(signal, fs, 'Name', Value, ...)
%
%   此函式實作論文中表現最佳的震顫估測演算法 (89.3% 震顫功率降低)。
%   架構為兩階段：
%     1) 低通濾波分離自主動作
%     2) WFLC 追蹤基頻 + 高階 Kalman Filter 最佳估測
%
%   參考文獻:
%     Zhou et al., "Real-Time Performance Assessment of High-Order Tremor
%     Estimators Used in a Wearable Tremor Suppression Device," IEEE TNSRE, 2022.
%     Zhou et al., "Design and validation of a high-order weighted-frequency
%     fourier linear combiner-based Kalman filter," IEEE EMBC, 2016.
%
%   輸入:
%     signal    - 輸入訊號 (1×N 或 N×1 行向量), 模擬陀螺儀角速度 (°/s)
%     fs        - 取樣頻率 (Hz)
%
%   名稱-值對:
%     'M'           - 諧波階數, 預設 3
%     'omega_init'  - 初始基頻 (rad/s), 預設 2*pi*5
%     'mu_w'        - WFLC 權重學習率, 預設 0.01
%     'mu_omega'    - WFLC 頻率學習率, 預設 0.005
%     'Q'           - KF 過程雜訊協方差 (2M×2M 或純量), 預設 1e-2
%     'R'           - KF 觀測雜訊方差 (純量), 預設 0.05
%     'P0'          - KF 初始協方差 (2M×2M 或純量), 預設 1
%     'fc_lp'       - 低通截止頻率 (Hz), 預設 2
%     'lp_order'    - 低通濾波器階數, 預設 4
%     'omega_min'   - 最小允許頻率 (rad/s), 預設 2*pi*3
%     'omega_max'   - 最大允許頻率 (rad/s), 預設 2*pi*12
%
%   輸出:
%     tremor_est - 估測震顫分量 (1×N)
%     freq_est   - 估測基頻歷史 (1×N, Hz)
%     w_kf       - KF 最終權重向量 (2M×1)
%     debug      - 除錯結構體 (包含中間變數)

    % === 輸入解析 ===
    signal = signal(:)';  % 確保為行向量
    N = length(signal);
    dt = 1 / fs;
    
    p = inputParser;
    addParameter(p, 'M', 3);
    addParameter(p, 'omega_init', 2*pi*5);
    addParameter(p, 'mu_w', 0.01);
    addParameter(p, 'mu_omega', 0.005);
    addParameter(p, 'Q', 1e-2);
    addParameter(p, 'R', 0.05);
    addParameter(p, 'P0', 1);
    addParameter(p, 'fc_lp', 2);
    addParameter(p, 'lp_order', 4);
    addParameter(p, 'omega_min', 2*pi*3);
    addParameter(p, 'omega_max', 2*pi*12);
    parse(p, varargin{:});
    
    M         = p.Results.M;
    omega_k   = p.Results.omega_init;
    mu_w      = p.Results.mu_w;
    mu_omega  = p.Results.mu_omega;
    Q_param   = p.Results.Q;
    R         = p.Results.R;
    P0_param  = p.Results.P0;
    fc_lp     = p.Results.fc_lp;
    lp_order  = p.Results.lp_order;
    omega_min = p.Results.omega_min;
    omega_max = p.Results.omega_max;
    
    dim = 2 * M;  % 狀態維度
    
    % 建立 Q 和 P0 矩陣
    if isscalar(Q_param)
        Q = Q_param * eye(dim);
    else
        Q = Q_param;
    end
    if isscalar(P0_param)
        P_est = P0_param * eye(dim);
    else
        P_est = P0_param;
    end
    
    % === 第一階段：低通濾波分離自主動作 ===
    voluntary_est = butter_lowpass(signal, fc_lp, fs, lp_order);
    residual = signal - voluntary_est;  % 殘差 = 震顫 + 雜訊
    
    % === 初始化 ===
    % WFLC 權重（用於頻率追蹤）
    w_wflc = zeros(dim, 1);
    
    % KF 狀態向量
    w_est = zeros(dim, 1);
    
    % 累積相位
    phi_k = 0;
    
    % 輸出陣列
    tremor_est = zeros(1, N);
    freq_est   = zeros(1, N);
    
    % Debug
    debug.innovation = zeros(1, N);
    debug.kalman_gain_norm = zeros(1, N);
    debug.w_history = zeros(dim, N);
    debug.voluntary_est = voluntary_est;
    debug.residual = residual;
    
    % === 主迴圈 ===
    for k = 1:N
        % --- 更新累積相位 ---
        phi_k = phi_k + omega_k * dt;
        
        % --- 建構參考向量 x_k ---
        % x_k = [sin(φ), sin(2φ), sin(3φ), cos(φ), cos(2φ), cos(3φ)]'
        x_k = zeros(dim, 1);
        for m = 1:M
            x_k(m)     = sin(m * phi_k);
            x_k(M + m) = cos(m * phi_k);
        end
        
        % --- WFLC 頻率追蹤 ---
        % WFLC 震顫估測
        s_hat_wflc = w_wflc' * x_k;
        e_wflc = residual(k) - s_hat_wflc;
        
        % 頻率梯度
        freq_grad = 0;
        for m = 1:M
            freq_grad = freq_grad + m * (...
                w_wflc(m) * cos(m * phi_k) - ...
                w_wflc(M + m) * sin(m * phi_k));
        end
        
        % 更新頻率
        omega_k = omega_k + 2 * mu_omega * e_wflc * freq_grad;
        
        % 頻率鉗位（防止發散）
        omega_k = max(omega_min, min(omega_max, omega_k));
        
        % 更新 WFLC 權重
        w_wflc = w_wflc + 2 * mu_w * e_wflc * x_k;
        
        % --- 高階 Kalman Filter ---
        % 建構狀態轉移矩陣 U(k) — 區塊對角旋轉矩陣
        U = zeros(dim, dim);
        for m = 1:M
            theta = m * omega_k * dt;
            idx = 2*(m-1) + 1;
            U(idx,   idx)   =  cos(theta);
            U(idx,   idx+1) =  sin(theta);
            U(idx+1, idx)   = -sin(theta);
            U(idx+1, idx+1) =  cos(theta);
        end
        
        % KF 預測步驟
        w_pred = U * w_est;
        P_pred = U * P_est * U' + Q;
        
        % KF 觀測向量（重新排列以匹配狀態向量順序）
        % 狀態：[a1, b1, a2, b2, a3, b3]
        % 觀測：H = [sin(φ), cos(φ), sin(2φ), cos(2φ), sin(3φ), cos(3φ)]
        H = zeros(1, dim);
        for m = 1:M
            idx = 2*(m-1) + 1;
            H(idx)   = sin(m * phi_k);
            H(idx+1) = cos(m * phi_k);
        end
        
        % KF 更新步驟
        S_k = H * P_pred * H' + R;              % 創新協方差 (純量)
        K_k = P_pred * H' / S_k;                % Kalman 增益 (dim×1)
        innovation = residual(k) - H * w_pred;   % 創新 (純量)
        
        w_est = w_pred + K_k * innovation;
        P_est = (eye(dim) - K_k * H) * P_pred;
        
        % 確保 P 對稱（數值穩定性）
        P_est = (P_est + P_est') / 2;
        
        % --- 震顫估測輸出 ---
        tremor_est(k) = H * w_est;
        freq_est(k)   = omega_k / (2 * pi);  % 轉換為 Hz
        
        % Debug 記錄
        debug.innovation(k) = innovation;
        debug.kalman_gain_norm(k) = norm(K_k);
        debug.w_history(:, k) = w_est;
    end
    
    % 最終 KF 權重
    w_kf = w_est;
end
