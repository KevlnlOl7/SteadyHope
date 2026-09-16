#include "motor_position_guard.h"
#include "quadrature_encoder.h"
#include "tb6612_driver.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* All values in this file are host-test fixtures, not motor settings. */
static Tb6612DriverConfig driver_fixture(void)
{
    Tb6612DriverConfig config;

    config.pwm_full_scale_ccr = 1000U;
    config.max_duty_fraction = 0.25;
    config.reversal_dead_ticks = 2U;
    config.release_ain1_level = 1U;
    return config;
}

static MotorPositionGuardConfig position_fixture(void)
{
    MotorPositionGuardConfig config;

    config.release_limit_counts = 20U;
    config.takeup_limit_counts = 20U;
    config.max_encoder_step_counts = 5U;
    config.min_motion_counts_per_window = 2U;
    config.wrong_direction_tolerance_counts = 0U;
    config.motion_window_active_ticks = 2U;
    config.max_active_ticks = 20U;
    return config;
}

static uint8_t snapshot_is_valid(
    const QuadratureEncoderSnapshot *snapshot)
{
    return (uint8_t)((snapshot != NULL) &&
                     (snapshot->initialized == 1U) &&
                     (snapshot->invalid_transition_latched == 0U) &&
                     (snapshot->overflow_latched == 0U));
}

static int bridge_output_is_safe(const Tb6612Output *output)
{
    return (output->ccr == 0U) && (output->direction == 0) &&
           (output->ain1 == 0U) && (output->ain2 == 0U) &&
           (output->stby == 0U);
}

/*
 * This helper mirrors the required foreground ordering:
 *
 *   mapper request -> TB6612 candidate -> position veto -> HAL apply
 *
 * PositionGuard sees the driver's actual candidate.  Therefore a reversal
 * dead-time tick is STOP, not a false "active but not moving" interval.
 */
static Tb6612DriverResult guarded_step(
    Tb6612Driver *driver,
    MotorPositionGuard *position,
    int32_t encoder_count,
    uint8_t encoder_valid,
    int8_t requested_direction,
    double requested_duty,
    uint8_t permission,
    Tb6612Output *final_output,
    MotorPositionGuardOutput *position_output)
{
    Tb6612Output candidate;
    Tb6612DriverResult driver_result;
    uint8_t position_allowed;

    memset(final_output, 0, sizeof(*final_output));
    memset(position_output, 0, sizeof(*position_output));
    driver_result = TB6612Driver_Update(
        driver, requested_direction, requested_duty, permission,
        &candidate);
    if (driver_result == TB6612_DRIVER_ERROR) {
        *final_output = candidate;
        return TB6612_DRIVER_ERROR;
    }

    if (driver_result == TB6612_DRIVER_ACTIVE) {
        position_allowed = MotorPositionGuard_Update(
            position, encoder_count, encoder_valid,
            candidate.direction, 1U, position_output);
    } else {
        position_allowed = MotorPositionGuard_Update(
            position, encoder_count, encoder_valid,
            MOTOR_POSITION_DIRECTION_STOP, 0U, position_output);
    }

    if ((driver_result == TB6612_DRIVER_ACTIVE) &&
        (position_allowed == 1U)) {
        *final_output = candidate;
        return TB6612_DRIVER_ACTIVE;
    }

    if (position_output->fault_latched != 0U) {
        (void)TB6612Driver_Update(driver, 0, 0.0, 0U, final_output);
        return TB6612_DRIVER_ERROR;
    }

    *final_output = candidate;
    return TB6612_DRIVER_SAFE;
}

static int init_chain(Tb6612Driver *driver,
                      MotorPositionGuard *position,
                      int32_t zero_count)
{
    Tb6612DriverConfig driver_config = driver_fixture();
    MotorPositionGuardConfig position_config = position_fixture();
    Tb6612Output safe;

    return (TB6612Driver_Init(driver, &driver_config, &safe) ==
            TB6612_DRIVER_SAFE) && bridge_output_is_safe(&safe) &&
           (MotorPositionGuard_Init(position, &position_config) != 0U) &&
           (MotorPositionGuard_SetZero(
                position, zero_count, 1U, 1U) != 0U);
}

static int test_normal_motion_and_gate_stop(void)
{
    Tb6612Driver driver;
    MotorPositionGuard position;
    Tb6612Output bridge;
    MotorPositionGuardOutput position_output;

    if (!init_chain(&driver, &position, 0)) {
        return 0;
    }
    if ((guarded_step(&driver, &position, 0, 1U, 1, 0.10, 1U,
                      &bridge, &position_output) !=
         TB6612_DRIVER_ACTIVE) || (bridge.direction != 1) ||
        (bridge.ccr != 100U)) {
        return 0;
    }
    if ((guarded_step(&driver, &position, 1, 1U, 1, 0.10, 1U,
                      &bridge, &position_output) !=
         TB6612_DRIVER_ACTIVE) ||
        (guarded_step(&driver, &position, 2, 1U, 1, 0.10, 1U,
                      &bridge, &position_output) !=
         TB6612_DRIVER_ACTIVE)) {
        return 0;
    }
    return (guarded_step(&driver, &position, 3, 1U, 0, 0.0, 0U,
                         &bridge, &position_output) ==
            TB6612_DRIVER_SAFE) && bridge_output_is_safe(&bridge) &&
           (position_output.bridge_enable == 0U) &&
           (position_output.fault_latched == 0U);
}

