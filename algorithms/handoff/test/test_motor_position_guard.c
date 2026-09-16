#include "motor_position_guard.h"

#include <limits.h>
#include <stdint.h>
#include <stdio.h>

/* Host-test fixture only.  These values are not product settings. */
static MotorPositionGuardConfig fixture_config(void)
{
    MotorPositionGuardConfig config;

    config.release_limit_counts = 100U;
    config.takeup_limit_counts = 80U;
    config.max_encoder_step_counts = 20U;
    config.min_motion_counts_per_window = 6U;
    config.wrong_direction_tolerance_counts = 1U;
    config.motion_window_active_ticks = 3U;
    config.max_active_ticks = 10U;
    return config;
}

static int output_is_bridge_off(const MotorPositionGuardOutput *output)
{
    return (output->bridge_enable == 0U) &&
           (output->direction == MOTOR_POSITION_DIRECTION_STOP);
}

static int init_and_zero(MotorPositionGuard *guard,
                         const MotorPositionGuardConfig *config,
                         int32_t count)
{
    return (MotorPositionGuard_Init(guard, config) != 0U) &&
           (MotorPositionGuard_SetZero(guard, count, 1U, 1U) != 0U);
}

static int test_config_validation(void)
{
    MotorPositionGuard guard;
    MotorPositionGuardConfig config = fixture_config();

    if ((MotorPositionGuard_ConfigIsValid(NULL) != 0U) ||
        (MotorPositionGuard_Init(NULL, &config) != 0U) ||
        (MotorPositionGuard_Init(&guard, NULL) != 0U)) {
        return 0;
    }

#define EXPECT_INVALID(field, value)                                        \
    do {                                                                     \
        config = fixture_config();                                           \
        config.field = (value);                                              \
        if (MotorPositionGuard_ConfigIsValid(&config) != 0U) {               \
            return 0;                                                        \
        }                                                                    \
    } while (0)

    EXPECT_INVALID(release_limit_counts, 0U);
    EXPECT_INVALID(release_limit_counts, (uint32_t)INT32_MAX + 1U);
    EXPECT_INVALID(takeup_limit_counts, 0U);
    EXPECT_INVALID(max_encoder_step_counts, 0U);
    EXPECT_INVALID(max_encoder_step_counts, (uint32_t)INT32_MAX + 1U);
    EXPECT_INVALID(min_motion_counts_per_window, 0U);
    EXPECT_INVALID(motion_window_active_ticks, 0U);
    EXPECT_INVALID(max_active_ticks, 0U);
    EXPECT_INVALID(max_active_ticks, 2U);

#undef EXPECT_INVALID

    config = fixture_config();
    config.max_encoder_step_counts = 1U;
    config.motion_window_active_ticks = 2U;
    config.min_motion_counts_per_window = 3U;
    if (MotorPositionGuard_ConfigIsValid(&config) != 0U) {
        return 0;
    }
    config = fixture_config();
    config.max_encoder_step_counts = 1U;
    config.motion_window_active_ticks = 2U;
    config.wrong_direction_tolerance_counts = 3U;
    if (MotorPositionGuard_ConfigIsValid(&config) != 0U) {
        return 0;
    }

    /* The validation multiplication must remain defined at type limits. */
    config.release_limit_counts = (uint32_t)INT32_MAX;
    config.takeup_limit_counts = (uint32_t)INT32_MAX;
    config.max_encoder_step_counts = (uint32_t)INT32_MAX;
    config.min_motion_counts_per_window = UINT32_MAX;
    config.wrong_direction_tolerance_counts = UINT32_MAX;
    config.motion_window_active_ticks = UINT32_MAX;
    config.max_active_ticks = UINT32_MAX;
    return MotorPositionGuard_ConfigIsValid(&config) != 0U;
}

