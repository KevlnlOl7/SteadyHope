#include "suppression_control.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>

#define FS_HZ 100.0
#define PI 3.14159265358979323846

static double fake_tremor_dps = 8.0;
static double fake_frequency_hz = NAN;

double BMFLC_step(double input)
{
    (void)input;
    return fake_tremor_dps;
}

void BMFLC_step_initialize(void)
{
}

void eHWFLC_KF_step(double input, double *tremor,
                    double *diagnostic_frequency)
{
    (void)input;
    *tremor = fake_tremor_dps;
    *diagnostic_frequency = fake_frequency_hz;
}

void eHWFLC_KF_step_initialize(void)
{
}

static double sample_5_hz(uint32_t index)
{
    return 15.0 * sin(2.0 * PI * 5.0 * (double)index / FS_HZ);
}

static int frequency_does_not_inhibit(double frequency_hz)
{
    SuppressionControl control;
    SuppressionControlOutput output;
    uint32_t index;
    uint8_t saw_permission = 0U;

    fake_tremor_dps = 8.0;
    fake_frequency_hz = frequency_hz;
    if (SuppressionControl_Init(
            &control, SUPPRESSION_ESTIMATOR_EHWFLC_KF, NULL) == 0U) {
        return 0;
    }
    for (index = 0U; index < 600U; ++index) {
        uint8_t permitted = SuppressionControl_Update(
            &control, sample_5_hz(index), 1U, 0U, 0U, 0U, &output);
        if ((output.current_fault !=
             (uint8_t)SUPPRESSION_CONTROL_FAULT_NONE) ||
            !isfinite(output.diagnostic_frequency_hz)) {
            (void)SuppressionControl_Release(&control);
            return 0;
        }
        saw_permission |= permitted;
    }
    if ((frequency_hz >= 0.0) && (frequency_hz <= 50.0) &&
        isfinite(frequency_hz)) {
        if (output.diagnostic_frequency_hz != frequency_hz) {
            (void)SuppressionControl_Release(&control);
            return 0;
        }
    } else if (output.diagnostic_frequency_hz != 0.0) {
        (void)SuppressionControl_Release(&control);
        return 0;
    }
    return (SuppressionControl_Release(&control) != 0U) &&
           (saw_permission != 0U);
}

static int invalid_tremor_still_fails_safe(void)
{
    SuppressionControl control;
    SuppressionControlOutput output;

    fake_tremor_dps = NAN;
    fake_frequency_hz = 5.0;
    if (SuppressionControl_Init(
            &control, SUPPRESSION_ESTIMATOR_EHWFLC_KF, NULL) == 0U) {
        return 0;
    }
    if ((SuppressionControl_Update(
             &control, 0.0, 1U, 0U, 0U, 0U, &output) != 0U) ||
        (output.current_fault !=
         (uint8_t)SUPPRESSION_CONTROL_FAULT_ESTIMATOR_OUTPUT) ||
        (output.actuation_permitted != 0U) ||
        (output.compensation_request_dps != 0.0)) {
        (void)SuppressionControl_Release(&control);
        return 0;
    }
    return SuppressionControl_Release(&control) != 0U;
}

int main(void)
{
    int pass = 1;

    pass &= frequency_does_not_inhibit(NAN);
    pass &= frequency_does_not_inhibit(INFINITY);
    pass &= frequency_does_not_inhibit(-1.0);
    pass &= frequency_does_not_inhibit(51.0);
    pass &= frequency_does_not_inhibit(5.0);
    pass &= invalid_tremor_still_fails_safe();

    printf("diagnostic frequency isolation: %s\n", pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}
