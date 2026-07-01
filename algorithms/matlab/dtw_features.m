%% dtw_features.m
%  DTW 動作偏離特徵擷取 (辨識/gating 用, 非抑震)
%  ------------------------------------------------------------
%  對應計畫書 4.2「動態特徵量化:導入 DTW 計算動作路徑偏離程度 → 量化特徵向量」。
%  流程:  RAM(快速輪替動作)角速度  →  DTW( 測試, 健康模板 )  →  偏離特徵
%          → 併入特徵向量 → (後半段) Random Forest 判定狀態。
%
%  DTW 的價值 = 對「動作快慢」不敏感(時間校正), 讓特徵反映「動作品質」而非速度。
%  本檔驗證兩件事:
%    (A) 速度不變性: 同動作不同快慢, DTW≈0 而 Euclidean 暴增。
%    (B) 嚴重度可分: 健康 < 輕 < 中 < 重, 可當 Random Forest 特徵。
%
%  需求: Signal Processing Toolbox (內建 dtw)。合成訊號僅供開發驗證;
%        後半段接真實 RAM 錄製資料 + GAN 擴增 + Random Forest。
%  ------------------------------------------------------------
clear; clc; close all;

% 健康模板: 平順、等幅、無震顫 (6 個來回 @ 2 Hz)
template = gen_ram(6, 2.0, 30, 0, 0, 0, 1.0, 0);

%% (A) 速度不變性: DTW vs Euclidean
fprintf('=== (A) 速度不變性: DTW vs Euclidean ===\n');
fprintf('%-18s | %7s | %7s\n','測試','DTW','Euclid');
for c = {{'健康 同速',1.0},{'健康 快 1.4x',1.4},{'健康 慢 0.7x',0.7}}
    lbl = c{1}{1}; sp = c{1}{2};
    sig = gen_ram(6, 2.0, 30, 0, 0, 0, sp, 0);
    fprintf('%-18s | %7.3f | %7.3f\n', lbl, dtw_dist(template,sig), euclid_norm(template,sig));
end
fprintf('  >> DTW 幾乎不受快慢影響, Euclidean 卻暴增 => DTW 吸收速度差異\n');

%% (B) 嚴重度可分 (DTW 距離 = 動作偏離特徵)
fprintf('\n=== (B) 嚴重度可分 (DTW 距離 = 動作偏離特徵) ===\n');
labels = {'健康','PD 輕度','PD 中度','PD 重度'};
% [tremor_amp, decrement, rhythm_jit]
params = [0 0 0; 8 0.2 0.05; 16 0.4 0.12; 25 0.6 0.20];
dmean = zeros(1,4);
fprintf('%-12s | %8s\n','受試者(合成)','DTW 距離');
for i = 1:4
    ds = zeros(1,5);
    for s = 1:5
        sig = gen_ram(6, 2.0, 30, params(i,1), params(i,2), params(i,3), 1.0, s);
        ds(s) = dtw_dist(template, sig);
    end
    dmean(i) = mean(ds);
    fprintf('%-12s | %8.3f\n', labels{i}, dmean(i));
end
fprintf('  >> 單調遞增且遠高於速度雜訊 => 可直接當 Random Forest 特徵\n');

%% 特徵向量範例 (DTW 是其中一維; 震顫功率/頻率可改用 eHWFLC 的 freq_hz)
sig = gen_ram(6, 2.0, 30, 16, 0.4, 0.12, 1.0, 1);
X = abs(fft(sig - mean(sig))); f = (0:numel(sig)-1)*(100/numel(sig));
half = 1:floor(numel(sig)/2); band = (f(half)>=4 & f(half)<=7);
tremor_ratio = sum(X(half(band)).^2)/sum(X(half).^2);
[~,mi] = max(X(half).*band); dom_f = f(mi);
fprintf('\n=== 特徵向量範例 ===\n');
fprintf('  dtw_dist=%.3f, tremor_band_ratio=%.3f, dominant_freq=%.2f Hz\n', ...
        dtw_dist(template,sig), tremor_ratio, dom_f);

%% 圖
figure('Name','DTW 特徵','Position',[80 80 950 400]);
subplot(1,2,1);
bar(dmean); set(gca,'XTickLabel',labels); ylabel('DTW 距離');
title('DTW 距離 vs 帕金森嚴重度'); grid on;
subplot(1,2,2);
sev = gen_ram(6, 2.0, 30, 25, 0.6, 0.20, 1.0, 3);
[~,ix,iy] = dtw((template-mean(template))/std(template), (sev-mean(sev))/std(sev));
plot(ix,iy,'LineWidth',1.2); hold on; plot([1 numel(ix)],[1 numel(iy)],'--k');
xlabel('模板 index'); ylabel('測試 index'); title('DTW 對齊路徑 (重度)'); grid on; axis tight;

fprintf('\n完成. 合成訊號僅供開發; 後半段接真實 RAM + GAN + Random Forest。\n');

%% ================= 本地函式 =================
function x = gen_ram(n_cycles, f_ram, amp, tremor_amp, decrement, rhythm_jit, speed, seed)
% 合成 RAM 角速度 (以固定週期數產生, speed 只改快慢不改來回次數)
    rng(seed); FS = 100;
    f_inst = f_ram*speed;
    n = round(n_cycles/f_inst*FS); t = (0:n-1)/FS; dur = n/FS;
    phi = 0; x = zeros(1,n);
    for k = 1:n
        f = f_inst*(1 + rhythm_jit*sin(2*pi*0.7*t(k)) + rhythm_jit*0.3*randn);
        phi = phi + 2*pi*f/FS;
        a = amp*(1 - decrement*t(k)/dur);          % 振幅衰減 (bradykinesia)
        x(k) = a*sin(phi) + tremor_amp*sin(2*pi*5*t(k));  % 輪替 + 靜止性震顫
    end
end

function d = dtw_dist(x, y)
% z-score 正規化後用內建 dtw, 距離除以路徑長度 (可比較)
    x = (x-mean(x))/max(std(x),1e-9);
    y = (y-mean(y))/max(std(y),1e-9);
    [dc,ix,~] = dtw(x, y);
    d = dc/numel(ix);
end

function d = euclid_norm(x, y)
% 對齊長度後的歐氏距離 (無時間校正, 當對照)
    x = (x-mean(x))/max(std(x),1e-9);
    y = (y-mean(y))/max(std(y),1e-9);
    m = min(numel(x),numel(y));
    d = sqrt(mean((x(1:m)-y(1:m)).^2));
end
