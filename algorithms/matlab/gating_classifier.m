%% gating_classifier.m
%  辨識 → gating 骨架 (合成資料; 後半段接真實 RAM + GAN)
%  ------------------------------------------------------------
%  完整鏈路:
%    IMU 視窗 → 特徵(DTW 偏離 + 震顫帶) → Random Forest → 狀態 → gating → PID 模式
%
%  三狀態 (計畫書 4.3):
%    0 自主意圖  1 靜止震顫  2 精細動作
%  gating (計畫書 4.4 決策流程 圖4-3):
%    自主意圖 → 不出力(不干擾自主動作)
%    靜止震顫 → 標準 PID 抑震
%    精細動作 → 高增益 PID (精細支撐)
%
%  把「估測(BMFLC/eHWFLC) → 辨識(本檔) → 控制(control_sim)」整條鏈在合成資料上打通。
%  ⚠ 合成資料僅供骨架驗證; 後半段以真實 RAM 錄製資料 + GAN 擴增重新訓練。
%  需求: Statistics and Machine Learning Toolbox (TreeBagger)。
%  ------------------------------------------------------------
clear; clc; close all;
FS = 100; WIN = 3; N = WIN*FS;
states = {'自主意圖','靜止震顫','精細動作'};
featNames = {'rms','低頻能量','震顫帶比','主頻','DTW偏離'};
template = gen_ram(6, 2.0, 30, 0, 0, 0, 1.0, 0);   % DTW 用健康 RAM 模板

%% 產生訓練資料 (每狀態 120 筆)
rng(0); nPer = 120;
X = zeros(3*nPer, 5); y = zeros(3*nPer, 1); r = 0;
for s = 0:2
    for k = 1:nPer
        r = r + 1;
        X(r,:) = features(gen_window(s, N, FS), template, FS);
        y(r)   = s;
    end
end

%% 訓練 / 測試 Random Forest
rng(1); idx = randperm(size(X,1)); ntr = round(0.7*numel(idx));
tr = idx(1:ntr); te = idx(ntr+1:end);
mdl = TreeBagger(100, X(tr,:), y(tr), 'Method','classification', ...
                 'OOBPredictorImportance','on');
yp  = str2double(predict(mdl, X(te,:)));
acc = mean(yp == y(te))*100;

fprintf('=== Random Forest 狀態分類  準確率 = %.1f%% ===\n', acc);
C = confusionmat(y(te), yp);
fprintf('混淆矩陣 (列=真實, 欄=預測):\n');
fprintf('%12s%10s%10s%10s\n','',states{:});
for i = 1:3, fprintf('%12s%10d%10d%10d\n', states{i}, C(i,:)); end

fprintf('\n特徵重要度 (OOB):\n');
imp = mdl.OOBPermutedPredictorDeltaError;
[~,ord] = sort(imp,'descend');
for i = ord, fprintf('  %-8s %.3f\n', featNames{i}, imp(i)); end

%% gating 示範
gain  = [0.0 1.0 1.5];                                  % 接 control_sim 的 gain_scale
gdesc = {'不出力(不干擾自主動作)','標準 PID 抑震','高增益 PID(精細支撐)'};
fprintf('\n--- gating 示範: 分類狀態 -> PID 模式 ---\n');
rng(9);
for s = [1 0 2 1 0 2]
    p = str2double(predict(mdl, features(gen_window(s,N,FS), template, FS)));
    fprintf('  真實=%-6s 預測=%-6s -> gain=%.1f  %s\n', ...
            states{s+1}, states{p+1}, gain(p+1), gdesc{p+1});
end

%% 圖: 特徵重要度
figure('Name','特徵重要度','Position',[100 100 560 380]);
bar(imp(ord)); set(gca,'XTickLabel',featNames(ord));
ylabel('OOB 重要度'); title('Random Forest 特徵重要度 (含 DTW)'); grid on;
fprintf('\n完成. (合成資料; 後半段接真實 RAM + GAN 擴增重新訓練 RF。)\n');

%% ================= 本地函式 =================
function x = gen_window(state, N, FS)
% 依狀態產生一段合成 gyro 角速度視窗 (加隨機變異)
    t = (0:N-1)/FS;
    switch state
        case 0, vol_a=35+8*randn;      vol_f=1.3+0.3*abs(randn); tr_a=2+1.5*abs(randn);  % 自主意圖
        case 1, vol_a=2+1.5*abs(randn);vol_f=0.3+0.1*abs(randn); tr_a=14+4*randn;        % 靜止震顫
        case 2, vol_a=9+3*randn;       vol_f=0.8+0.2*abs(randn); tr_a=8+2.5*abs(randn);  % 精細動作
    end
    tr_a = max(tr_a,0); f_tr = 5.0+0.4*randn;
    x = vol_a*sin(2*pi*vol_f*t + 2*pi*rand) ...
        + tr_a*sin(2*pi*f_tr*t) + 0.3*tr_a*sin(2*pi*2*f_tr*t) ...
        + 0.5*randn(1,N);
end

function fv = features(x, template, FS)
% 特徵向量: [rms, 低頻能量, 震顫帶比, 主頻, DTW偏離]
    N = numel(x);
    [bl,al] = butter(2, 2/(FS/2), 'low'); low = filter(bl,al,x);
    Xf = abs(fft(x-mean(x))); f = (0:N-1)*(FS/N); half = 1:floor(N/2);
    band = (f(half)>=4 & f(half)<=7);
    tremor_ratio = sum(Xf(half(band)).^2)/(sum(Xf(half).^2)+1e-9);
    [~,mi] = max(Xf(half).*band); dom = f(mi);
    fv = [std(x), var(low), tremor_ratio, dom, dtw_dist(template,x)];
end

function d = dtw_dist(x, y)
    x = (x-mean(x))/max(std(x),1e-9);
    y = (y-mean(y))/max(std(y),1e-9);
    [dc,ix,~] = dtw(x, y); d = dc/numel(ix);
end

function x = gen_ram(n_cycles, f_ram, amp, tremor_amp, decrement, rhythm_jit, speed, seed)
    rng(seed); FS = 100; f_inst = f_ram*speed;
    n = round(n_cycles/f_inst*FS); t = (0:n-1)/FS; dur = n/FS;
    phi = 0; x = zeros(1,n);
    for k = 1:n
        f = f_inst*(1 + rhythm_jit*sin(2*pi*0.7*t(k)) + rhythm_jit*0.3*randn);
        phi = phi + 2*pi*f/FS;
        a = amp*(1 - decrement*t(k)/dur);
        x(k) = a*sin(phi) + tremor_amp*sin(2*pi*5*t(k));
    end
end
