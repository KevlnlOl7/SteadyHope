#include "suppression_control.h"

#include "BMFLC_step.h"
#include "BMFLC_step_initialize.h"
#include "eHWFLC_KF_step.h"
#include "eHWFLC_KF_step_initialize.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>

#define FS_HZ 100.0
#define PI 3.14159265358979323846
#define SOAK_TICK_COUNT 1000000U

/* All tests intentionally reuse the same address because production permits
 * exactly one wrapper owner for the generated singleton estimators. */
static SuppressionControl control;

static double sine_sample(double frequency_hz, double amplitude_dps,
                          uint32_t index)
{
    return amplitude_dps * sin(2.0 * PI * frequency_hz * (double)index / FS_HZ);
}

static int output_is_safely_inhibited(const SuppressionControlOutput *output)
{
    return (output->gate_enabled == 0U) &&
           (output->actuation_permitted == 0U) &&
           (output->tremor_estimate_dps == 0.0) &&
           (output->diagnostic_frequency_hz == 0.0) &&
           (output->compensation_request_dps == 0.0);
}

static int test_valid_transparency(SuppressionEstimatorKind kind)
{
    SuppressionControlOutput output;
    double direct_tremor[300];
    double direct_frequency[300];
    uint32_t i;

    if (kind == SUPPRESSION_ESTIMATOR_BMFLC) {
        BMFLC_step_initialize();
        for (i = 0U; i < 300U; ++i) {
            direct_tremor[i] = BMFLC_step(sine_sample(5.0, 12.0, i));
            direct_frequency[i] = 0.0;
        }
    } else {
        eHWFLC_KF_step_initialize();
        for (i = 0U; i < 300U; ++i) {
            eHWFLC_KF_step(sine_sample(5.0, 12.0, i), &direct_tremor[i],
                           &direct_frequency[i]);
        }
    }

    if (SuppressionControl_Init(&control, kind, NULL) == 0U) {
        return 0;
    }
    for (i = 0U; i < 300U; ++i) {
        uint8_t permitted = SuppressionControl_Update(
            &control, sine_sample(5.0, 12.0, i), 1U, 0U, 0U, 0U, &output);
        if ((fabs(output.tremor_estimate_dps - direct_tremor[i]) > 1.0e-12) ||
            (fabs(output.diagnostic_frequency_hz - direct_frequency[i]) >
             1.0e-12) ||
            (output.current_fault !=
             (uint8_t)SUPPRESSION_CONTROL_FAULT_NONE) ||
            (permitted != output.actuation_permitted)) {
            return 0;
        }
    }
    return output.actuation_permitted != 0U;
}

