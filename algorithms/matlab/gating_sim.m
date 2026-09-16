%% gating_sim.m
%  SteadyHope 馬達 gating（何時作動）設計驗證 — V1 freq窗 vs V2 頻帶比
%  ------------------------------------------------------------
%  回答:「馬達是否應該只在病徵頻率 (4-6 Hz 顫抖帶) 才作動?」
%  現行韌體 (Ryan branch main.c) 觸發條件只有 |tremorEstimate|>5,
%  freqEstimate 完全沒進判斷式 => 任何帶內動作都會觸發馬達 (實測「一動就轉」)。
%
%  兩種 gating 方案 (皆為 頻率鑑別 ∧ envelope ∧ 持續性 hysteresis):
%    V1 freq窗   : freqEstimate ∈ [4.0, 6.5] Hz    (被實證推翻, 留作對照)
%    V2 頻帶比   : env(4-6Hz) / (env(4-6Hz)+env(1-3Hz)) >= ratio  (建議採用)
%
%  V1 失效機制 (情境 C 實證): 強自主動作把 WFLC omega 拖到 3 Hz clamp 下限
%  後卡死 (pull-in range 限制), 顫抖恢復後 freqEstimate 回不到帶內,
%  gate 永久失效。與實機靜置 freqEstimate=3.21 Hz (clamp 地板) 觀測一致。
%
%  本檔與 algorithms/validation/gating_check.py 邏輯逐行對應
%  (Python 版已跑通, 四情境結論見該檔 docstring; 兩邊 RNG 不同,
%   duty/延遲數字會微幅差異, 結論不變)。
%
%  ⚠ 依賴 eHWFLC_KF_step.m 的 persistent 狀態: 每個情境前必須
%    `clear eHWFLC_KF_step`, 否則沿用上一輪的濾波器/KF 狀態, 結果失真。
%  ⚠ AMP_ON/AMP_OFF 為標稱值, 與病患顫抖振幅/gyro 標度/配戴朝向相關,
%    上板後須實測校調 (比照 control_sim.m 對致動器參數的 caveat)。
%  ------------------------------------------------------------
clear; clc; close all;

%% ===== gating 參數 (100 Hz tick, 10 ms/tick) =====
GP.f_lo      = 4.0;    % V1: 頻率窗下緣 (Hz)
GP.f_hi      = 6.5;    % V1: 頻率窗上緣 (Hz)
GP.amp_on    = 6.0;    % 啟動 envelope 門檻 (deg/s)
GP.amp_off   = 3.0;    % 關閉 envelope 門檻 (hysteresis, 較低)
GP.ratio_on  = 0.55;   % V2: 啟動頻帶比門檻
GP.ratio_off = 0.45;   % V2: 維持頻帶比門檻
GP.env_decay = 0.94;   % envelope 衰減 tau≈160ms = exp(-0.01/0.16)
GP.n_on      = 20;     % 連續 20 tick = 200 ms 才啟動 (≈1 顫抖週期)
GP.n_off     = 15;     % 連續 15 tick = 150 ms 才關閉

FS = 100; DT = 1/FS;

% V2 的雙頻帶 biquad (2 階 Butterworth 帶通, fs=100Hz)
[bt_, at_] = butter(2, [4 6]/(FS/2), 'bandpass');   % 顫抖帶 4-6 Hz
[bv_, av_] = butter(2, [1 3]/(FS/2), 'bandpass');   % 自主帶 1-3 Hz

%% ===== 四個驗證情境 =====
scen = {
 'A: 純自主動作 (2Hz+4Hz諧波+瞬態)', 20, {0 2 'rest'; 2 20 'voluntary'};
 'B: 靜置5s → 5Hz 顫抖 onset',       20, {0 5 'rest'; 5 20 'tremor'};
 'C: 顫抖→自主→顫抖',               18, {0 2 'rest'; 2 7 'tremor'; 7 10 'voluntary'; 10 16 'tremor'; 16 18 'rest'};
 'D: 顫抖疊加自主動作',              18, {0 2 'rest'; 2 4 'tremor'; 4 16 'both'; 16 18 'rest'};
};

