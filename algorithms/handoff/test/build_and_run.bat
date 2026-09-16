@echo off
REM Build and run PC equivalence tests. MinGW gcc must be on PATH.
REM May be called from any working directory.
setlocal
set HERE=%~dp0
set ROOT=%HERE%..
set SRC=%ROOT%\src
set OUT=%TEMP%\steadyhope_handoff_tests
if "%CC%"=="" set CC=gcc
if not exist "%OUT%" mkdir "%OUT%"
if not exist "%OUT%\golden" mkdir "%OUT%\golden"
copy /Y "%ROOT%\golden\*.csv" "%OUT%\golden\" >nul

%CC% -O2 -std=c11 ^
  -I"%SRC%\bmflc" -I"%SRC%\ehwflc" ^
  "%HERE%test_equivalence.c" ^
  "%SRC%\bmflc\BMFLC_step.c" "%SRC%\bmflc\BMFLC_step_data.c" "%SRC%\bmflc\BMFLC_step_initialize.c" ^
  "%SRC%\ehwflc\eHWFLC_KF_step.c" "%SRC%\ehwflc\eHWFLC_KF_step_data.c" "%SRC%\ehwflc\eHWFLC_KF_step_initialize.c" ^
  "%SRC%\ehwflc\eye.c" ^
  -lm -o "%OUT%\test_equivalence.exe"
if errorlevel 1 exit /b 1

"%OUT%\test_equivalence.exe" "%OUT%\golden"
if errorlevel 1 exit /b 1

%CC% -O2 -std=c11 -Wall -Wextra ^
  -I"%SRC%\gating" ^
  "%HERE%test_tremor_gate.c" "%SRC%\gating\tremor_gate.c" ^
  -lm -o "%OUT%\test_tremor_gate.exe"
if errorlevel 1 exit /b 1

"%OUT%\test_tremor_gate.exe"
if errorlevel 1 exit /b 1

%CC% -O2 -std=c11 -Wall -Wextra ^
  -I"%SRC%\gating" -I"%ROOT%\test_vectors\gating_7hz_boundary" ^
  "%HERE%test_tremor_gate_7hz_boundary.c" "%SRC%\gating\tremor_gate.c" ^
  -lm -o "%OUT%\test_tremor_gate_7hz_boundary.exe"
if errorlevel 1 exit /b 1

"%OUT%\test_tremor_gate_7hz_boundary.exe"
if errorlevel 1 exit /b 1

%CC% -O2 -std=c11 -Wall -Wextra ^
  -I"%SRC%\gating" -I"%ROOT%\test_vectors\gating_amplitude_sweep" ^
  "%HERE%test_tremor_gate_amplitude_sweep.c" "%SRC%\gating\tremor_gate.c" ^
  -lm -o "%OUT%\test_tremor_gate_amplitude_sweep.exe"
if errorlevel 1 exit /b 1

"%OUT%\test_tremor_gate_amplitude_sweep.exe"
if errorlevel 1 exit /b 1

%CC% -O2 -std=c11 -Wall -Wextra ^
  -I"%SRC%\gating" -I"%ROOT%\test_vectors\gating_mixed_boundary" ^
  "%HERE%test_tremor_gate_mixed_boundary.c" "%SRC%\gating\tremor_gate.c" ^
  -lm -o "%OUT%\test_tremor_gate_mixed_boundary.exe"
if errorlevel 1 exit /b 1

"%OUT%\test_tremor_gate_mixed_boundary.exe"
if errorlevel 1 exit /b 1
endlocal
