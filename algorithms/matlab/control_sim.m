%% control_sim.m
%  SteadyHope 抑震「控制律」閉迴路模擬 (design / 參數校調 / 答辯用圖)
%  ------------------------------------------------------------
%  把估測器輸出接上致動器,驗證「出多少力」這一層:
%    - feedback PID (計畫書「PID 閉迴路」直譯; 精細模式=高增益)
%    - 半主動阻尼   (張力∝顫抖速度; 對應線纜牽引, 天生穩定)
%    - 相位/延遲敏感度: 為何閉迴路延遲要 <=15ms
%
%  指標: TPSR = 1 - var(殘餘顫抖)/var(開迴路顫抖)   (計畫書主指標)
%        ETVM = RMS( 低通(量測) - 真實自主動作 )      (不干擾正常動作)
%
%  ⚠ plant / 致動器參數為【標稱值】,僅供設計與參數敏感度分析。
%    最終 PID 參數必須用硬體實測的致動器增益/頻寬/延遲重新校調
%    (對應計畫書「主動抑震力矩實測與參數校調」)。
%  ------------------------------------------------------------
clear; clc; close all;

%% ===== 標稱參數 (待硬體實測替換) =====
P.fs_sim   = 1000;      % 模擬解析度 (Hz)
P.dt       = 1/P.fs_sim;
P.T        = 14;        % 秒
P.N        = round(P.T*P.fs_sim);
P.ctrl_dec = 10;        % 每 10 個 sim-sample 更新一次控制 => 100 Hz
P.dt_ctrl  = P.ctrl_dec/P.fs_sim;
P.K_act    = 1.0;       % 致動器等效增益 (命令->量測角速度)
P.tau_act  = 0.005;     % 致動器一階時間常數 5 ms
% fs=100Hz 的 2-20Hz 帶通 (DF-II Transposed), 與交付演算法前處理一致
P.bp_b = [0.17508764367210086, 0, -0.3501752873442017, 0, 0.17508764367210086];
P.bp_a = [1.0, -2.299055356038497, 1.9674977599844512, -0.874805556449481, 0.21965398391369484];

%% ===== 1. 四種控制方案比較 @ 10 ms 延遲 =====
fprintf('=== 控制方案比較 @ 10 ms 迴路延遲 ===\n');
fprintf('%-24s | %7s | %s\n','方案','TPSR','ETVM');
cases = {
  'none (基準)',        struct('mode','none');
  'PID 基準 (Kp=0.8)',  struct('mode','pid','Kp',0.8);
  'PID 精細 (Kp=1.2)',  struct('mode','pid','Kp',1.2);
  '半主動阻尼',          struct('mode','damping','b',0.5);
  '半主動阻尼(單向)',     struct('mode','damping','b',0.5,'uni',true);
};
for i = 1:size(cases,1)
    r = run_case(P, 10, cases{i,2});
    fprintf('%-24s | %6.1f%% | %.4f\n', cases{i,1}, r.tpsr, r.etvm);
end

%% ===== 2. 關鍵發現: 相位/延遲敏感度 =====
delays = [5 10 15 20 25 30 40];
tp_pid = zeros(size(delays)); tp_dmp = zeros(size(delays));
for k = 1:numel(delays)
    tp_pid(k) = run_case(P, delays(k), struct('mode','pid','Kp',1.0)).tpsr;
    tp_dmp(k) = run_case(P, delays(k), struct('mode','damping','b',0.5)).tpsr;
end
fprintf('\n=== 相位/延遲敏感度: TPSR vs 迴路延遲 ===\n');
fprintf('%9s | %12s | %10s\n','delay(ms)','feedback PID','半主動阻尼');
for k = 1:numel(delays)
    fprintf('%9d | %11.1f%% | %9.1f%%\n', delays(k), tp_pid(k), tp_dmp(k));
end
fprintf('  >> 延遲越大 TPSR 越低; PID 過大甚至變負(抵銷變放大), 阻尼只會變差不會放大.\n');

