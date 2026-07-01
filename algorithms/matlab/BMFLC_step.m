function tremor_est = BMFLC_step(signal_sample, fs_in)
%#codegen
% BMFLC_STEP 單樣本 BMFLC 震顫估測（即時版本 v6）
%
%   tremor_est = BMFLC_step(signal_sample, fs_in)
%
%   v6 改進：支援動態 fs_in 輸入，預設為 100 Hz，並預存 50 Hz 與 100 Hz 
%   之 2-20 Hz 帶通濾波器係數，維持 C-codegen 相容性。
%
%   輸入:  signal_sample - 單一 IMU 樣本
%          fs_in         - (可選) 取樣率 (預設 100 Hz)
%   輸出:  tremor_est    - 估測震顫值

    if nargin < 2
        fs_in = 100;
    end

    % ================================================================
    %  參數設定
    % ================================================================
    mu = 0.5;              % NLMS 正規化學習率

    % 頻率設定：3~12 Hz, 間距 0.5 Hz → 19 個頻率
    f_low = 3;
    delta_f = 0.5;
    n_freq = 19;
    dim = 2 * n_freq;       % 38 維

    % ================================================================
    %  持久性狀態變數
    % ================================================================
    persistent initialized
    persistent w_k k_count
    persistent bp_z1 bp_z2 bp_z3 bp_z4
    persistent bp_b bp_a dt

    if isempty(initialized)
        initialized = true;
        w_k = zeros(dim, 1);
        k_count = 0;
        bp_z1 = 0; bp_z2 = 0; bp_z3 = 0; bp_z4 = 0;
        
        if fs_in == 50
            dt = 1 / 50;
            bp_b = [0.5299672270693482, 0.0000000000000000, -1.0599344541386964, 0.0000000000000000, 0.5299672270693482];
            bp_a = [1.0000000000000000, -0.5170037744907683, -0.7343184542248229, 0.1038433983977615, 0.2946365275879149];
        else
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
    %  NLMS 震顫估測
    % ================================================================
    t_k = k_count * dt;
    k_count = k_count + 1;

    % 建構參考向量 x_k (38×1)
    x_k = zeros(dim, 1);
    for r = 1:n_freq
        omega_r = 2 * pi * (f_low + (r-1) * delta_f);
        x_k(r)          = sin(omega_r * t_k);
        x_k(n_freq + r) = cos(omega_r * t_k);
    end

    % 估測（用當前權重）
    y_k = 0;
    for i = 1:dim
        y_k = y_k + w_k(i) * x_k(i);
    end

    % 誤差
    e_k = residual - y_k;

    % NLMS 權重更新
    x_power = 1e-8;
    for i = 1:dim
        x_power = x_power + x_k(i) * x_k(i);
    end
    step_size = 2 * mu / x_power;
    for i = 1:dim
        w_k(i) = w_k(i) + step_size * e_k * x_k(i);
    end

    % 輸出（使用更新後的權重）
    tremor_est = 0;
    for i = 1:dim
        tremor_est = tremor_est + w_k(i) * x_k(i);
    end
end
