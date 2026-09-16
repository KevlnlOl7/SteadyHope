#ifndef MOTOR_BENCH_CONFIG_H
#define MOTOR_BENCH_CONFIG_H

/* Encoder-position tremor bench profile. */
#define MOTOR_POWERED_BENCH_MODE                    1U
#define MOTOR_BENCH_CONFIG_APPROVED                 1U
#define MOTOR_DEFAULT_RUNTIME_ARMED                 1U
#define MOTOR_DEFAULT_INTENSITY_PERCENT             100U

/* 0=X, 1=Y, 2=Z. */
#define MOTOR_TREMOR_INPUT_AXIS                     0U

#define MOTOR_SUPPRESSION_ESTIMATOR                 \
    SUPPRESSION_ESTIMATOR_EHWFLC_KF

/* TIM1_CH1: 20 kHz, ARR=3199.  Position controller requests at most 60%. */
#define MOTOR_PWM_FULL_SCALE_CCR                    3200U
#define MOTOR_MAX_ACTIVE_CCR                        1920U

/* These mapper values are retained for API compatibility.  The revised
 * main.c does not use tremorEstimate sign to command the motor; position
 * control bypasses MotorCommandMapper for the active motion command. */
#define MOTOR_COMMAND_DEADBAND_DPS                  0.8
#define MOTOR_COMMAND_GAIN_DUTY_FRACTION_PER_DPS   0.05
#define MOTOR_COMMAND_MAX_DUTY_FRACTION             0.60
#define MOTOR_COMMAND_MAX_DUTY_STEP_PER_TICK        0.05
#define MOTOR_COMMAND_MAX_ABS_REQUEST_DPS           2048.0

#define MOTOR_MAPPER_REVERSAL_DEAD_TICKS            3U
#define MOTOR_DRIVER_REVERSAL_DEAD_TICKS            3U

#define MOTOR_COMMAND_DIRECTION_POLARITY             1
#define MOTOR_RELEASE_AIN1_LEVEL                    0U
#define MOTOR_ENCODER_COUNT_POLARITY                 1

#if (MOTOR_TREMOR_INPUT_AXIS > 2U)
#error "MOTOR_TREMOR_INPUT_AXIS must be 0(X), 1(Y), or 2(Z)"
#endif

#if (MOTOR_DEFAULT_INTENSITY_PERCENT > 100U)
#error "MOTOR_DEFAULT_INTENSITY_PERCENT must be <= 100"
#endif

#if (MOTOR_MAX_ACTIVE_CCR > MOTOR_PWM_FULL_SCALE_CCR)
#error "MOTOR_MAX_ACTIVE_CCR cannot exceed MOTOR_PWM_FULL_SCALE_CCR"
#endif

#if ((MOTOR_COMMAND_DIRECTION_POLARITY != 1) && \
     (MOTOR_COMMAND_DIRECTION_POLARITY != -1))
#error "MOTOR_COMMAND_DIRECTION_POLARITY must be +1 or -1"
#endif

#if (MOTOR_RELEASE_AIN1_LEVEL > 1U)
#error "MOTOR_RELEASE_AIN1_LEVEL must be 0 or 1"
#endif

#if ((MOTOR_ENCODER_COUNT_POLARITY != 1) && \
     (MOTOR_ENCODER_COUNT_POLARITY != -1))
#error "MOTOR_ENCODER_COUNT_POLARITY must be +1 or -1"
#endif

#endif
