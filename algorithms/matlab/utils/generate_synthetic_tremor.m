function [signal, tremor, voluntary, noise, t] = generate_synthetic_tremor(varargin)
% GENERATE_SYNTHETIC_TREMOR 產生合成帕金森震顫測試訊號
%
%   [signal, tremor, voluntary, noise, t] = generate_synthetic_tremor()
%   [signal, tremor, voluntary, noise, t] = generate_synthetic_tremor('Name', Value, ...)
%
%   此函式產生包含多諧波震顫、低頻自主動作與感測器雜訊的合成訊號，
%   模擬 BNO055 陀螺儀角速度 (°/s) 輸出。
%
%   名稱-值對:
%     'fs'            - 取樣頻率 (Hz), 預設 100
%     'duration'      - 訊號持續時間 (s), 預設 10
%     'f_tremor'      - 震顫基頻 (Hz), 預設 5
%     'tremor_amps'   - 諧波振幅 [A1, A2, A3] (°/s), 預設 [2.0, 0.8, 0.3]
%     'tremor_phases' - 諧波相位 [φ1, φ2, φ3] (rad), 預設 [0, pi/4, pi/3]
%     'vol_amps'      - 自主動作振幅 (°/s), 預設 [5, 3]
%     'vol_freqs'     - 自主動作頻率 (Hz), 預設 [0.5, 1.2]
%     'noise_std'     - 雜訊標準差 (°/s), 預設 0.2
%     'freq_drift'    - 震顫頻率漂移量 (Hz), 預設 0 (無漂移)
%
%   輸出:
%     signal    - 總訊號 (自主動作 + 震顫 + 雜訊)
%     tremor    - 純震顫分量
%     voluntary - 純自主動作分量
%     noise     - 雜訊分量
%     t         - 時間向量

    % 解析輸入參數
    p = inputParser;
    addParameter(p, 'fs', 100);
    addParameter(p, 'duration', 10);
    addParameter(p, 'f_tremor', 5);
    addParameter(p, 'tremor_amps', [2.0, 0.8, 0.3]);
    addParameter(p, 'tremor_phases', [0, pi/4, pi/3]);
    addParameter(p, 'vol_amps', [5, 3]);
    addParameter(p, 'vol_freqs', [0.5, 1.2]);
    addParameter(p, 'noise_std', 0.2);
    addParameter(p, 'freq_drift', 0);
    parse(p, varargin{:});
    
    fs          = p.Results.fs;
    duration    = p.Results.duration;
    f_tremor    = p.Results.f_tremor;
    amps        = p.Results.tremor_amps;
    phases      = p.Results.tremor_phases;
    vol_amps    = p.Results.vol_amps;
    vol_freqs   = p.Results.vol_freqs;
    noise_std   = p.Results.noise_std;
    freq_drift  = p.Results.freq_drift;
    
    dt = 1 / fs;
    t = 0:dt:(duration - dt);
    N = length(t);
    
    % === 震顫訊號 (多諧波) ===
    % 支援頻率漂移：震顫頻率隨時間緩慢變化
    if freq_drift ~= 0
        f_inst = f_tremor + freq_drift * sin(2*pi*0.1*t);  % 0.1 Hz 慢變
    else
        f_inst = f_tremor * ones(1, N);
    end
    
    % 計算累積相位（處理時變頻率）
    phase_accum = cumsum(2*pi*f_inst*dt);
    
    tremor = zeros(1, N);
    n_harmonics = min(length(amps), length(phases));
    for h = 1:n_harmonics
        tremor = tremor + amps(h) * sin(h * phase_accum + phases(h));
    end
    
    % === 自主動作 (低頻 < 2 Hz) ===
    voluntary = zeros(1, N);
    n_vol = min(length(vol_amps), length(vol_freqs));
    for v = 1:n_vol
        voluntary = voluntary + vol_amps(v) * sin(2*pi*vol_freqs(v)*t);
    end
    
    % === 感測器雜訊 ===
    noise = noise_std * randn(1, N);
    
    % === 總訊號 ===
    signal = voluntary + tremor + noise;
end
