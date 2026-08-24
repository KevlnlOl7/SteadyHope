#include "motor_position_guard.h"

#include <limits.h>
#include <stddef.h>
#include <string.h>

static uint8_t direction_is_valid(int8_t direction)
{
    return (uint8_t)((direction == MOTOR_POSITION_DIRECTION_TAKE_UP) ||
                     (direction == MOTOR_POSITION_DIRECTION_STOP) ||
                     (direction == MOTOR_POSITION_DIRECTION_RELEASE));
}

static uint8_t config_equal(const MotorPositionGuardConfig *left,
                            const MotorPositionGuardConfig *right)
{
    return (uint8_t)(
        (left->release_limit_counts == right->release_limit_counts) &&
        (left->takeup_limit_counts == right->takeup_limit_counts) &&
        (left->max_encoder_step_counts ==
         right->max_encoder_step_counts) &&
        (left->min_motion_counts_per_window ==
         right->min_motion_counts_per_window) &&
        (left->wrong_direction_tolerance_counts ==
         right->wrong_direction_tolerance_counts) &&
        (left->motion_window_active_ticks ==
         right->motion_window_active_ticks) &&
        (left->max_active_ticks == right->max_active_ticks));
}

uint8_t MotorPositionGuard_ConfigIsValid(
    const MotorPositionGuardConfig *config)
{
    uint64_t maximum_window_motion;

    if (config == NULL) {
        return 0U;
    }
    if ((config->release_limit_counts == 0U) ||
        (config->release_limit_counts > (uint32_t)INT32_MAX) ||
        (config->takeup_limit_counts == 0U) ||
        (config->takeup_limit_counts > (uint32_t)INT32_MAX) ||
        (config->max_encoder_step_counts == 0U) ||
        (config->max_encoder_step_counts > (uint32_t)INT32_MAX) ||
        (config->min_motion_counts_per_window == 0U) ||
        (config->motion_window_active_ticks == 0U) ||
        (config->max_active_ticks == 0U) ||
        (config->max_active_ticks <
         config->motion_window_active_ticks)) {
        return 0U;
    }

    /* The product of two uint32_t values is representable in uint64_t. */
    maximum_window_motion =
        (uint64_t)config->max_encoder_step_counts *
        (uint64_t)config->motion_window_active_ticks;
    if (((uint64_t)config->min_motion_counts_per_window >
         maximum_window_motion) ||
        ((uint64_t)config->wrong_direction_tolerance_counts >
         maximum_window_motion)) {
        return 0U;
    }
    return 1U;
}

static void clear_motion_window(MotorPositionGuard *guard)
{
    guard->expected_motion_counts = 0U;
    guard->reverse_motion_counts = 0U;
    guard->motion_window_active_ticks = 0U;
    guard->motion_direction = MOTOR_POSITION_DIRECTION_STOP;
}

static void force_safe_state(MotorPositionGuard *guard)
{
    guard->active_ticks = 0U;
    guard->previous_bridge_enabled = 0U;
    guard->last_authorized_direction = MOTOR_POSITION_DIRECTION_STOP;
    clear_motion_window(guard);
}

static void increment_saturating_u32(uint32_t *value)
{
    if (*value < UINT32_MAX) {
        (*value)++;
    }
}

static uint64_t add_saturating_u64(uint64_t left, uint64_t right)
{
    if (right > (UINT64_MAX - left)) {
        return UINT64_MAX;
    }
    return left + right;
}

static void clear_output(MotorPositionGuardOutput *output)
{
    if (output != NULL) {
        memset(output, 0, sizeof(*output));
    }
}

static void publish_status(const MotorPositionGuard *guard,
                           MotorPositionGuardOutput *output)
{
    output->relative_position_counts = guard->relative_position_counts;
    output->motion_window_active_ticks =
        guard->motion_window_active_ticks;
    output->active_ticks = guard->active_ticks;
    output->fault_count = guard->fault_count;
    output->zeroed = guard->zeroed;
    output->fault_latched = guard->fault_latched;
    output->fault = guard->fault;
}