static int test_reversal_dead_time_is_not_no_motion(void)
{
    Tb6612Driver driver;
    MotorPositionGuard position;
    Tb6612Output bridge;
    MotorPositionGuardOutput position_output;

    if (!init_chain(&driver, &position, 0) ||
        (guarded_step(&driver, &position, 0, 1U, 1, 0.10, 1U,
                      &bridge, &position_output) !=
         TB6612_DRIVER_ACTIVE) ||
        (guarded_step(&driver, &position, 1, 1U, 1, 0.10, 1U,
                      &bridge, &position_output) !=
         TB6612_DRIVER_ACTIVE)) {
        return 0;
    }

    /* Two actual SAFE ticks are generated before the opposite direction. */
    if ((guarded_step(&driver, &position, 2, 1U, -1, 0.10, 1U,
                      &bridge, &position_output) !=
         TB6612_DRIVER_SAFE) || !bridge_output_is_safe(&bridge) ||
        (position_output.motion_window_active_ticks != 0U) ||
        (guarded_step(&driver, &position, 2, 1U, -1, 0.10, 1U,
                      &bridge, &position_output) !=
         TB6612_DRIVER_SAFE) || !bridge_output_is_safe(&bridge) ||
        (position_output.fault_latched != 0U)) {
        return 0;
    }

    return (guarded_step(&driver, &position, 2, 1U, -1, 0.10, 1U,
                         &bridge, &position_output) ==
            TB6612_DRIVER_ACTIVE) && (bridge.direction == -1) &&
           (position_output.fault_latched == 0U);
}

static int test_position_veto_replaces_candidate_with_safe_output(void)
{
    Tb6612Driver driver;
    MotorPositionGuard position;
    Tb6612Output bridge;
    MotorPositionGuardOutput position_output;

    if (!init_chain(&driver, &position, 0)) {
        return 0;
    }
    if ((guarded_step(&driver, &position, 5, 1U, 0, 0.0, 0U,
                      &bridge, &position_output) !=
         TB6612_DRIVER_SAFE) ||
        (guarded_step(&driver, &position, 10, 1U, 0, 0.0, 0U,
                      &bridge, &position_output) !=
         TB6612_DRIVER_SAFE) ||
        (guarded_step(&driver, &position, 15, 1U, 0, 0.0, 0U,
                      &bridge, &position_output) !=
         TB6612_DRIVER_SAFE) ||
        (guarded_step(&driver, &position, 20, 1U, 0, 0.0, 0U,
                      &bridge, &position_output) !=
         TB6612_DRIVER_SAFE)) {
        return 0;
    }
    if (guarded_step(&driver, &position, 20, 1U, 1, 0.10, 1U,
                     &bridge, &position_output) !=
        TB6612_DRIVER_ERROR) {
        return 0;
    }
    return bridge_output_is_safe(&bridge) &&
           (position_output.fault_latched == 1U) &&
           (position_output.fault ==
            (uint8_t)MOTOR_POSITION_FAULT_RELEASE_LIMIT);
}

static int test_quadrature_fault_removes_position_validity(void)
{
    QuadratureEncoder encoder;
    QuadratureEncoderSnapshot snapshot;

    if ((QuadratureEncoder_Init(&encoder, 0U, 0U, 1) == 0U) ||
        (QuadratureEncoder_Snapshot(&encoder, &snapshot) == 0U) ||
        (snapshot_is_valid(&snapshot) == 0U)) {
        return 0;
    }

    /* 00 -> 11 is an illegal two-bit transition and must stay latched. */
    if ((QuadratureEncoder_OnEdge(&encoder, 1U, 1U) != 0) ||
        (QuadratureEncoder_Snapshot(&encoder, &snapshot) == 0U)) {
        return 0;
    }
    return snapshot.invalid_transition_latched == 1U &&
           snapshot_is_valid(&snapshot) == 0U;
}

int main(void)
{
    int pass = 1;

    pass &= test_normal_motion_and_gate_stop();
    pass &= test_reversal_dead_time_is_not_no_motion();
    pass &= test_position_veto_replaces_candidate_with_safe_output();
    pass &= test_quadrature_fault_removes_position_validity();

    printf("mapper-request -> driver -> position-veto chain: %s\n",
           pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}
