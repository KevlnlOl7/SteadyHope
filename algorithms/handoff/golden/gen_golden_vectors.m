%% gen_golden_vectors.m
%  產生「黃金測試向量」(authoritative golden vectors)
%  ------------------------------------------------------------
%  用 MATLAB 原始模型 (BMFLC_step.m / eHWFLC_KF_step.m) 在 fs = 100 Hz
%  跑一段「確定性、無亂數」的合成訊號, 把輸入與輸出存成 CSV,
%  作為 C 端 test_equivalence 的比對基準。
%
%  這份 CSV 就是「MATLAB 模型的真值」。STM32 組重新產生 / 移植的 C
%  只要逐點對得上這份, 就證明移植沒有改變演算法數值。
%
%  用法:
%    1. 把 ALGO_DIR 設成 BMFLC_step.m / eHWFLC_KF_step.m 所在資料夾。
%    2. 在 MATLAB 執行本檔。會覆寫同目錄的 input.csv / golden_*.csv。
%  ------------------------------------------------------------

clear BMFLC_step eHWFLC_KF_step      % ★ 重置 persistent 狀態(務必, 否則沿用上次殘留)

here = fileparts(mfilename('fullpath'));

% --- 模型 .m 所在資料夾 = repo 內權威來源 ../../matlab (與 codegen_arm.m 同一份,
%     避免「golden 用一份、codegen 用另一份」的兩個 source-of-truth 陷阱) ---
ALGO_DIR = fullfile(here, '..', '..', 'matlab');
if isfolder(ALGO_DIR)
    addpath(ALGO_DIR);
else
    warning('找不到 %s — 請手動把 ALGO_DIR 設成 BMFLC_step.m 所在資料夾', ALGO_DIR);
end

fs = 100;        % ★ 與韌體實際取樣率一致; 改 fs 必須同時重產生 C
N  = 1000;       % 10 秒 @ 100 Hz

% --- 確定性輸入訊號 (與 README 公式一致, 無 rand/randn) ---
x = zeros(N, 1);
for k = 0:N-1
    t = k / fs;
    voluntary = 5*sin(2*pi*0.5*t) + 3*sin(2*pi*1.2*t);
    tremor    = 2*sin(2*pi*5*t) + 0.8*sin(2*pi*10*t + pi/4) + 0.3*sin(2*pi*15*t + pi/3);
    x(k+1)    = voluntary + tremor + 0.1*sin(2*pi*37*t);
end

% --- 逐樣本跑模型 (fs 顯式帶入 100, 與寫死 fs=100 的 codegen 一致) ---
ob = zeros(N, 1); oe = zeros(N, 1); of = zeros(N, 1);
for k = 1:N
    ob(k)        = BMFLC_step(x(k), fs);
    [oe(k), of(k)] = eHWFLC_KF_step(x(k), fs);
end

% --- 寫檔 (17 位有效數字 = double 全精度, 供 C 逐位元比對) ---
write_col(fullfile(here, 'input.csv'),         x);
write_col(fullfile(here, 'golden_bmflc.csv'),  ob);
write_two(fullfile(here, 'golden_ehwflc.csv'), oe, of);

fprintf('已寫出 input.csv / golden_bmflc.csv / golden_ehwflc.csv  (N=%d, fs=%d)\n', N, fs);
fprintf('BMFLC  out(end)=%.6f\n', ob(end));
fprintf('eHWFLC out(end)=%.6f  freq(end)=%.4f Hz\n', oe(end), of(end));

% ================= local functions =================
function write_col(path, v)
    f = fopen(path, 'w');
    fprintf(f, '%.17g\n', v);
    fclose(f);
end

function write_two(path, a, b)
    f = fopen(path, 'w');
    fprintf(f, '%.17g,%.17g\n', [a, b].');
    fclose(f);
end