static uint8_t latch_fault(MotorPositionGuard *guard,
                           MotorPositionFault fault,
                           MotorPositionGuardOutput *output)
{
    if (guard->fault_latched == 0U) {
        increment_saturating_u32(&guard->fault_count);
        guard->fault = (uint8_t)fault;
    }
    guard->fault_latched = 1U;
    guard->zeroed = 0U;
    force_safe_state(guard);
    clear_output(output);
    if (output != NULL) {
        publish_status(guard, output);
    }
    return 0U;
}

static uint8_t runtime_config_is_valid(const MotorPositionGuard *guard)
{
    return (uint8_t)(
        (MotorPositionGuard_ConfigIsValid(&guard->config) != 0U) &&
        (config_equal(&guard->config, &guard->initialized_config) != 0U));
}

uint8_t MotorPositionGuard_Init(MotorPositionGuard *guard,
                                const MotorPositionGuardConfig *config)
{
    if (guard == NULL) {
        return 0U;
    }
    memset(guard, 0, sizeof(*guard));
    if (MotorPositionGuard_ConfigIsValid(config) == 0U) {
        guard->fault_latched = 1U;
        guard->fault = (uint8_t)MOTOR_POSITION_FAULT_CONFIG;
        guard->fault_count = 1U;
        return 0U;
    }

    guard->config = *config;
    guard->initialized_config = *config;
    guard->initialized = 1U;
    return 1U;
}

uint8_t MotorPositionGuard_SetZero(MotorPositionGuard *guard,
                                   int32_t encoder_count,
                                   uint8_t encoder_valid,
                                   uint8_t bridge_is_off)
{
    if (guard == NULL) {
        return 0U;
    }
    if (guard->initialized != 1U) {
        guard->fault_latched = 1U;
        guard->fault = (uint8_t)MOTOR_POSITION_FAULT_NOT_INITIALIZED;
        increment_saturating_u32(&guard->fault_count);
        guard->zeroed = 0U;
        force_safe_state(guard);
        return 0U;
    }
    if (runtime_config_is_valid(guard) == 0U) {
        guard->initialized = 0U;
        guard->fault_latched = 1U;
        guard->fault = (uint8_t)MOTOR_POSITION_FAULT_CONFIG;
        increment_saturating_u32(&guard->fault_count);
        guard->zeroed = 0U;
        force_safe_state(guard);
        return 0U;
    }
    if (bridge_is_off != 1U) {
        (void)latch_fault(guard,
                          MOTOR_POSITION_FAULT_ZERO_WHILE_ACTIVE, NULL);
        return 0U;
    }
    if (encoder_valid != 1U) {
        (void)latch_fault(guard, MOTOR_POSITION_FAULT_ENCODER_INVALID,
                          NULL);
        return 0U;
    }

    guard->zero_count = encoder_count;
    guard->previous_count = encoder_count;
    guard->relative_position_counts = 0;
    guard->zeroed = 1U;
    guard->fault_latched = 0U;
    guard->fault = (uint8_t)MOTOR_POSITION_FAULT_NONE;
    force_safe_state(guard);
    return 1U;
}

static uint8_t dynamic_state_is_valid(const MotorPositionGuard *guard)
{
    uint64_t maximum_accumulated_motion;

    if ((guard->zeroed > 1U) ||
        (guard->previous_bridge_enabled > 1U) ||
        (guard->fault_latched > 1U) ||
        (guard->fault > (uint8_t)MOTOR_POSITION_FAULT_STATE) ||
        (direction_is_valid(guard->motion_direction) == 0U) ||
        (direction_is_valid(guard->last_authorized_direction) == 0U) ||
        (guard->active_ticks > guard->config.max_active_ticks) ||
        (guard->motion_window_active_ticks >=
         guard->config.motion_window_active_ticks)) {
        return 0U;
    }
    if ((guard->previous_bridge_enabled != 0U) &&
        ((guard->last_authorized_direction ==
          MOTOR_POSITION_DIRECTION_STOP) ||
         (guard->active_ticks == 0U))) {
        return 0U;
    }
    if ((guard->previous_bridge_enabled == 0U) &&
        (guard->active_ticks != 0U)) {
        return 0U;
    }
    if ((guard->motion_window_active_ticks == 0U) &&
        ((guard->expected_motion_counts != 0U) ||
         (guard->reverse_motion_counts != 0U))) {
        return 0U;
    }
    if ((guard->motion_window_active_ticks != 0U) &&
        (guard->motion_direction == MOTOR_POSITION_DIRECTION_STOP)) {
        return 0U;
    }

    maximum_accumulated_motion =
        (uint64_t)guard->config.max_encoder_step_counts *
        (uint64_t)guard->motion_window_active_ticks;
    if ((guard->expected_motion_counts > maximum_accumulated_motion) ||
        (guard->reverse_motion_counts > maximum_accumulated_motion)) {
        return 0U;
    }
    return 1U;
}