static int test_explicit_zero_and_recovery(void)
{
    MotorPositionGuard guard;
    MotorPositionGuardConfig config = fixture_config();
    MotorPositionGuardOutput output;

    if (MotorPositionGuard_Init(&guard, &config) == 0U) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 50, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) != 0U) ||
        !output_is_bridge_off(&output) ||
        (output.fault != (uint8_t)MOTOR_POSITION_FAULT_NOT_ZEROED) ||
        (output.fault_latched == 0U)) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 50, 1U, MOTOR_POSITION_DIRECTION_STOP, 0U,
             &output) != 0U) ||
        (output.fault != (uint8_t)MOTOR_POSITION_FAULT_NOT_ZEROED)) {
        return 0;
    }
    if ((MotorPositionGuard_SetZero(&guard, 50, 1U, 0U) != 0U) ||
        (MotorPositionGuard_SetZero(&guard, 50, 1U, 1U) == 0U)) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 50, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (output.zeroed == 0U) || (output.fault_latched != 0U)) {
        return 0;
    }

    /* SetZero may not be used to move the reference while energized. */
    if ((MotorPositionGuard_SetZero(&guard, 51, 1U, 0U) != 0U) ||
        (guard.fault !=
         (uint8_t)MOTOR_POSITION_FAULT_ZERO_WHILE_ACTIVE) ||
        (MotorPositionGuard_SetZero(&guard, 51, 1U, 1U) == 0U)) {
        return 0;
    }
    if ((MotorPositionGuard_SetZero(&guard, 51, 0U, 1U) != 0U) ||
        (guard.fault !=
         (uint8_t)MOTOR_POSITION_FAULT_ENCODER_INVALID)) {
        return 0;
    }
    return MotorPositionGuard_SetZero(&guard, 51, 1U, 1U) != 0U;
}

static int test_direction_and_motion(void)
{
    MotorPositionGuard guard;
    MotorPositionGuardConfig config = fixture_config();
    MotorPositionGuardOutput output;

    if (init_and_zero(&guard, &config, 100) == 0) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 100, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (output.direction != MOTOR_POSITION_DIRECTION_RELEASE)) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 102, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 104, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 106, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (output.relative_position_counts != 6)) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 108, 1U, MOTOR_POSITION_DIRECTION_STOP, 0U,
             &output) != 0U) ||
        !output_is_bridge_off(&output)) {
        return 0;
    }

    if (MotorPositionGuard_SetZero(&guard, 108, 1U, 1U) == 0U) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 108, 1U, MOTOR_POSITION_DIRECTION_TAKE_UP, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 106, 1U, MOTOR_POSITION_DIRECTION_TAKE_UP, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 104, 1U, MOTOR_POSITION_DIRECTION_TAKE_UP, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 102, 1U, MOTOR_POSITION_DIRECTION_TAKE_UP, 1U,
             &output) == 0U)) {
        return 0;
    }
    return (output.direction == MOTOR_POSITION_DIRECTION_TAKE_UP) &&
           (output.relative_position_counts == -6) &&
           (output.fault_latched == 0U);
}

static int test_position_limits(void)
{
    MotorPositionGuard guard;
    MotorPositionGuardConfig config = fixture_config();
    MotorPositionGuardOutput output;

    config.release_limit_counts = 10U;
    config.takeup_limit_counts = 8U;

    if (init_and_zero(&guard, &config, 0) == 0) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 10, 1U, MOTOR_POSITION_DIRECTION_STOP, 0U,
             &output) != 0U) ||
        (output.fault_latched != 0U)) {
        return 0;
    }
    /* At the release boundary, motion back toward neutral is allowed. */
    if (MotorPositionGuard_Update(
            &guard, 10, 1U, MOTOR_POSITION_DIRECTION_TAKE_UP, 1U,
            &output) == 0U) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 9, 1U, MOTOR_POSITION_DIRECTION_STOP, 0U,
             &output) != 0U) ||
        (MotorPositionGuard_SetZero(&guard, 0, 1U, 1U) == 0U)) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 10, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) != 0U) ||
        (output.fault !=
         (uint8_t)MOTOR_POSITION_FAULT_RELEASE_LIMIT)) {
        return 0;
    }

    if (MotorPositionGuard_SetZero(&guard, 0, 1U, 1U) == 0U) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, -8, 1U, MOTOR_POSITION_DIRECTION_TAKE_UP, 1U,
             &output) != 0U) ||
        (output.fault !=
         (uint8_t)MOTOR_POSITION_FAULT_TAKEUP_LIMIT)) {
        return 0;
    }

    if (MotorPositionGuard_SetZero(&guard, 0, 1U, 1U) == 0U) {
        return 0;
    }
    return (MotorPositionGuard_Update(
                &guard, 11, 1U, MOTOR_POSITION_DIRECTION_STOP, 0U,
                &output) == 0U) &&
           (output.fault ==
            (uint8_t)MOTOR_POSITION_FAULT_RELEASE_LIMIT);
}

