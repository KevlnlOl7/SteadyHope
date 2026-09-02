#include <stdio.h>

#include "motor_bench_config.h"
#include "motor_command_mapper.h"
#include "tb6612_driver.h"

int main(void)
{
    MotorCommandMapper mapper;
    MotorCommandOutput command;
    Tb6612Driver driver;
    Tb6612Output output;
    MotorCommandMapperConfig mapper_config = {
        MOTOR_COMMAND_DEADBAND_DPS,
        MOTOR_COMMAND_GAIN_DUTY_FRACTION_PER_DPS,
        MOTOR_COMMAND_MAX_DUTY_FRACTION,
        MOTOR_COMMAND_MAX_DUTY_STEP_PER_TICK,
        MOTOR_COMMAND_MAX_ABS_REQUEST_DPS,
        MOTOR_MAPPER_REVERSAL_DEAD_TICKS,
        MOTOR_COMMAND_DIRECTION_POLARITY
    };
    Tb6612DriverConfig driver_config = {
        MOTOR_PWM_FULL_SCALE_CCR,
        MOTOR_COMMAND_MAX_DUTY_FRACTION,
        MOTOR_DRIVER_REVERSAL_DEAD_TICKS,
        MOTOR_RELEASE_AIN1_LEVEL
    };

    if ((MOTOR_POWERED_BENCH_MODE != 1U) ||
        (MOTOR_BENCH_CONFIG_APPROVED != 1U) ||
        (MOTOR_DEFAULT_RUNTIME_ARMED != 1U) ||
        (MOTOR_DEFAULT_INTENSITY_PERCENT != 100U) ||
        (MOTOR_MAX_ACTIVE_CCR != MOTOR_PWM_FULL_SCALE_CCR) ||
        (MotorCommandMapper_ConfigIsValid(&mapper_config) != 1U) ||
        (TB6612Driver_ConfigIsValid(&driver_config) != 1U) ||
        (MotorCommandMapper_Init(
             &mapper, &mapper_config, &mapper_config) != 1U) ||
        (TB6612Driver_Init(
             &driver, &driver_config, &output) != TB6612_DRIVER_SAFE)) {
        fprintf(stderr, "powered bench config initialization: FAIL\n");
        return 1;
    }

    if ((MotorCommandMapper_Update(
             &mapper, 2.0, 1U, 0U, 0U, &command) != 1U) ||
        (command.bridge_enable != 1U) ||
        (command.direction != 1) ||
        (command.duty_fraction != 1.0) ||
        (TB6612Driver_Update(
             &driver, command.direction, command.duty_fraction,
             command.bridge_enable, &output) != TB6612_DRIVER_ACTIVE) ||
        (output.ccr != MOTOR_PWM_FULL_SCALE_CCR) ||
        (output.ccr > MOTOR_MAX_ACTIVE_CCR) ||
        (output.stby != 1U) ||
        (output.ain1 != MOTOR_RELEASE_AIN1_LEVEL) ||
        (output.ain2 == output.ain1)) {
        fprintf(stderr, "powered bench active output: FAIL\n");
        return 1;
    }

    puts("powered bench config and full-scale active chain: PASS");
    return 0;
}
