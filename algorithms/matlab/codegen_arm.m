%% codegen_arm.m
%  一鍵：以 ARM Cortex-M 為目標，把「帶通版」 BMFLC_step / eHWFLC_KF_step
%  重新產生成可在 STM32 上編譯的 C，並覆蓋到 ../handoff/src/。
%
%  解掉兩個阻斷點：
%    (1) 關掉 SIMD → 不再產生 x86 的 <emmintrin.h> / __m128d（ARM 才編得過）
%    (2) fs 維持 100 Hz（單參數入口，dt/帶通係數都固定 100 Hz）
%
%  用法：在本資料夾 (algorithms/matlab) 開 MATLAB，直接執行本檔。
%  完成後跑 ../handoff/test/build_and_run.sh (或 .bat) 應為 ALL PASS。

here = fileparts(mfilename('fullpath'));
cd(here);
addpath(here);
addpath(fullfile(here, 'utils'));

%% ---- ARM-safe Coder 設定 ----
cfg = coder.config('lib');
cfg.TargetLang = 'C';
cfg.GenCodeOnly = true;      % 只產生原始碼，不呼叫 ARM 編譯器（免裝 toolchain）

% ★ 目標設成 ARM Cortex-M —— 這是不再產生 x86 SSE2 的主因
cfg.HardwareImplementation.ProdHWDeviceType = 'ARM Compatible->ARM Cortex-M';

% 以下屬性在不同 MATLAB 版本名稱可能略有差異，用 try/catch 保護：
try, cfg.InstructionSetExtensions = 'None'; catch, warning('InstructionSetExtensions 不支援，略過（ARM 目標已足以避免 SSE2）'); end
try, cfg.EnableOpenMP = false; catch, end
% 無動態配置：新版屬性優先，舊版當後備（舊 DynamicMemoryAllocation 已淘汰，設了會讓 codegen 報錯）
try
    cfg.EnableDynamicMemoryAllocation = false;     % 新版 API
catch
    try, cfg.DynamicMemoryAllocation = 'Off'; catch, end   % 舊版 API
end
try, cfg.SupportNonFinite = false; catch, end           % 省碼（不需 NaN/Inf 處理）

%% ---- 產生（帶通版；fs 寫死 100，單參數入口）----
fprintf('codegen BMFLC_step ...\n');
codegen -config cfg BMFLC_step     -args {0.0}
fprintf('codegen eHWFLC_KF_step ...\n');
codegen -config cfg eHWFLC_KF_step -args {0.0}

%% ---- 覆蓋到 handoff/src ----
srcBM = fullfile(here, 'codegen', 'lib', 'BMFLC_step');
srcEH = fullfile(here, 'codegen', 'lib', 'eHWFLC_KF_step');
dstBM = fullfile(here, '..', 'handoff', 'src', 'bmflc');
dstEH = fullfile(here, '..', 'handoff', 'src', 'ehwflc');

%% ---- 先檢查 ARM 安全性 (掃兩個檔的多種 x86 SIMD 標記; 有就擋下, 不覆蓋 handoff) ----
simd = 'emmintrin|xmmintrin|pmmintrin|tmmintrin|smmintrin|immintrin|__m128|__m256|_mm_';
bad = {};
for f = {fullfile(srcBM,'BMFLC_step.c'), fullfile(srcEH,'eHWFLC_KF_step.c')}
    if ~isempty(regexp(fileread(f{1}), simd, 'once')), bad{end+1} = f{1}; end %#ok<AGROW>
end
if ~isempty(bad)
    error(['產生的 C 仍含 x86 SIMD (%s)。請設 ARM 目標 + InstructionSetExtensions=''None'' ' ...
           '後重跑 (未覆蓋 handoff)。'], strjoin(bad, ', '));
end

%% ---- 清掉舊產物再覆蓋 (copyfile 不刪, 避免殘留 stale .c/.h 被編譯) ----
delete(fullfile(dstBM,'*.c')); delete(fullfile(dstBM,'*.h'));
delete(fullfile(dstEH,'*.c')); delete(fullfile(dstEH,'*.h'));
copyfile(fullfile(srcBM, '*.c'), dstBM);  copyfile(fullfile(srcBM, '*.h'), dstBM);
copyfile(fullfile(srcEH, '*.c'), dstEH);  copyfile(fullfile(srcEH, '*.h'), dstEH);

fprintf('OK：BMFLC / eHWFLC 產生的 C 皆無 x86 SIMD, 已覆蓋 handoff/src。\n');
fprintf('下一步：跑 ../handoff/test/build_and_run.sh (或 .bat)，應為 ALL PASS。\n');

% 備註：若 MATLAB 不認 'ARM Compatible->ARM Cortex-M' 字串，
%       改用 Coder App 的 Hardware 下拉選 ARM Cortex-M，或參考 ../handoff/README.md §4。