static int test_encoder_faults_and_integer_extremes(void)
{
    MotorPositionGuard guard;
    MotorPositionGuardConfig config = fixture_config();
    MotorPositionGuardOutput output;

    if (init_and_zero(&guard, &config, 0) == 0) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 0, 0U, MOTOR_POSITION_DIRECTION_STOP, 0U,
             &output) != 0U) ||
        (output.fault !=
         (uint8_t)MOTOR_POSITION_FAULT_ENCODER_INVALID) ||
        (MotorPositionGuard_SetZero(&guard, 0, 1U, 1U) == 0U)) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 21, 1U, MOTOR_POSITION_DIRECTION_STOP, 0U,
             &output) != 0U) ||
        (output.fault !=
         (uint8_t)MOTOR_POSITION_FAULT_ENCODER_JUMP)) {
        return 0;
    }

    config.release_limit_counts = (uint32_t)INT32_MAX;
    config.takeup_limit_counts = (uint32_t)INT32_MAX;
    config.max_encoder_step_counts = (uint32_t)INT32_MAX;
    config.min_motion_counts_per_window = 1U;
    config.wrong_direction_tolerance_counts = 0U;
    config.motion_window_active_ticks = 1U;
    config.max_active_ticks = 2U;
    if (init_and_zero(&guard, &config, INT32_MIN) == 0) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, -1, 1U, MOTOR_POSITION_DIRECTION_STOP, 0U,
             &output) != 0U) ||
        (output.relative_position_counts != (int64_t)INT32_MAX)) {
        return 0;
    }
    if ((MotorPositionGuard_SetZero(&guard, INT32_MIN, 1U, 1U) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, INT32_MAX, 1U, MOTOR_POSITION_DIRECTION_STOP, 0U,
             &output) != 0U) ||
        (output.fault !=
         (uint8_t)MOTOR_POSITION_FAULT_ENCODER_JUMP)) {
        return 0;
    }
    if (MotorPositionGuard_SetZero(&guard, INT32_MAX, 1U, 1U) == 0U) {
        return 0;
    }
    return (MotorPositionGuard_Update(
                &guard, INT32_MIN, 1U,
                MOTOR_POSITION_DIRECTION_STOP, 0U, &output) == 0U) &&
           (output.fault ==
            (uint8_t)MOTOR_POSITION_FAULT_ENCODER_JUMP);
}

static int test_no_motion_wrong_direction_and_stop_reset(void)
{
    MotorPositionGuard guard;
    MotorPositionGuardConfig config = fixture_config();
    MotorPositionGuardOutput output;

    if (init_and_zero(&guard, &config, 0) == 0) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U)) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) != 0U) ||
        (output.fault !=
         (uint8_t)MOTOR_POSITION_FAULT_NO_MOTION)) {
        return 0;
    }

    if (MotorPositionGuard_SetZero(&guard, 0, 1U, 1U) == 0U) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, -2, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, -4, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U)) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, -6, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) != 0U) ||
        (output.fault !=
         (uint8_t)MOTOR_POSITION_FAULT_WRONG_DIRECTION)) {
        return 0;
    }

    if (MotorPositionGuard_SetZero(&guard, 0, 1U, 1U) == 0U) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 2, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 4, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 6, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (output.fault_latched != 0U)) {
        return 0;
    }

    /* A stopped command starts the next burst with a fresh motion window. */
    if (MotorPositionGuard_SetZero(&guard, 0, 1U, 1U) == 0U) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_STOP, 0U,
             &output) != 0U) ||
        (output.motion_window_active_ticks != 0U) ||
        (output.fault_latched != 0U) ||
        (MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U)) {
        return 0;
    }
    return (MotorPositionGuard_Update(
                &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
                &output) == 0U) &&
           (output.fault ==
            (uint8_t)MOTOR_POSITION_FAULT_NO_MOTION) &&
           (output.fault_latched != 0U);
}

