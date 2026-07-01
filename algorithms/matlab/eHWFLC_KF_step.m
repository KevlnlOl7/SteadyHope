function [tremor_est, freq_hz] = eHWFLC_KF_step(signal_sample, fs_in)
%#codegen
% eHWFLC_KF_STEP 單樣本 eHWFLC-KF 震顫估測（即時版本 v6）
%
%   [tremor_est, freq_hz] = eHWFLC_KF_step(signal_sample, fs_in)
%
%   v6 改進：支援動態 fs_in 輸入，預設為 100 Hz，並預存 50 Hz 與 100 Hz 
%   之 2-20 Hz 帶通濾波器係數，維持 C-codegen 相容性。
%
%   輸入:  signal_sample - 單一 IMU 樣本
%          fs_in         - (可選) 取樣率 (預設 100 Hz)
%   輸出:  tremor_est    - 估測震顫值
%          freq_hz       - 估測基頻 (Hz)

    if nargin < 2
        fs_in = 100;
    end

    % ================================================================
    %  參數設定
    % ================================================================
    M = 3;                 % 諧波階數
    dim = 2 * M;           % 狀態維度 = 6

    % WFLC 參數
    mu_w = 0.01;
    mu_omega = 0.005;
    omega_init = 2*pi*5;
    omega_min = 2*pi*3;
    omega_max = 2*pi*12;

    % KF 參數
    Q_val = 1e-2;
    R_val = 0.05;

    % ================================================================
    %  持久性狀態變數
    % ================================================================
    persistent initialized
    persistent phi_k omega_k
    persistent w_wflc
    persistent w_est P_est
    persistent bp_z1 bp_z2 bp_z3 bp_z4
    persistent bp_b bp_a dt

    if isempty(initialized)
        initialized = true;
        phi_k = 0;
        omega_k = omega_init;
        w_wflc = zeros(dim, 1);
        w_est = zeros(dim, 1);
        P_est = eye(dim);
        bp_z1 = 0; bp_z2 = 0; bp_z3 = 0; bp_z4 = 0;
        
        if fs_in == 50
            dt = 1 / 50;
            bp_b = [0.5299672270693482, 0.0000000000000000, -1.0599344541386964, 0.0000000000000000, 0.5299672270693482];
            bp_a = [1.0000000000000000, -0.5170037744907683, -0.7343184542248229, 0.1038433983977615, 0.2946365275879149];
        else
            % 預設 100 Hz
            dt = 1 / 100;
            bp_b = [0.17508764367210086, 0, -0.3501752873442017, 0, 0.17508764367210086];
            bp_a = [1.0, -2.299055356038497, 1.9674977599844512, -0.874805556449481, 0.21965398391369484];
        end
    end

    % ================================================================
    %  4 階因果帶通濾波 (DF-II Transposed)
    % ================================================================
    residual = bp_b(1) * signal_sample + bp_z1;
    bp_z1 = bp_b(2) * signal_sample - bp_a(2) * residual + bp_z2;
    bp_z2 = bp_b(3) * signal_sample - bp_a(3) * residual + bp_z3;
    bp_z3 = bp_b(4) * signal_sample - bp_a(4) * residual + bp_z4;
    bp_z4 = bp_b(5) * signal_sample - bp_a(5) * residual;

    % ================================================================
    %  WFLC 頻率追蹤
    % ================================================================
    phi_k = phi_k + omega_k * dt;

    x_k = zeros(dim, 1);
    for m = 1:M
        x_k(m)     = sin(m * phi_k);
        x_k(M + m) = cos(m * phi_k);
    end

    s_hat_wflc = 0;
    for i = 1:dim
        s_hat_wflc = s_hat_wflc + w_wflc(i) * x_k(i);
    end
    e_wflc = residual - s_hat_wflc;

    freq_grad = 0;
    for m = 1:M
        freq_grad = freq_grad + m * ...
            (w_wflc(m) * cos(m * phi_k) - w_wflc(M+m) * sin(m * phi_k));
    end

    omega_k = omega_k + 2 * mu_omega * e_wflc * freq_grad;
    if omega_k < omega_min
        omega_k = omega_min;
    elseif omega_k > omega_max
        omega_k = omega_max;
    end

    for i = 1:dim
        w_wflc(i) = w_wflc(i) + 2 * mu_w * e_wflc * x_k(i);
    end

    % ================================================================
    %  高階 Kalman Filter
    % ================================================================
    U = zeros(dim, dim);
    for m = 1:M
        theta = m * omega_k * dt;
        idx = 2*(m-1) + 1;
        ct = cos(theta);
        st = sin(theta);
        U(idx,   idx)   =  ct;
        U(idx,   idx+1) =  st;
        U(idx+1, idx)   = -st;
        U(idx+1, idx+1) =  ct;
    end

    H = zeros(1, dim);
    for m = 1:M
        idx = 2*(m-1) + 1;
        H(idx)   = sin(m * phi_k);
        H(idx+1) = cos(m * phi_k);
    end

    % KF 預測
    w_pred = U * w_est;
    P_pred = U * P_est * U';
    for i = 1:dim
        P_pred(i,i) = P_pred(i,i) + Q_val;
    end

    % KF 更新
    S_k = R_val;
    for i = 1:dim
        for j = 1:dim
            S_k = S_k + H(i) * P_pred(i,j) * H(j);
        end
    end

    K_k = zeros(dim, 1);
    for i = 1:dim
        tmp = 0;
        for j = 1:dim
            tmp = tmp + P_pred(i,j) * H(j);
        end
        K_k(i) = tmp / S_k;
    end

    innov = residual;
    for i = 1:dim
        innov = innov - H(i) * w_pred(i);
    end

    w_est = w_pred;
    for i = 1:dim
        w_est(i) = w_est(i) + K_k(i) * innov;
    end

    % P 更新
    KH = K_k * H;
    P_est = (eye(dim) - KH) * P_pred;
    P_est = (P_est + P_est') * 0.5;

    % ================================================================
    %  輸出
    % ================================================================
    tremor_est = 0;
    for i = 1:dim
        tremor_est = tremor_est + H(i) * w_est(i);
    end
    freq_hz = omega_k / (2 * pi);
end