R = cell(size(scen,1),1);
for k = 1:size(scen,1)
    rng(0);
    [t, sig, tm, vm] = make_signal(scen{k,2}, scen{k,3}, FS);
    clear eHWFLC_KF_step                       % ← 必要! 重設 persistent 狀態
    g1 = init_gate(); g2 = init_gate();
    N = numel(t);
    en1 = false(1,N); en2 = false(1,N); freq = zeros(1,N); trem = zeros(1,N);
    for i = 1:N
        [te, fh] = eHWFLC_KF_step(sig(i));     % fs 預設 100 Hz
        [en1(i), g1] = freq_gate(g1, te, fh, GP);
        [en2(i), g2] = band_gate(g2, sig(i), GP, bt_, at_, bv_, av_);
        freq(i) = fh; trem(i) = te;
    end
    R{k} = struct('name',scen{k,1},'t',t,'sig',sig,'tm',tm,'vm',vm, ...
                  'en1',en1,'en2',en2,'freq',freq,'trem',trem);

    vol_only = vm & ~tm; rest = ~tm & ~vm;
    fprintf('=== %s ===\n', scen{k,1});
    for gi = 1:2
        if gi==1, en = en1; tag='V1 freq窗 '; else, en = en2; tag='V2 頻帶比'; end
        s = sprintf('  [%s]', tag);
        if any(vol_only), s = [s sprintf(' 自主段 %5.2f%% (<2%%) |', 100*mean(en(vol_only)))]; end %#ok<AGROW>
        if any(tm),       s = [s sprintf(' 顫抖段 %5.2f%% (>90%%) |', 100*mean(en(tm)))];       end %#ok<AGROW>
        if any(rest),     s = [s sprintf(' 靜置段 %5.2f%%', 100*mean(en(rest)))];                end %#ok<AGROW>
        fprintf('%s\n', s);
    end
    en_old = abs(trem) > 5.0;                  % 現行韌體: |tremorEstimate|>MOTOR_THRESHOLD
    if any(vol_only)
        fprintf('  [現行韌體無gating] 自主段誤觸發 %5.2f%%\n', 100*mean(en_old(vol_only)));
    end
end

%% ===== 切換延遲 (情境 B / C) =====
B = R{2}; C = R{3};
fprintf('\n--- 切換延遲 ---\n');
fprintf('B onset(t=5)     V1: %s | V2: %s\n', fmtd(ft(B.en1,5,FS)),  fmtd(ft(B.en2,5,FS)));
fprintf('C onset(t=2)     V1: %s | V2: %s\n', fmtd(ft(C.en1,2,FS)),  fmtd(ft(C.en2,2,FS)));
fprintf('C 釋放(t=7)      V1: %s | V2: %s\n', fmtd(ft(~C.en1,7,FS)), fmtd(ft(~C.en2,7,FS)));
fprintf('C 再啟動(t=10)   V1: %s | V2: %s\n', fmtd(ft(C.en1,10,FS)), fmtd(ft(C.en2,10,FS)));
fprintf('C 停止釋放(t=16) V1: %s | V2: %s\n', fmtd(ft(~C.en1,16,FS)),fmtd(ft(~C.en2,16,FS)));

i_stuck = C.t>=10.5 & C.t<=14;
fprintf('\nV1 失效證據: C t=10.5-14s freqEstimate ∈ [%.3f, %.3f] Hz (clamp 下限 3.0, 回不到 4-6 帶)\n', ...
        min(C.freq(i_stuck)), max(C.freq(i_stuck)));

fprintf('\n--- V2 韌體用 biquad 係數 (fs=100Hz, DF-II Transposed) ---\n');
fprintf('TREMOR 4-6Hz    b=[%s]\n                a=[%s]\n', num2str(bt_,'%.17g '), num2str(at_,'%.17g '));
fprintf('VOLUNTARY 1-3Hz b=[%s]\n                a=[%s]\n', num2str(bv_,'%.17g '), num2str(av_,'%.17g '));

%% ===== 答辯用圖: 情境 C =====
figure('Name','gating 驗證 (情境 C)','Position',[80 80 950 640]);
subplot(3,1,1);
plot(C.t, C.sig, 'Color', [.6 .6 .6]); ylabel('gyro (\circ/s)');
title('情境 C: 顫抖(2-7s) → 自主動作(7-10s) → 顫抖(10-16s)'); grid on;
subplot(3,1,2);
plot(C.t, C.freq, 'b', 'LineWidth', 1.1); hold on;
yline(4.0,'--k','F\_LO'); yline(6.5,'--k','F\_HI'); yline(3.0,':r','\omega clamp 下限');
ylabel('freqEstimate (Hz)'); ylim([2.5 7.5]); grid on;
title('V1 失效機制: 自主動作把 \omega 拖到 clamp 地板後卡死');
subplot(3,1,3);
stairs(C.t, double(C.en1)*0.9, 'r', 'LineWidth', 1.2); hold on;
stairs(C.t, double(C.en2)*1.0, 'b', 'LineWidth', 1.2);
ylim([-0.1 1.3]); ylabel('motor enabled');
legend('V1 freq窗 (失效)','V2 頻帶比','Location','east');
xlabel('時間 (s)'); grid on;

fprintf('\n完成. V2 (頻帶比) 為建議方案; C 程式碼移植見 algorithms/handoff/GATING_DESIGN.md\n');

