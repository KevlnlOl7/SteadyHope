#ifndef TB6612_DRIVER_H
#define TB6612_DRIVER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    TB6612_DRIVER_FAULT_NONE = 0,
    TB6612_DRIVER_FAULT_NOT_INITIALIZED = 1,
    TB6612_DRIVER_FAULT_CONFIG = 2,
    TB6612_DRIVER_FAULT_DIRECTION = 3,
    TB6612_DRIVER_FAULT_DUTY = 4,
    TB6612_DRIVER_FAULT_PERMISSION = 5,
    TB6612_DRIVER_FAULT_STATE = 6
} Tb6612DriverFault;

typedef enum {
    TB6612_DRIVER_ERROR = -1,
    TB6612_DRIVER_SAFE = 0,
    TB6612_DRIVER_ACTIVE = 1
} Tb6612DriverResult;

/*
 * There are deliberately no product defaults.  Every value must come from
 * the reviewed STM32 timer configuration and bench evidence.
 *
 * pwm_full_scale_ccr is the PWM denominator and the compare value for 100%
 * duty.  For STM32 edge-aligned PWM it must be ARR + 1.  It must agree with
 * the timer/HAL adapter configuration.
 *
 * release_ain1_level selects the physical polarity without changing the
 * public direction meaning:
 *   direction +1: release cable
 *   direction -1: take up cable
 */
typedef struct {
    uint32_t pwm_full_scale_ccr;
    double max_duty_fraction;
    uint16_t reversal_dead_ticks;
    uint8_t release_ain1_level;
} Tb6612DriverConfig;

typedef struct {
    uint32_t ccr;
    uint16_t reversal_dead_ticks_remaining;
    int8_t direction;
    uint8_t ain1;
    uint8_t ain2;
    uint8_t stby;
    uint8_t fault;
} Tb6612Output;

typedef struct {
    Tb6612DriverConfig config;
    Tb6612DriverConfig initialized_config;
    uint64_t runtime_guard[2];
    uint16_t reversal_dead_ticks_remaining;
    uint16_t safe_ticks_since_energized;
    int8_t last_energized_direction;
    int8_t pending_direction;
    uint8_t initialized;
    uint8_t current_fault;
} Tb6612Driver;

uint8_t TB6612Driver_ConfigIsValid(const Tb6612DriverConfig *config);

Tb6612DriverResult TB6612Driver_Init(
    Tb6612Driver *driver,
    const Tb6612DriverConfig *config,
    Tb6612Output *output);

/*
 * A permitted active command requires direction to be +1 or -1 and duty to
 * be finite in (0, max_duty_fraction].  Zero duty is a safe stop.
 *
 * With permission == 0, direction may additionally be zero so an upstream
 * fail-closed command can pass through unchanged.  Duty must still be finite
 * and in range.  Any invalid input, configuration, or runtime state returns
 * ERROR, emits a safe output, and latches the driver uninitialized.  The
 * caller must clear the upstream fault and explicitly call Init again.
 *
 * Every consecutive SAFE output after an energized command counts toward
 * reversal_dead_ticks.  An opposite active request receives credit for SAFE
 * ticks already imposed upstream; the driver emits only the missing ticks.
 * A direct reversal with no preceding SAFE tick still receives the complete
 * configured dead time.  Any active output resets the accumulated credit.
 */
Tb6612DriverResult TB6612Driver_Update(
    Tb6612Driver *driver,
    int8_t direction,
    double duty_fraction,
    uint8_t permission,
    Tb6612Output *output);

#ifdef __cplusplus
}
#endif

#endif