static uint64_t magnitude_i64(int64_t value)
{
    /* All callers pass an int32_t difference, so INT64_MIN is impossible. */
    return (uint64_t)((value < 0) ? -value : value);
}

static uint8_t accumulate_previous_motion(
    MotorPositionGuard *guard,
    int64_t encoder_delta,
    MotorPositionGuardOutput *output)
{
    uint64_t magnitude;
    uint64_t net_motion;
    uint8_t delta_is_expected;

    if (guard->previous_bridge_enabled == 0U) {
        return 1U;
    }
    if ((guard->last_authorized_direction ==
         MOTOR_POSITION_DIRECTION_STOP) ||
        (guard->motion_direction != guard->last_authorized_direction)) {
        (void)latch_fault(guard, MOTOR_POSITION_FAULT_STATE, output);
        return 0U;
    }

    magnitude = magnitude_i64(encoder_delta);
    delta_is_expected = (uint8_t)(
        ((encoder_delta > 0) &&
         (guard->motion_direction ==
          MOTOR_POSITION_DIRECTION_RELEASE)) ||
        ((encoder_delta < 0) &&
         (guard->motion_direction ==
          MOTOR_POSITION_DIRECTION_TAKE_UP)));

    if (encoder_delta != 0) {
        if (delta_is_expected != 0U) {
            guard->expected_motion_counts = add_saturating_u64(
                guard->expected_motion_counts, magnitude);
        } else {
            guard->reverse_motion_counts = add_saturating_u64(
                guard->reverse_motion_counts, magnitude);
        }
    }

    /* Stored state is always below the configured value before this step. */
    guard->motion_window_active_ticks++;
    if (guard->motion_window_active_ticks <
        guard->config.motion_window_active_ticks) {
        return 1U;
    }

    if (guard->reverse_motion_counts >
        guard->expected_motion_counts) {
        net_motion = guard->reverse_motion_counts -
                     guard->expected_motion_counts;
        if (net_motion >
            (uint64_t)guard->config.wrong_direction_tolerance_counts) {
            (void)latch_fault(guard,
                              MOTOR_POSITION_FAULT_WRONG_DIRECTION,
                              output);
            return 0U;
        }
        net_motion = 0U;
    } else {
        net_motion = guard->expected_motion_counts -
                     guard->reverse_motion_counts;
    }

    if (net_motion <
        (uint64_t)guard->config.min_motion_counts_per_window) {
        (void)latch_fault(guard, MOTOR_POSITION_FAULT_NO_MOTION,
                          output);
        return 0U;
    }

    clear_motion_window(guard);
    return 1U;
}

static uint8_t command_is_valid(int8_t direction,
                                uint8_t bridge_requested)
{
    if (bridge_requested > 1U) {
        return 0U;
    }
    if (bridge_requested == 0U) {
        return (uint8_t)(direction == MOTOR_POSITION_DIRECTION_STOP);
    }
    return (uint8_t)((direction == MOTOR_POSITION_DIRECTION_RELEASE) ||
                     (direction == MOTOR_POSITION_DIRECTION_TAKE_UP));
}

