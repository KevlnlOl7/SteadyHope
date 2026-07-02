function d = dtw_dist(x, y)
% DTW_DIST  z-score 正規化後用內建 dtw, 距離除以路徑長度(可跨長度比較)。
%   共用於 dtw_features.m / gating_classifier.m。需 Signal Processing Toolbox。
    x = (x-mean(x))/max(std(x),1e-9);
    y = (y-mean(y))/max(std(y),1e-9);
    [dc,ix,~] = dtw(x, y);
    d = dc/numel(ix);
end
