#!/bin/sh
# Build and run the bench-only actuator host tests. Outputs go to TMPDIR.
set -e

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
REPO=$(CDPATH= cd -- "$ROOT/../.." && pwd)
SRC="$ROOT/src"
STM32_SRC="$ROOT/stm32_motor_control_20260823/src/actuator"
CC="${CC:-gcc}"
OUT="${TMPDIR:-/tmp}/steadyhope_handoff_actuator_tests"
mkdir -p "$OUT"

"$CC" -O2 -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$SRC/control" -I"$SRC/gating" -I"$SRC/bmflc" -I"$SRC/ehwflc" \
  "$HERE/test_suppression_control.c" \
  "$SRC/control/suppression_control.c" "$SRC/gating/tremor_gate.c" \
  "$SRC/bmflc/BMFLC_step.c" "$SRC/bmflc/BMFLC_step_data.c" \
  "$SRC/bmflc/BMFLC_step_initialize.c" \
  "$SRC/ehwflc/eHWFLC_KF_step.c" "$SRC/ehwflc/eHWFLC_KF_step_data.c" \
  "$SRC/ehwflc/eHWFLC_KF_step_initialize.c" "$SRC/ehwflc/eye.c" \
  -lm -o "$OUT/test_suppression_control"
"$OUT/test_suppression_control"

"$CC" -O2 -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$SRC/control" -I"$SRC/gating" -I"$SRC/bmflc" -I"$SRC/ehwflc" \
  "$HERE/test_diagnostic_frequency_isolation.c" \
  "$SRC/control/suppression_control.c" "$SRC/gating/tremor_gate.c" \
  -lm -o "$OUT/test_diagnostic_frequency_isolation"
"$OUT/test_diagnostic_frequency_isolation"

"$CC" -O2 -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$SRC/control" \
  "$HERE/test_motor_command_mapper.c" \
  "$SRC/control/motor_command_mapper.c" \
  -lm -o "$OUT/test_motor_command_mapper"
"$OUT/test_motor_command_mapper"

"$CC" -O2 -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$SRC/control" -I"$SRC/gating" -I"$SRC/bmflc" -I"$SRC/ehwflc" \
  "$HERE/test_suppression_pipeline.c" \
  "$SRC/control/suppression_control.c" "$SRC/control/motor_command_mapper.c" \
  "$SRC/gating/tremor_gate.c" \
  "$SRC/bmflc/BMFLC_step.c" "$SRC/bmflc/BMFLC_step_data.c" \
  "$SRC/bmflc/BMFLC_step_initialize.c" \
  "$SRC/ehwflc/eHWFLC_KF_step.c" "$SRC/ehwflc/eHWFLC_KF_step_data.c" \
  "$SRC/ehwflc/eHWFLC_KF_step_initialize.c" "$SRC/ehwflc/eye.c" \
  -lm -o "$OUT/test_suppression_pipeline"
"$OUT/test_suppression_pipeline"

"$CC" -O2 -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$SRC/actuator" \
  "$HERE/test_quadrature_encoder.c" \
  "$SRC/actuator/quadrature_encoder.c" \
  -o "$OUT/test_quadrature_encoder"
"$OUT/test_quadrature_encoder"

"$CC" -O2 -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$SRC/actuator" \
  "$HERE/test_motor_position_guard.c" \
  "$SRC/actuator/motor_position_guard.c" \
  -o "$OUT/test_motor_position_guard"
"$OUT/test_motor_position_guard"

"$CC" -O2 -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$SRC/actuator" \
  "$HERE/test_tb6612_driver.c" \
  "$SRC/actuator/tb6612_driver.c" \
  -lm -o "$OUT/test_tb6612_driver"
"$OUT/test_tb6612_driver"

"$CC" -O2 -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$SRC/actuator" -I"$SRC/control" \
  "$HERE/test_motor_mapper_driver_chain.c" \
  "$SRC/control/motor_command_mapper.c" \
  "$SRC/actuator/tb6612_driver.c" \
  -lm -o "$OUT/test_motor_mapper_driver_chain"
"$OUT/test_motor_mapper_driver_chain"

"$CC" -O2 -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$SRC/actuator" -I"$SRC/control" \
  -I"$REPO/firmware/algo/CM7/Core/Inc" \
  "$HERE/test_powered_bench_config.c" \
  "$SRC/control/motor_command_mapper.c" \
  "$SRC/actuator/tb6612_driver.c" \
  -lm -o "$OUT/test_powered_bench_config"
"$OUT/test_powered_bench_config"

"$CC" -O2 -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$HERE/fakes" -I"$STM32_SRC" -I"$SRC/actuator" \
  "$HERE/test_stm32_tb6612_hal.c" \
  "$STM32_SRC/stm32_tb6612_hal.c" \
  -o "$OUT/test_stm32_tb6612_hal"
"$OUT/test_stm32_tb6612_hal"

"$CC" -O2 -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$HERE/fakes" -I"$STM32_SRC" -I"$SRC/actuator" -I"$SRC/control" \
  -c "$ROOT/stm32_motor_control_20260823/example/stm32_motor_integration_example.c" \
  -o "$OUT/stm32_motor_integration_example.o"
echo "STM32 motor integration example strict syntax: PASS"

"$CC" -O2 -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$SRC/actuator" \
  "$HERE/test_motor_actuator_chain.c" \
  "$SRC/actuator/quadrature_encoder.c" \
  "$SRC/actuator/motor_position_guard.c" \
  "$SRC/actuator/tb6612_driver.c" \
  -lm -o "$OUT/test_motor_actuator_chain"
"$OUT/test_motor_actuator_chain"
