#ifndef MOTOR_POSITION_GUARD_H
#define MOTOR_POSITION_GUARD_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Direction is defined at the output shaft/cable:
 *
 *   RELEASE (+1): encoder count must increase (cable is released)
 *   STOP     ( 0): bridge must be disabled
 *   TAKE_UP  (-1): encoder count must decrease (cable is taken up)
 *
 * The encoder polarity must be calibrated to this convention before this
 * guard is promoted to target firmware.
 */
typedef enum {
    MOTOR_POSITION_DIRECTION_TAKE_UP = -1,
    MOTOR_POSITION_DIRECTION_STOP = 0,
    MOTOR_POSITION_DIRECTION_RELEASE = 1
} MotorPositionDirection;

typedef enum {
    MOTOR_POSITION_FAULT_NONE = 0,
    MOTOR_POSITION_FAULT_NOT_INITIALIZED = 1,
    MOTOR_POSITION_FAULT_CONFIG = 2,
    MOTOR_POSITION_FAULT_NOT_ZEROED = 3,
    MOTOR_POSITION_FAULT_ZERO_WHILE_ACTIVE = 4,
    MOTOR_POSITION_FAULT_INPUT = 5,
    MOTOR_POSITION_FAULT_ENCODER_INVALID = 6,
    MOTOR_POSITION_FAULT_ENCODER_JUMP = 7,
    MOTOR_POSITION_FAULT_RELEASE_LIMIT = 8,
    MOTOR_POSITION_FAULT_TAKEUP_LIMIT = 9,
    MOTOR_POSITION_FAULT_WRONG_DIRECTION = 10,
    MOTOR_POSITION_FAULT_NO_MOTION = 11,
    MOTOR_POSITION_FAULT_ACTIVE_TIMEOUT = 12,
    MOTOR_POSITION_FAULT_STATE = 13
} MotorPositionFault;

/*
 * There are deliberately no product defaults.  Every field is a reviewed,
 * bench-derived input in encoder x4 counts and 100 Hz (or caller-defined)
 * control ticks.  Unit-test values are fixtures only.
 *
 * The configured travel limits must include a separately measured stopping
 * margin; this software can only react at the next call to Update().
 */
typedef struct {
    uint32_t release_limit_counts;
    uint32_t takeup_limit_counts;
    uint32_t max_encoder_step_counts;
    uint32_t min_motion_counts_per_window;
    uint32_t wrong_direction_tolerance_counts;
    uint32_t motion_window_active_ticks;
    uint32_t max_active_ticks;
} MotorPositionGuardConfig;

typedef struct {
    MotorPositionGuardConfig config;
    MotorPositionGuardConfig initialized_config;
    int32_t zero_count;
    int32_t previous_count;
    int64_t relative_position_counts;
    uint64_t expected_motion_counts;
    uint64_t reverse_motion_counts;
    uint32_t motion_window_active_ticks;
    uint32_t active_ticks;
    uint32_t fault_count;
    int8_t motion_direction;
    int8_t last_authorized_direction;
    uint8_t initialized;
    uint8_t zeroed;
    uint8_t previous_bridge_enabled;
    uint8_t fault_latched;
    uint8_t fault;
} MotorPositionGuard;

typedef struct {
    int64_t relative_position_counts;
    uint32_t motion_window_active_ticks;
    uint32_t active_ticks;
    uint32_t fault_count;
    int8_t direction;
    uint8_t bridge_enable;
    uint8_t zeroed;
    uint8_t fault_latched;
    uint8_t fault;
} MotorPositionGuardOutput;

uint8_t MotorPositionGuard_ConfigIsValid(
    const MotorPositionGuardConfig *config);

/* Initialization never establishes a position reference or permits motion. */
uint8_t MotorPositionGuard_Init(MotorPositionGuard *guard,
                                const MotorPositionGuardConfig *config);

/*
 * This is the only recovery operation for a runtime fault.  It succeeds only
 * when the caller positively confirms that the physical H-bridge is off and
 * the encoder sample is valid.  The caller must independently ensure that
 * the mechanism is at its real neutral position; software cannot infer that.
 */
uint8_t MotorPositionGuard_SetZero(MotorPositionGuard *guard,
                                   int32_t encoder_count,
                                   uint8_t encoder_valid,
                                   uint8_t bridge_is_off);

/*
 * Processes one encoder sample and authorizes (or rejects) the requested
 * abstract bridge state.  bridge_requested and encoder_valid are strict
 * booleans.  encoder_valid must be one only when the quadrature decoder is
 * initialized and neither its invalid-transition latch nor overflow latch is
 * set.  An enabled request requires direction to be RELEASE or TAKE_UP; a
 * disabled request requires STOP.  Stopping clears a partial motion-check
 * window, so wrong/no-motion is evaluated over consecutive active intervals.
 * The return value equals the published bridge_enable value.
 *
 * An invalid/jumped encoder sample, travel violation, wrong/no motion,
 * unsafe direct reversal, or active timeout disables the bridge in this call
 * and latches the fault.  Only a later successful SetZero() can recover it.
 */
uint8_t MotorPositionGuard_Update(MotorPositionGuard *guard,
                                  int32_t encoder_count,
                                  uint8_t encoder_valid,
                                  int8_t requested_direction,
                                  uint8_t bridge_requested,
                                  MotorPositionGuardOutput *output);

#ifdef __cplusplus
}
#endif

#endif
