#ifndef MOTOR_BENCH_CONFIG_H
#define MOTOR_BENCH_CONFIG_H

/*
 * POWERED BENCH PROFILE
 *
 * This profile is intentionally enabled for the current off-body motor test.
 * It boots armed, starts at 100 % intensity, allows the complete TIM1 range,
 * and bypasses encoder homing/position vetoes.  Gate, estimator validity,
 * fresh-sample, scheduler, driver and HAL checks still define whether an
 * output may be applied.
 *
 * Ryan/Wei-Zhe tuning entry point: change values in this file, not the pin
 * wiring or generated CubeMX sections in main.c.
 */
#define MOTOR_POWERED_BENCH_MODE                    1U
#define MOTOR_BENCH_CONFIG_APPROVED                 1U
#define MOTOR_DEFAULT_RUNTIME_ARMED                 1U
#define MOTOR_DEFAULT_INTENSITY_PERCENT             100U

/* 0=X, 1=Y, 2=Z.  Change this when the mounted IMU tremor axis differs. */
#define MOTOR_TREMOR_INPUT_AXIS                     0U

/* May be changed to SUPPRESSION_ESTIMATOR_BMFLC for an A/B bench run. */
#define MOTOR_SUPPRESSION_ESTIMATOR                 \
    SUPPRESSION_ESTIMATOR_EHWFLC_KF

/* TIM1_CH1: timer clock 64 MHz, PSC=0, ARR=3199 -> 20 kHz PWM. */
#define MOTOR_PWM_FULL_SCALE_CCR                    3200U
#define MOTOR_MAX_ACTIVE_CCR                        3200U

/* compensation_request_dps -> signed duty fraction. */
#define MOTOR_COMMAND_DEADBAND_DPS                  0.0
#define MOTOR_COMMAND_GAIN_DUTY_FRACTION_PER_DPS   1.0
#define MOTOR_COMMAND_MAX_DUTY_FRACTION             1.0
#define MOTOR_COMMAND_MAX_DUTY_STEP_PER_TICK        1.0
#define MOTOR_COMMAND_MAX_ABS_REQUEST_DPS           2048.0

/* One 100 Hz safe tick is retained in each software reversal layer. */
#define MOTOR_MAPPER_REVERSAL_DEAD_TICKS            1U
#define MOTOR_DRIVER_REVERSAL_DEAD_TICKS            1U

/* Change only MOTOR_COMMAND_DIRECTION_POLARITY to invert compensation sign. */
#define MOTOR_COMMAND_DIRECTION_POLARITY             1

/* Raw bridge convention: direction +1 -> AIN1=1, AIN2=0. */
#define MOTOR_RELEASE_AIN1_LEVEL                    1U

/* Encoder is telemetry-only in MOTOR_POWERED_BENCH_MODE. */
#define MOTOR_ENCODER_COUNT_POLARITY                 1

#endif