static int test_invalid_input_and_reacquisition(SuppressionEstimatorKind kind)
{
    SuppressionControlOutput output;
    uint32_t i;

    if (SuppressionControl_Init(&control, kind, NULL) == 0U) {
        return 0;
    }
    for (i = 0U; i < 300U; ++i) {
        (void)SuppressionControl_Update(
            &control, sine_sample(5.0, 12.0, i), 1U, 0U, 0U, 0U, &output);
    }
    if (output.actuation_permitted == 0U) {
        return 0;
    }

    if ((SuppressionControl_Update(&control, NAN, 1U, 0U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safely_inhibited(&output) ||
        (output.current_fault != (uint8_t)SUPPRESSION_CONTROL_FAULT_INPUT)) {
        return 0;
    }
    if ((SuppressionControl_Update(&control, sine_sample(5.0, 12.0, 0U),
                                   1U, 0U, 0U, 0U, &output) != 0U) ||
        (output.gate_enabled != 0U) ||
        (output.current_fault != (uint8_t)SUPPRESSION_CONTROL_FAULT_NONE)) {
        return 0;
    }

    for (i = 1U; i < 300U; ++i) {
        (void)SuppressionControl_Update(
            &control, sine_sample(5.0, 12.0, i), 1U, 0U, 0U, 0U, &output);
    }
    return (output.actuation_permitted != 0U) &&
           (output.last_fault == (uint8_t)SUPPRESSION_CONTROL_FAULT_INPUT) &&
           (output.fault_count == 1U);
}

static int test_poisoned_estimator_output_is_caught(
    SuppressionEstimatorKind kind)
{
    SuppressionControlOutput output;
    double tremor;
    double frequency;

    if (SuppressionControl_Init(&control, kind, NULL) == 0U) {
        return 0;
    }
    if (kind == SUPPRESSION_ESTIMATOR_BMFLC) {
        (void)BMFLC_step(NAN);
    } else {
        eHWFLC_KF_step(NAN, &tremor, &frequency);
    }

    if ((SuppressionControl_Update(&control, 0.0, 1U, 0U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safely_inhibited(&output) ||
        (output.current_fault !=
         (uint8_t)SUPPRESSION_CONTROL_FAULT_ESTIMATOR_OUTPUT)) {
        return 0;
    }
    (void)SuppressionControl_Update(&control, 0.0, 1U, 0U, 0U, 0U,
                                    &output);
    return (output.current_fault == (uint8_t)SUPPRESSION_CONTROL_FAULT_NONE) &&
           isfinite(output.tremor_estimate_dps);
}

static int test_external_inhibits_and_config_corruption(void)
{
    SuppressionControlOutput output;

    if (SuppressionControl_Init(
            &control, SUPPRESSION_ESTIMATOR_EHWFLC_KF, NULL) == 0U) {
        return 0;
    }
    if ((SuppressionControl_Update(&control, 0.0, 0U, 0U, 0U, 0U,
                                   &output) != 0U) ||
        (output.current_fault !=
         (uint8_t)SUPPRESSION_CONTROL_FAULT_SENSOR_INVALID) ||
        !output_is_safely_inhibited(&output)) {
        return 0;
    }
    if ((SuppressionControl_Update(&control, 0.0, 1U, 1U, 0U, 0U,
                                   &output) != 0U) ||
        (output.current_fault !=
         (uint8_t)SUPPRESSION_CONTROL_FAULT_SENSOR_STALE) ||
        !output_is_safely_inhibited(&output)) {
        return 0;
    }
    if ((SuppressionControl_Update(&control, 0.0, 1U, 0U, 1U, 0U,
                                   &output) != 0U) ||
        (output.current_fault != (uint8_t)SUPPRESSION_CONTROL_FAULT_DRIVER) ||
        !output_is_safely_inhibited(&output)) {
        return 0;
    }

    if ((SuppressionControl_Update(
             &control, 0.0, 1U, 0U, 0U,
             (uint32_t)(SUPPRESSION_CONTROL_INHIBIT_USER_STOP |
                        SUPPRESSION_CONTROL_INHIBIT_WATCHDOG),
             &output) != 0U) ||
        (output.current_fault !=
         (uint8_t)SUPPRESSION_CONTROL_FAULT_LOCAL_INHIBIT) ||
        (output.active_inhibit_flags !=
         (uint32_t)(SUPPRESSION_CONTROL_INHIBIT_USER_STOP |
                    SUPPRESSION_CONTROL_INHIBIT_WATCHDOG)) ||
        !output_is_safely_inhibited(&output)) {
        return 0;
    }

    control.gate.config.samples_on = 0U;
    if ((SuppressionControl_Update(&control, 0.0, 1U, 0U, 0U, 0U,
                                   &output) != 0U) ||
        (control.initialized != 0U) ||
        (output.current_fault != (uint8_t)SUPPRESSION_CONTROL_FAULT_CONFIG) ||
        !output_is_safely_inhibited(&output)) {
        return 0;
    }
    return SuppressionControl_Update(
               &control, 0.0, 1U, 0U, 0U, 0U, &output) == 0U &&
           output.current_fault ==
               (uint8_t)SUPPRESSION_CONTROL_FAULT_NOT_INITIALIZED;
}

static int test_wrapper_rejects_corrupted_runtime_state(void)
{
    SuppressionControlOutput output;

    if (SuppressionControl_Init(
            &control, SUPPRESSION_ESTIMATOR_EHWFLC_KF, NULL) == 0U) {
        return 0;
    }
    control.gate.enabled = 2U;
    if ((SuppressionControl_Update(&control, 0.0, 1U, 0U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safely_inhibited(&output) ||
        (output.current_fault != (uint8_t)SUPPRESSION_CONTROL_FAULT_GATE)) {
        return 0;
    }

    if (SuppressionControl_Init(
            &control, SUPPRESSION_ESTIMATOR_EHWFLC_KF, NULL) == 0U) {
        return 0;
    }
    control.initialized = 2U;
    return (SuppressionControl_Update(&control, 0.0, 1U, 0U, 0U, 0U,
                                      &output) == 0U) &&
           !control.initialized && output_is_safely_inhibited(&output) &&
           (output.current_fault ==
            (uint8_t)SUPPRESSION_CONTROL_FAULT_NOT_INITIALIZED);
}

static int public_output_is_finite(const SuppressionControlOutput *output)
{
    return isfinite(output->tremor_estimate_dps) &&
           isfinite(output->diagnostic_frequency_hz) &&
           isfinite(output->compensation_request_dps);
}

static int test_single_owner_and_estimator_identity(void)
{
    SuppressionControl second;
    SuppressionControlOutput output;
    uint32_t i;

    if (SuppressionControl_Init(
            &control, SUPPRESSION_ESTIMATOR_BMFLC, NULL) == 0U) {
        return 0;
    }
    for (i = 0U; i < 600U; ++i) {
        (void)SuppressionControl_Update(
            &control, sine_sample(5.0, 12.0, i), 1U, 0U, 0U, 0U, &output);
    }
    if ((output.actuation_permitted == 0U) ||
        (SuppressionControl_Init(
             &second, SUPPRESSION_ESTIMATOR_EHWFLC_KF, NULL) != 0U) ||
        (second.current_fault !=
         (uint8_t)SUPPRESSION_CONTROL_FAULT_OWNER)) {
        return 0;
    }
    if ((SuppressionControl_Update(
             &control, sine_sample(5.0, 12.0, 600U),
             1U, 0U, 0U, 0U, &output) == 0U) ||
        (fabs(output.tremor_estimate_dps) < 0.05)) {
        return 0;
    }

    control.estimator_kind =
        (uint8_t)SUPPRESSION_ESTIMATOR_EHWFLC_KF;
    if ((SuppressionControl_Update(&control, 0.0, 1U, 0U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safely_inhibited(&output) ||
        (control.initialized != 0U) ||
        (output.current_fault !=
         (uint8_t)SUPPRESSION_CONTROL_FAULT_IDENTITY)) {
        return 0;
    }

    if (SuppressionControl_Init(
            &control, SUPPRESSION_ESTIMATOR_BMFLC, NULL) == 0U) {
        return 0;
    }
    for (i = 0U; i < 600U; ++i) {
        (void)SuppressionControl_Update(
            &control, sine_sample(5.0, 12.0, i), 1U, 0U, 0U, 0U, &output);
    }
    if (output.actuation_permitted == 0U) {
        return 0;
    }
    control.estimator_kind =
        (uint8_t)SUPPRESSION_ESTIMATOR_EHWFLC_KF;
    control.initialized_estimator_kind =
        (uint8_t)SUPPRESSION_ESTIMATOR_EHWFLC_KF;
    if ((SuppressionControl_Update(&control, 0.0, 1U, 0U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safely_inhibited(&output) ||
        (control.initialized != 0U) ||
        (output.current_fault !=
         (uint8_t)SUPPRESSION_CONTROL_FAULT_IDENTITY)) {
        return 0;
    }
    if ((SuppressionControl_Release(&second) != 0U) ||
        (SuppressionControl_Release(&control) == 0U) ||
        (SuppressionControl_Init(
             &second, SUPPRESSION_ESTIMATOR_EHWFLC_KF, NULL) == 0U) ||
        (SuppressionControl_Release(&second) == 0U)) {
        return 0;
    }
    return 1;
}

static int test_fault_injection_soak(SuppressionEstimatorKind kind)
{
    SuppressionControlOutput output;
    uint32_t i;
    uint32_t permitted_count = 0U;
    uint32_t injected_fault_count = 0U;

    if (SuppressionControl_Init(&control, kind, NULL) == 0U) {
        return 0;
    }

    for (i = 0U; i < SOAK_TICK_COUNT; ++i) {
        double raw = sine_sample(5.0, 15.0, i) +
                     sine_sample(2.0, 3.0, i);
        uint8_t sensor_valid = 1U;
        uint8_t sensor_stale = 0U;
        uint8_t driver_fault = 0U;
        uint32_t inhibit_flags = 0U;
        uint8_t expected_fault_tick = 0U;
        uint8_t permitted;

        if ((i != 0U) && ((i % 100003U) == 0U)) {
            raw = NAN;
            expected_fault_tick = 1U;
        } else if ((i != 0U) && ((i % 130003U) == 0U)) {
            raw = INFINITY;
            expected_fault_tick = 1U;
        } else if ((i != 0U) && ((i % 170003U) == 0U)) {
            raw = -INFINITY;
            expected_fault_tick = 1U;
        } else if ((i != 0U) && ((i % 190001U) == 0U)) {
            raw = TREMOR_GATE_MAX_ABS_INPUT_DPS + 0.0625;
            expected_fault_tick = 1U;
        } else if ((i != 0U) && ((i % 210011U) == 0U)) {
            sensor_valid = 0U;
            expected_fault_tick = 1U;
        } else if ((i != 0U) && ((i % 230003U) == 0U)) {
            sensor_stale = 1U;
            expected_fault_tick = 1U;
        } else if ((i != 0U) && ((i % 270001U) == 0U)) {
            driver_fault = 1U;
            expected_fault_tick = 1U;
        } else if ((i != 0U) && ((i % 310019U) == 0U)) {
            inhibit_flags =
                (uint32_t)SUPPRESSION_CONTROL_INHIBIT_WATCHDOG;
            expected_fault_tick = 1U;
        } else if ((i != 0U) && ((i % 370003U) == 0U)) {
            inhibit_flags =
                (uint32_t)SUPPRESSION_CONTROL_INHIBIT_SCHEDULER_OVERRUN;
            expected_fault_tick = 1U;
        }

        if (i == (SOAK_TICK_COUNT / 2U)) {
            double poisoned_tremor;
            double poisoned_frequency;

            if (kind == SUPPRESSION_ESTIMATOR_BMFLC) {
                (void)BMFLC_step(NAN);
            } else {
                eHWFLC_KF_step(NAN, &poisoned_tremor,
                               &poisoned_frequency);
            }
            expected_fault_tick = 1U;
        }

        permitted = SuppressionControl_Update(
            &control, raw, sensor_valid, sensor_stale, driver_fault,
            inhibit_flags, &output);

        if (!public_output_is_finite(&output) ||
            (permitted != output.actuation_permitted)) {
            return 0;
        }
        if (permitted != 0U) {
            if ((sensor_valid == 0U) || (sensor_stale != 0U) ||
                (driver_fault != 0U) || (inhibit_flags != 0U) ||
                (output.gate_enabled == 0U) ||
                (output.current_fault !=
                 (uint8_t)SUPPRESSION_CONTROL_FAULT_NONE)) {
                return 0;
            }
            permitted_count++;
        }
        if (expected_fault_tick != 0U) {
            if ((permitted != 0U) || !output_is_safely_inhibited(&output) ||
                (output.current_fault ==
                 (uint8_t)SUPPRESSION_CONTROL_FAULT_NONE)) {
                return 0;
            }
            injected_fault_count++;
        }
    }

    return (permitted_count > 0U) && (injected_fault_count >= 20U) &&
           (control.fault_count > 0U);
}

int main(void)
{
    int pass = 1;

    pass &= test_valid_transparency(SUPPRESSION_ESTIMATOR_BMFLC);
    pass &= test_valid_transparency(SUPPRESSION_ESTIMATOR_EHWFLC_KF);
    pass &= test_invalid_input_and_reacquisition(SUPPRESSION_ESTIMATOR_BMFLC);
    pass &= test_invalid_input_and_reacquisition(
        SUPPRESSION_ESTIMATOR_EHWFLC_KF);
    pass &= test_poisoned_estimator_output_is_caught(
        SUPPRESSION_ESTIMATOR_BMFLC);
    pass &= test_poisoned_estimator_output_is_caught(
        SUPPRESSION_ESTIMATOR_EHWFLC_KF);
    pass &= test_external_inhibits_and_config_corruption();
    pass &= test_wrapper_rejects_corrupted_runtime_state();
    pass &= test_single_owner_and_estimator_identity();
    pass &= test_fault_injection_soak(SUPPRESSION_ESTIMATOR_BMFLC);
    pass &= test_fault_injection_soak(SUPPRESSION_ESTIMATOR_EHWFLC_KF);

    pass &= SuppressionControl_Release(&control) != 0U;

    printf("suppression_control fail-closed wrapper: %s\n",
           pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}
