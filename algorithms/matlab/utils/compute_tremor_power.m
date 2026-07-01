function [reduction_pct, power_before, power_after] = compute_tremor_power(tremor_true, tremor_est, voluntary_true, signal)
% COMPUTE_TREMOR_POWER 計算震顫功率降低百分比
%
%   [reduction_pct, power_before, power_after] = compute_tremor_power(tremor_true, tremor_est, voluntary_true, signal)
%
%   此函式計算震顫抑制前後的功率降低率，
%   模擬 WTSD 的實際運作：
%     - 抑制前：原始訊號中的震顫功率
%     - 抑制後：原始訊號減去估測震顫後的殘餘震顫功率
%
%   輸入:
%     tremor_true    - 真實震顫分量 (ground truth)
%     tremor_est     - 演算法估測的震顫分量
%     voluntary_true - 真實自主動作分量 (ground truth)  
%     signal         - 原始總訊號
%
%   輸出:
%     reduction_pct - 震顫功率降低百分比 (%)
%     power_before  - 抑制前震顫功率
%     power_after   - 抑制後殘餘震顫功率
%
%   功率降低公式:
%     reduction = (1 - power_after / power_before) × 100%

    % 抑制前的震顫功率（原始訊號中的震顫分量）
    power_before = mean(tremor_true.^2);
    
    % 抑制後：從訊號中減去估測震顫
    % 理想情況下，剩餘 = 自主動作 + 雜訊
    % 殘餘震顫 = (原始震顫 - 估測震顫)
    residual_tremor = tremor_true - tremor_est;
    power_after = mean(residual_tremor.^2);
    
    % 功率降低百分比
    if power_before > 0
        reduction_pct = (1 - power_after / power_before) * 100;
    else
        reduction_pct = 0;
    end
end