%% ===== 3. 圖 =====
% (a) 時域抑震效果
r0 = run_case(P, 10, struct('mode','none'));
r1 = run_case(P, 10, struct('mode','pid','Kp',1.2));
figure('Name','抑震效果 (時域)','Position',[80 80 900 420]);
idx = round(6*P.fs_sim):round(8*P.fs_sim);   % 取中段 2 秒
plot(r0.t(idx), r0.measured(idx)-r0.voluntary(idx),'Color',[.6 .6 .6]); hold on;
plot(r1.t(idx), r1.measured(idx)-r1.voluntary(idx),'b','LineWidth',1.2);
xlabel('時間 (s)'); ylabel('顫抖角速度 (\circ/s)');
legend('無控制','PID 抑震後'); title('抑震效果 (扣除自主動作後的顫抖分量)'); grid on;

% (b) TPSR vs 延遲
figure('Name','相位/延遲敏感度','Position',[120 120 720 420]);
plot(delays,tp_pid,'-o','LineWidth',1.5); hold on;
plot(delays,tp_dmp,'-s','LineWidth',1.5);
yline(60,'--k','目標 60%'); yline(0,':r'); xline(15,'--',' 15ms 預算');
xlabel('迴路延遲 (ms)'); ylabel('TPSR (%)');
legend('feedback PID','半主動阻尼','Location','southwest');
title('相位/延遲敏感度 — 為何閉迴路延遲要 \leq 15 ms'); grid on;

fprintf('\n完成. (參數為標稱值; 拿到致動器實測後改 P.K_act / P.tau_act / 延遲再校調 Kp.)\n');

%% ================= 本地函式 =================
function r = run_case(P, delay_ms, opt)
    if ~isfield(opt,'Kp'),  opt.Kp  = 0; end
    if ~isfield(opt,'b'),   opt.b   = 0; end
    if ~isfield(opt,'uni'), opt.uni = false; end
    if ~isfield(opt,'gain'),opt.gain= 1; end

    t = (0:P.N-1)/P.fs_sim;
    tremor    = 2.0*sin(2*pi*5*t) + 0.6*sin(2*pi*10*t + pi/4);
    voluntary = 3.0*sin(2*pi*0.8*t);              % 帶外, 應保留
    D = round(delay_ms*P.fs_sim/1000);            % 純延遲樣本數
    a_lag = P.dt/P.tau_act;

    u_hist = zeros(1,P.N); measured = zeros(1,P.N);
    y_act = 0; bp_z = [0 0 0 0]; e_prev = 0; u_cmd = 0;

    for n = 1:P.N
        if n-D >= 1, u_del = u_hist(n-D); else, u_del = 0; end
        y_act = y_act + a_lag*(P.K_act*u_del - y_act);     % 致動器一階遲滯
        measured(n) = voluntary(n) + tremor(n) + y_act;

        if mod(n-1, P.ctrl_dec) == 0
            switch opt.mode
                case 'none'
                    u_cmd = 0;
                case 'pid'
                    [z,bp_z] = df2t(measured(n), P.bp_b, P.bp_a, bp_z);   % 帶通隔離顫抖
                    e = -z;
                    u_cmd = opt.gain*opt.Kp*e;               % 純 P (Kd/Ki 對窄頻會發散)
                    e_prev = e; %#ok<NASGU>
                case 'damping'
                    [z,bp_z] = df2t(measured(n), P.bp_b, P.bp_a, bp_z);
                    u_cmd = -opt.gain*opt.b*z;               % 張力 ∝ 顫抖速度
                    if opt.uni, u_cmd = min(u_cmd,0); end     % 線纜只能拉一向
            end
        end
        u_hist(n) = u_cmd;
    end

    w0 = round(3*P.fs_sim);                        % 跳過 3 秒暫態
    residual = measured - voluntary;               % = 殘餘顫抖 (帶內)
    r.tpsr = (1 - var(residual(w0:end))/var(tremor(w0:end)))*100;
    [bl,al] = butter(4, 2/(P.fs_sim/2), 'low');    % ETVM: 低頻應=自主動作
    vol_est = filtfilt(bl,al,measured);
    r.etvm = sqrt(mean((vol_est(w0:end)-voluntary(w0:end)).^2));
    r.t = t; r.measured = measured; r.voluntary = voluntary; r.tremor = tremor;
end

function [y,z] = df2t(x, b, a, z)   % 4 階 IIR, Direct-Form-II Transposed, 單樣本
    y    = b(1)*x + z(1);
    z(1) = b(2)*x - a(2)*y + z(2);
    z(2) = b(3)*x - a(3)*y + z(3);
    z(3) = b(4)*x - a(4)*y + z(4);
    z(4) = b(5)*x - a(5)*y;
end
