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

copyfile(fullfile(srcBM, '*.c'), dstBM);  copyfile(fullfile(srcBM, '*.h'), dstBM);
copyfile(fullfile(srcEH, '*.c'), dstEH);  copyfile(fullfile(srcEH, '*.h'), dstEH);

%% ---- 檢查 & 提示 ----
ehc = fileread(fullfile(dstEH, 'eHWFLC_KF_step.c'));
if contains(ehc, 'emmintrin')
    warning('eHWFLC_KF_step.c 仍含 emmintrin！請確認 ARM 目標與 InstructionSetExtensions 設定。');
else
    fprintf('OK：eHWFLC_KF_step.c 已無 x86 SSE2。\n');
end

fprintf('\n完成：已覆蓋 handoff/src/bmflc 與 handoff/src/ehwflc。\n');
fprintf('下一步：跑 ../handoff/test/build_and_run.sh (或 .bat)，應為 ALL PASS。\n');

% 備註：若 MATLAB 不認 'ARM Compatible->ARM Cortex-M' 字串，
%       改用 Coder App 的 Hardware 下拉選 ARM Cortex-M，或參考 ../handoff/README.md §4。
