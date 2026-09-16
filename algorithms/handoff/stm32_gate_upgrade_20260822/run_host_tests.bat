@echo off
setlocal

set "PACKAGE_ROOT=%~dp0"
set "OUT_DIR=%TEMP%\steadyhope_gate_upgrade_20260822"
set "TRACE=%OUT_DIR%\host_actual_trace.csv"
set "REPORT=%OUT_DIR%\host_comparison.json"
set "EXE=%OUT_DIR%\test_gate_upgrade.exe"

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

gcc -std=c11 -Wall -Wextra -Werror -pedantic ^
  -I"%PACKAGE_ROOT%src\gating" ^
  -I"%PACKAGE_ROOT%src\shadow" ^
  -I"%PACKAGE_ROOT%target_test" ^
  "%PACKAGE_ROOT%src\gating\tremor_gate.c" ^
  "%PACKAGE_ROOT%src\shadow\gate_shadow_adapter.c" ^
  "%PACKAGE_ROOT%target_test\gate_boundary_runner.c" ^
  "%PACKAGE_ROOT%test\test_gate_upgrade.c" ^
  -lm -o "%EXE%"
if errorlevel 1 exit /b 1

"%EXE%" "%TRACE%"
if errorlevel 1 exit /b 1

python "%PACKAGE_ROOT%tools\compare_stm32_gate_log.py" ^
  --input "%TRACE%" ^
  --output-json "%REPORT%"
if errorlevel 1 exit /b 1

echo Host gate upgrade package: PASS
echo Trace: %TRACE%
echo Report: %REPORT%
exit /b 0
