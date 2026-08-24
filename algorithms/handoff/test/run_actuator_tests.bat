@echo off
REM Build and run the bench-only actuator host tests. MinGW gcc is required.
REM May be called from any working directory; outputs go to %%TEMP%%.
setlocal
set HERE=%~dp0
set ROOT=%HERE%..
set SRC=%ROOT%\src
set STM32_SRC=%ROOT%\stm32_motor_control_20260823\src\actuator
set OUT=%TEMP%\steadyhope_handoff_actuator_tests
if "%CC%"=="" set CC=gcc
if not exist "%OUT%" mkdir "%OUT%"

%CC% -O2 -std=c11 -Wall -Wextra -Werror -pedantic ^
  -I"%SRC%\control" -I"%SRC%\gating" -I"%SRC%\bmflc" -I"%SRC%\ehwflc" ^
  "%HERE%test_suppression_control.c" ^
  "%SRC%\control\suppression_control.c" "%SRC%\gating\tremor_gate.c" ^
  "%SRC%\bmflc\BMFLC_step.c" "%SRC%\bmflc\BMFLC_step_data.c" "%SRC%\bmflc\BMFLC_step_initialize.c" ^
  "%SRC%\ehwflc\eHWFLC_KF_step.c" "%SRC%\ehwflc\eHWFLC_KF_step_data.c" "%SRC%\ehwflc\eHWFLC_KF_step_initialize.c" ^
  "%SRC%\ehwflc\eye.c" ^
  -lm -o "%OUT%\test_suppression_control.exe"
if errorlevel 1 exit /b 1
"%OUT%\test_suppression_control.exe"
if errorlevel 1 exit /b 1

%CC% -O2 -std=c11 -Wall -Wextra -Werror -pedantic ^
  -I"%SRC%\control" ^
  "%HERE%test_motor_command_mapper.c" ^
  "%SRC%\control\motor_command_mapper.c" ^
  -lm -o "%OUT%\test_motor_command_mapper.exe"
if errorlevel 1 exit /b 1
"%OUT%\test_motor_command_mapper.exe"
if errorlevel 1 exit /b 1

%CC% -O2 -std=c11 -Wall -Wextra -Werror -pedantic ^
  -I"%SRC%\control" -I"%SRC%\gating" -I"%SRC%\bmflc" -I"%SRC%\ehwflc" ^
  "%HERE%test_suppression_pipeline.c" ^
  "%SRC%\control\suppression_control.c" "%SRC%\control\motor_command_mapper.c" "%SRC%\gating\tremor_gate.c" ^
  "%SRC%\bmflc\BMFLC_step.c" "%SRC%\bmflc\BMFLC_step_data.c" "%SRC%\bmflc\BMFLC_step_initialize.c" ^
  "%SRC%\ehwflc\eHWFLC_KF_step.c" "%SRC%\ehwflc\eHWFLC_KF_step_data.c" "%SRC%\ehwflc\eHWFLC_KF_step_initialize.c" ^
  "%SRC%\ehwflc\eye.c" ^
  -lm -o "%OUT%\test_suppression_pipeline.exe"
if errorlevel 1 exit /b 1
"%OUT%\test_suppression_pipeline.exe"
if errorlevel 1 exit /b 1

%CC% -O2 -std=c11 -Wall -Wextra -Werror -pedantic ^
  -I"%SRC%\actuator" ^
  "%HERE%test_quadrature_encoder.c" ^
  "%SRC%\actuator\quadrature_encoder.c" ^
  -o "%OUT%\test_quadrature_encoder.exe"
if errorlevel 1 exit /b 1
"%OUT%\test_quadrature_encoder.exe"
if errorlevel 1 exit /b 1

%CC% -O2 -std=c11 -Wall -Wextra -Werror -pedantic ^
  -I"%SRC%\actuator" ^
  "%HERE%test_motor_position_guard.c" ^
  "%SRC%\actuator\motor_position_guard.c" ^
  -o "%OUT%\test_motor_position_guard.exe"
if errorlevel 1 exit /b 1
"%OUT%\test_motor_position_guard.exe"
if errorlevel 1 exit /b 1

%CC% -O2 -std=c11 -Wall -Wextra -Werror -pedantic ^
  -I"%SRC%\actuator" ^
  "%HERE%test_tb6612_driver.c" ^
  "%SRC%\actuator\tb6612_driver.c" ^
  -lm -o "%OUT%\test_tb6612_driver.exe"
if errorlevel 1 exit /b 1
"%OUT%\test_tb6612_driver.exe"
if errorlevel 1 exit /b 1

%CC% -O2 -std=c11 -Wall -Wextra -Werror -pedantic ^
  -I"%HERE%fakes" -I"%STM32_SRC%" -I"%SRC%\actuator" ^
  "%HERE%test_stm32_tb6612_hal.c" ^
  "%STM32_SRC%\stm32_tb6612_hal.c" ^
  -o "%OUT%\test_stm32_tb6612_hal.exe"
if errorlevel 1 exit /b 1
"%OUT%\test_stm32_tb6612_hal.exe"
if errorlevel 1 exit /b 1

%CC% -O2 -std=c11 -Wall -Wextra -Werror -pedantic ^
  -I"%HERE%fakes" -I"%STM32_SRC%" -I"%SRC%\actuator" -I"%SRC%\control" ^
  -c "%ROOT%\stm32_motor_control_20260823\example\stm32_motor_integration_example.c" ^
  -o "%OUT%\stm32_motor_integration_example.o"
if errorlevel 1 exit /b 1
echo STM32 motor integration example strict syntax: PASS

%CC% -O2 -std=c11 -Wall -Wextra -Werror -pedantic ^
  -I"%SRC%\actuator" ^
  "%HERE%test_motor_actuator_chain.c" ^
  "%SRC%\actuator\quadrature_encoder.c" ^
  "%SRC%\actuator\motor_position_guard.c" ^
  "%SRC%\actuator\tb6612_driver.c" ^
  -lm -o "%OUT%\test_motor_actuator_chain.exe"
if errorlevel 1 exit /b 1
"%OUT%\test_motor_actuator_chain.exe"
if errorlevel 1 exit /b 1

endlocal