static int test_active_timeout_and_unsafe_reversal(void)
{
    MotorPositionGuard guard;
    MotorPositionGuardConfig config = fixture_config();
    MotorPositionGuardOutput output;

    config.min_motion_counts_per_window = 2U;
    config.motion_window_active_ticks = 2U;
    config.max_active_ticks = 3U;
    if (init_and_zero(&guard, &config, 0) == 0) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 1, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 2, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U)) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 3, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) != 0U) ||
        (output.fault !=
         (uint8_t)MOTOR_POSITION_FAULT_ACTIVE_TIMEOUT)) {
        return 0;
    }

    if (MotorPositionGuard_SetZero(&guard, 0, 1U, 1U) == 0U) {
        return 0;
    }
    if ((MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_RELEASE, 1U,
             &output) == 0U) ||
        (MotorPositionGuard_Update(
             &guard, 1, 1U, MOTOR_POSITION_DIRECTION_TAKE_UP, 1U,
             &output) != 0U)) {
        return 0;
    }
    return (output.fault == (uint8_t)MOTOR_POSITION_FAULT_INPUT) &&
           output_is_bridge_off(&output);
}

static int test_mutation_state_corruption_and_null_output(void)
{
    MotorPositionGuard guard;
    MotorPositionGuardConfig config = fixture_config();
    MotorPositionGuardOutput output;

    if (init_and_zero(&guard, &config, 0) == 0) {
        return 0;
    }
    guard.config.release_limit_counts = 101U;
    if ((MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_STOP, 0U,
             &output) != 0U) ||
        (output.fault != (uint8_t)MOTOR_POSITION_FAULT_CONFIG) ||
        (guard.initialized != 0U) ||
        (MotorPositionGuard_SetZero(&guard, 0, 1U, 1U) != 0U)) {
        return 0;
    }

    if (init_and_zero(&guard, &config, 0) == 0) {
        return 0;
    }
    guard.active_ticks = 1U;
    if ((MotorPositionGuard_Update(
             &guard, 0, 1U, MOTOR_POSITION_DIRECTION_STOP, 0U,
             &output) != 0U) ||
        (output.fault != (uint8_t)MOTOR_POSITION_FAULT_STATE)) {
        return 0;
    }

    if (MotorPositionGuard_SetZero(&guard, 0, 1U, 1U) == 0U) {
        return 0;
    }
    guard.fault_count = UINT32_MAX;
    if ((MotorPositionGuard_Update(
             &guard, 0, 0U, MOTOR_POSITION_DIRECTION_STOP, 0U,
             &output) != 0U) ||
        (output.fault_count != UINT32_MAX)) {
        return 0;
    }

    if (MotorPositionGuard_SetZero(&guard, 0, 1U, 1U) == 0U) {
        return 0;
    }
    if (MotorPositionGuard_Update(
            &guard, 0, 1U, MOTOR_POSITION_DIRECTION_STOP, 0U,
            NULL) != 0U) {
        return 0;
    }
    return (guard.fault_latched != 0U) &&
           (guard.fault == (uint8_t)MOTOR_POSITION_FAULT_INPUT) &&
           (guard.previous_bridge_enabled == 0U);
}

int main(void)
{
    int pass = 1;

    pass &= test_config_validation();
    pass &= test_explicit_zero_and_recovery();
    pass &= test_direction_and_motion();
    pass &= test_position_limits();
    pass &= test_encoder_faults_and_integer_extremes();
    pass &= test_no_motion_wrong_direction_and_stop_reset();
    pass &= test_active_timeout_and_unsafe_reversal();
    pass &= test_mutation_state_corruption_and_null_output();

    printf("motor relative-position fail-closed guard: %s\n",
           pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}
