function y = butter_lowpass(x, fc, fs, order)
% BUTTER_LOWPASS 使用 Butterworth 低通濾波器分離自主動作
%
%   y = butter_lowpass(x, fc, fs)
%   y = butter_lowpass(x, fc, fs, order)
%
%   此函式使用零相位 Butterworth 低通濾波器（filtfilt），
%   用於從混合訊號中提取低頻自主動作分量。
%
%   輸入:
%     x     - 輸入訊號（行向量）
%     fc    - 截止頻率 (Hz), 建議 2 Hz
%     fs    - 取樣頻率 (Hz)
%     order - 濾波器階數, 預設 4
%
%   輸出:
%     y     - 濾波後的低頻訊號（自主動作估測）
%
%   使用 filtfilt 實現零相位延遲，適合離線模擬。
%   注意：嵌入式即時實作應改用因果濾波器 (filter)。

    if nargin < 4
        order = 4;
    end
    
    % 正規化截止頻率
    Wn = fc / (fs / 2);
    
    % 防止異常值
    if Wn >= 1
        warning('截止頻率 >= 奈奎斯特頻率，自動設為 0.99');
        Wn = 0.99;
    end
    
    % 設計 Butterworth 低通濾波器
    [b, a] = butter(order, Wn, 'low');
    
    % 零相位濾波（前向+反向）
    y = filtfilt(b, a, x);
end