uint8_t MotorPositionGuard_Update(MotorPositionGuard *guard,
                                  int32_t encoder_count,
                                  uint8_t encoder_valid,
                                  int8_t requested_direction,
                                  uint8_t bridge_requested,
                                  MotorPositionGuardOutput *output)
{
    int64_t encoder_delta;
    int64_t relative_position;

    clear_output(output);
    if (guard == NULL) {
        return 0U;
    }
    if (output == NULL) {
        return latch_fault(guard, MOTOR_POSITION_FAULT_INPUT, NULL);
    }
    if (guard->initialized != 1U) {
        return latch_fault(guard,
                           MOTOR_POSITION_FAULT_NOT_INITIALIZED, output);
    }
    if (runtime_config_is_valid(guard) == 0U) {
        guard->initialized = 0U;
        return latch_fault(guard, MOTOR_POSITION_FAULT_CONFIG, output);
    }
    if (guard->fault_latched != 0U) {
        publish_status(guard, output);
        return 0U;
    }
    if (guard->zeroed != 1U) {
        return latch_fault(guard, MOTOR_POSITION_FAULT_NOT_ZEROED,
                           output);
    }
    if (dynamic_state_is_valid(guard) == 0U) {
        return latch_fault(guard, MOTOR_POSITION_FAULT_STATE, output);
    }
    if (encoder_valid != 1U) {
        return latch_fault(guard,
                           MOTOR_POSITION_FAULT_ENCODER_INVALID, output);
    }
    if (command_is_valid(requested_direction,
                         bridge_requested) == 0U) {
        return latch_fault(guard, MOTOR_POSITION_FAULT_INPUT, output);
    }

    /* int32_t-to-int64_t promotion makes both differences overflow-safe. */
    encoder_delta = (int64_t)encoder_count -
                    (int64_t)guard->previous_count;
    relative_position = (int64_t)encoder_count -
                        (int64_t)guard->zero_count;
    guard->relative_position_counts = relative_position;

    if (magnitude_i64(encoder_delta) >
        (uint64_t)guard->config.max_encoder_step_counts) {
        return latch_fault(guard, MOTOR_POSITION_FAULT_ENCODER_JUMP,
                           output);
    }
    if (relative_position >
        (int64_t)guard->config.release_limit_counts) {
        return latch_fault(guard, MOTOR_POSITION_FAULT_RELEASE_LIMIT,
                           output);
    }
    if (relative_position <
        -(int64_t)guard->config.takeup_limit_counts) {
        return latch_fault(guard, MOTOR_POSITION_FAULT_TAKEUP_LIMIT,
                           output);
    }

    guard->previous_count = encoder_count;
    if (accumulate_previous_motion(guard, encoder_delta, output) == 0U) {
        return 0U;
    }

    if (bridge_requested == 0U) {
        guard->previous_bridge_enabled = 0U;
        guard->last_authorized_direction =
            MOTOR_POSITION_DIRECTION_STOP;
        guard->active_ticks = 0U;
        clear_motion_window(guard);
        publish_status(guard, output);
        return 0U;
    }

    if ((guard->previous_bridge_enabled != 0U) &&
        (requested_direction != guard->last_authorized_direction)) {
        return latch_fault(guard, MOTOR_POSITION_FAULT_INPUT, output);
    }
    if ((requested_direction == MOTOR_POSITION_DIRECTION_RELEASE) &&
        (relative_position >=
         (int64_t)guard->config.release_limit_counts)) {
        return latch_fault(guard, MOTOR_POSITION_FAULT_RELEASE_LIMIT,
                           output);
    }
    if ((requested_direction == MOTOR_POSITION_DIRECTION_TAKE_UP) &&
        (relative_position <=
         -(int64_t)guard->config.takeup_limit_counts)) {
        return latch_fault(guard, MOTOR_POSITION_FAULT_TAKEUP_LIMIT,
                           output);
    }

    if (guard->motion_direction != requested_direction) {
        clear_motion_window(guard);
        guard->motion_direction = requested_direction;
    }
    if (guard->active_ticks >= guard->config.max_active_ticks) {
        return latch_fault(guard,
                           MOTOR_POSITION_FAULT_ACTIVE_TIMEOUT, output);
    }
    guard->active_ticks++;
    guard->previous_bridge_enabled = 1U;
    guard->last_authorized_direction = requested_direction;

    output->direction = requested_direction;
    output->bridge_enable = 1U;
    publish_status(guard, output);
    return 1U;
}