%% ================= 本地函式 =================
function [t, sig, tm, vm] = make_signal(T, segs, FS)
    % 背景: BNO055 雜訊 0.2 deg/s + 0.5 Hz 姿勢性微晃 2 deg/s
    % tremor: 15·sin(5Hz, ±0.3Hz 飄移) + 4.5·sin(二次諧波)  [對齊 golden 設計]
    % voluntary: 40·sin(2Hz) + 6·sin(4Hz+0.7, 對抗性諧波) + 每2s 一個 0.3s reach 瞬態
    N = round(T*FS); t = (0:N-1)/FS;
    sig = 0.2*randn(1,N) + 2.0*sin(2*pi*0.5*t);
    tm = false(1,N); vm = false(1,N);
    for si = 1:size(segs,1)
        m = t>=segs{si,1} & t<segs{si,2}; kind = segs{si,3};
        if any(strcmp(kind,{'tremor','both'}))
            drift = 0.3*sin(2*pi*0.1*t(m));
            phase = 2*pi*cumsum(5.0+drift)/FS;
            sig(m) = sig(m) + 15.0*sin(phase) + 4.5*sin(2*phase);
            tm = tm | m;
        end
        if any(strcmp(kind,{'voluntary','both'}))
            sig(m) = sig(m) + 40.0*sin(2*pi*2.0*t(m)) + 6.0*sin(2*pi*4.0*t(m)+0.7);
            vm = vm | m;
        end
    end
    for si = 1:size(segs,1)
        if any(strcmp(segs{si,3},{'voluntary','both'}))
            for tb = segs{si,1}+0.5 : 2.0 : segs{si,2}
                m = t>=tb & t<tb+0.3;
                sig(m) = sig(m) + 60.0*0.5*(1-cos(2*pi*(t(m)-tb)/0.3));
            end
        end
    end
end

function g = init_gate()
    g = struct('env',0,'env_t',0,'env_v',0,'enabled',false, ...
               'on_count',0,'off_count',0,'zt',[0 0 0 0],'zv',[0 0 0 0]);
end

function [en, g] = freq_gate(g, tremor_est, freq_hz, GP)
    % V1: freqEstimate 頻率窗 (對照組, 已被情境 C 推翻)
    g.env = max(abs(tremor_est), g.env*GP.env_decay);
    in_band = freq_hz >= GP.f_lo && freq_hz <= GP.f_hi;
    g = gate_fsm(g, in_band && g.env >= GP.amp_off, in_band && g.env >= GP.amp_on, GP);
    en = g.enabled;
end

function [en, g] = band_gate(g, raw, GP, bt, at, bv, av)
    % V2: 雙頻帶能量比 (建議方案, 可直接移植韌體 C)
    [yt, g.zt] = df2t(raw, bt, at, g.zt);
    [yv, g.zv] = df2t(raw, bv, av, g.zv);
    g.env_t = max(abs(yt), g.env_t*GP.env_decay);
    g.env_v = max(abs(yv), g.env_v*GP.env_decay);
    ratio = g.env_t / (g.env_t + g.env_v + 1e-9);
    hold_c = g.env_t >= GP.amp_off && ratio >= GP.ratio_off;
    trig_c = g.env_t >= GP.amp_on  && ratio >= GP.ratio_on;
    g = gate_fsm(g, hold_c, trig_c, GP);
    en = g.enabled;
end

function g = gate_fsm(g, hold_c, trig_c, GP)
    % 共用持續性 hysteresis 狀態機 (與 GATING_DESIGN.md 的 C 版逐行對應)
    if g.enabled
        if hold_c, g.off_count = 0;
        else
            g.off_count = g.off_count + 1;
            if g.off_count >= GP.n_off, g.enabled = false; g.on_count = 0; end
        end
    else
        if trig_c
            g.on_count = g.on_count + 1;
            if g.on_count >= GP.n_on, g.enabled = true; g.off_count = 0; end
        else
            g.on_count = 0;
        end
    end
end

function [y, z] = df2t(x, b, a, z)   % 4 階 IIR, DF-II Transposed, 單樣本
    y    = b(1)*x + z(1);
    z(1) = b(2)*x - a(2)*y + z(2);
    z(2) = b(3)*x - a(3)*y + z(3);
    z(3) = b(4)*x - a(4)*y + z(4);
    z(4) = b(5)*x - a(5)*y;
end

function delay = ft(enabled, t0, FS)
    % 回傳 t0 之後首次符合條件的延遲（秒）；找不到則為 NaN。
    i0 = round(t0*FS) + 1;
    hit = find(enabled(i0:end), 1, 'first');
    if isempty(hit), delay = NaN; else, delay = (hit-1)/FS; end
end

function s = fmtd(delay)
    if isnan(delay), s = 'never'; else, s = sprintf('%.0f ms', 1000*delay); end
end
