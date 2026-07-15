@echo off
REM 在 Windows PC 上編譯等價性測試並執行 (需要 MinGW gcc 在 PATH)。
REM 用法:  test\build_and_run.bat        (從 handoff\ 目錄執行)
setlocal
set HERE=%~dp0
set ROOT=%HERE%..
set SRC=%ROOT%\src
if "%CC%"=="" set CC=gcc

%CC% -O2 -std=c11 ^
  -I"%SRC%\bmflc" -I"%SRC%\ehwflc" ^
  "%HERE%test_equivalence.c" ^
  "%SRC%\bmflc\BMFLC_step.c" "%SRC%\bmflc\BMFLC_step_data.c" "%SRC%\bmflc\BMFLC_step_initialize.c" ^
  "%SRC%\ehwflc\eHWFLC_KF_step.c" "%SRC%\ehwflc\eHWFLC_KF_step_data.c" "%SRC%\ehwflc\eHWFLC_KF_step_initialize.c" ^
  "%SRC%\ehwflc\eye.c" ^
  -lm -o "%HERE%test_equivalence.exe"
if errorlevel 1 exit /b 1

"%HERE%test_equivalence.exe" "%ROOT%\golden"
if errorlevel 1 exit /b 1

%CC% -O2 -std=c11 -Wall -Wextra ^
  -I"%SRC%\gating" ^
  "%HERE%test_tremor_gate.c" "%SRC%\gating\tremor_gate.c" ^
  -lm -o "%HERE%test_tremor_gate.exe"
if errorlevel 1 exit /b 1

"%HERE%test_tremor_gate.exe"
endlocal
