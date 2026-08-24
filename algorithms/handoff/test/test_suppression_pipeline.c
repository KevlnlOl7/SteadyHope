#include "motor_command_mapper.h"
#include "suppression_control.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>

#define FS_HZ 100.0
#define PI 3.14159265358979323846
#define PIPELINE_SOAK_TICKS 250000U

/* Host-test fixture only.  These values have no firmware or motor authority. */
static MotorCommandMapperConfig fixture_mapper_config(void)
{
    MotorCommandMapperConfig config;

    config.deadband_dps = 0.0;
    config.gain_duty_fraction_per_dps = 0.02;
    config.max_duty_fraction = 0.20;
    config.max_duty_step_per_tick = 0.05;
    config.max_abs_request_dps = 100.0;
    config.reversal_dead_ticks = 2U;
    config.direction_polarity = 1;
    return config;
}

static double input_sample(uint32_t index)
{
    double t = (double)index / FS_HZ;
    return 15.0 * sin(2.0 * PI * 5.0 * t) +
           2.0 * sin(2.0 * PI * 2.0 * t);
}

static int motor_output_is_safe(const MotorCommandOutput *output)
{
    return isfinite(output->duty_fraction) &&
           (output->duty_fraction == 0.0) &&
           (output->direction == 0) &&
           (output->bridge_enable == 0U);
}

static int pipeline_invariant_holds(
    uint8_t motor_active, uint8_t sensor_valid, uint8_t sensor_stale,
    uint8_t driver_fault, uint32_t inhibit_flags,
    const SuppressionControlOutput *suppression,
    const MotorCommandOutput *motor,
    const MotorCommandMapperConfig *config)
{
    if (!isfinite(suppression->tremor_estimate_dps) ||
        !isfinite(suppression->diagnostic_frequency_hz) ||
        !isfinite(suppression->compensation_request_dps) ||
        !isfinite(motor->duty_fraction) ||
        (motor_active != motor->bridge_enable) ||
        (motor->duty_fraction < 0.0) ||
        (motor->duty_fraction > config->max_duty_fraction)) {
        return 0;
    }
    if (motor_active != 0U) {
        if ((sensor_valid != 1U) || (sensor_stale != 0U) ||
            (driver_fault != 0U) || (inhibit_flags != 0U) ||
            (suppression->gate_enabled != 1U) ||
            (suppression->actuation_permitted != 1U) ||
            (suppression->current_fault !=
             (uint8_t)SUPPRESSION_CONTROL_FAULT_NONE) ||
            (motor->current_fault !=
             (uint8_t)MOTOR_MAPPER_FAULT_NONE) ||
            ((motor->direction != -1) && (motor->direction != 1)) ||
            (motor->duty_fraction <= 0.0)) {
            return 0;
        }
    }
    if ((suppression->actuation_permitted == 0U) &&
        !motor_output_is_safe(motor)) {
        return 0;
    }
    return 1;
}

static int test_integrated_fault_soak(SuppressionEstimatorKind kind)
{
    static SuppressionControl control;
    SuppressionControlOutput suppression;
    MotorCommandMapper mapper;
    MotorCommandMapperConfig config = fixture_mapper_config();
    MotorCommandOutput motor;
    uint32_t i;
    uint32_t active_count = 0U;
    uint32_t fault_tick_count = 0U;

    if ((SuppressionControl_Init(&control, kind, NULL) == 0U) ||
        (MotorCommandMapper_Init(
             &mapper, &config, &config) == 0U)) {
        return 0;
    }

    for (i = 0U; i < PIPELINE_SOAK_TICKS; ++i) {
        double raw = input_sample(i);
        uint8_t sensor_valid = 1U;
        uint8_t sensor_stale = 0U;
        uint8_t driver_fault = 0U;
        uint32_t inhibit_flags = 0U;
        uint8_t fault_tick = 0U;
        uint8_t permitted;
        uint8_t motor_active;

        if ((i != 0U) && ((i % 40009U) == 0U)) {
            raw = NAN;
            fault_tick = 1U;
        } else if ((i != 0U) && ((i % 50021U) == 0U)) {
            sensor_valid = 0U;
            fault_tick = 1U;
        } else if ((i != 0U) && ((i % 60013U) == 0U)) {
            sensor_stale = 1U;
            fault_tick = 1U;
        } else if ((i != 0U) && ((i % 70001U) == 0U)) {
            driver_fault = 1U;
            fault_tick = 1U;
        } else if ((i != 0U) && ((i % 80021U) == 0U)) {
            inhibit_flags =
                (uint32_t)SUPPRESSION_CONTROL_INHIBIT_WATCHDOG;
            fault_tick = 1U;
        } else if ((i != 0U) && ((i % 90001U) == 0U)) {
            inhibit_flags =
                (uint32_t)SUPPRESSION_CONTROL_INHIBIT_SCHEDULER_OVERRUN;
            fault_tick = 1U;
        }

        permitted = SuppressionControl_Update(
            &control, raw, sensor_valid, sensor_stale, driver_fault,
            inhibit_flags, &suppression);
        motor_active = MotorCommandMapper_Update(
            &mapper, suppression.compensation_request_dps, permitted,
            driver_fault, inhibit_flags, &motor);

        if (!pipeline_invariant_holds(
                motor_active, sensor_valid, sensor_stale, driver_fault,
                inhibit_flags, &suppression, &motor, &config)) {
            return 0;
        }
        if (fault_tick != 0U) {
            if ((permitted != 0U) || (motor_active != 0U) ||
                !motor_output_is_safe(&motor) ||
                (suppression.current_fault ==
                 (uint8_t)SUPPRESSION_CONTROL_FAULT_NONE)) {
                return 0;
            }
            fault_tick_count++;
        }
        if (motor_active != 0U) {
            active_count++;
        }
    }

    /* Upstream faults clear permission before the mapper; therefore they do
     * not need to increment the mapper's own fault counter. */
    return (active_count > 0U) && (fault_tick_count >= 15U) &&
           (control.fault_count > 0U);
}

int main(void)
{
    int pass = 1;

    pass &= test_integrated_fault_soak(SUPPRESSION_ESTIMATOR_BMFLC);
    pass &= test_integrated_fault_soak(SUPPRESSION_ESTIMATOR_EHWFLC_KF);
    printf("suppression wrapper -> mapper integrated invariant: %s\n",
           pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}
