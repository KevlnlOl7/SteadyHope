#ifndef MOTOR_COMMAND_MAPPER_H
#define MOTOR_COMMAND_MAPPER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MOTOR_MAPPER_FAULT_NONE = 0,
    MOTOR_MAPPER_FAULT_NOT_INITIALIZED = 1,
    MOTOR_MAPPER_FAULT_CONFIG = 2,
    MOTOR_MAPPER_FAULT_INPUT = 3,
    MOTOR_MAPPER_FAULT_DRIVER = 4,
    MOTOR_MAPPER_FAULT_INHIBIT = 5,
    MOTOR_MAPPER_FAULT_NUMERIC = 6
} MotorCommandMapperFault;

/*
 * Every numeric value is a bench-derived design input.  This module has no
 * product default and shall not be initialized from an unreviewed example.
 */
typedef struct {
    double deadband_dps;
    double gain_duty_fraction_per_dps;
    double max_duty_fraction;
    double max_duty_step_per_tick;
    double max_abs_request_dps;
    uint16_t reversal_dead_ticks;
    int8_t direction_polarity;
} MotorCommandMapperConfig;

typedef struct {
    MotorCommandMapperConfig config;
    MotorCommandMapperConfig initialized_config;
    double duty_fraction;
    uint64_t runtime_guard[3];
    uint32_t config_fingerprint;
    uint32_t fault_count;
    uint16_t dead_ticks_remaining;
    int8_t direction;
    int8_t last_energized_direction;
    uint8_t initialized;
    uint8_t current_fault;
    uint8_t last_fault;
} MotorCommandMapper;

typedef struct {
    double duty_fraction;
    uint32_t fault_count;
    uint32_t active_inhibit_flags;
    uint16_t dead_ticks_remaining;
    int8_t direction;
    uint8_t bridge_enable;
    uint8_t current_fault;
    uint8_t last_fault;
} MotorCommandOutput;

uint8_t MotorCommandMapper_ConfigIsValid(
    const MotorCommandMapperConfig *config);
uint32_t MotorCommandMapper_ConfigFingerprint(
    const MotorCommandMapperConfig *config);

uint8_t MotorCommandMapper_Init(MotorCommandMapper *mapper,
                                const MotorCommandMapperConfig *config,
                                const MotorCommandMapperConfig *approved_config);

/*
 * Produces an abstract direction and duty fraction only.  It does not drive
 * GPIO, a timer, an H-bridge, or authorize connection to a motor.
 */
uint8_t MotorCommandMapper_Update(MotorCommandMapper *mapper,
                                  double compensation_request_dps,
                                  uint8_t actuation_permitted,
                                  uint8_t driver_fault,
                                  uint32_t inhibit_flags,
                                  MotorCommandOutput *output);

#ifdef __cplusplus
}
#endif

#endif
