#include "suppression_control.h"

#include "BMFLC_step.h"
#include "BMFLC_step_initialize.h"
#include "eHWFLC_KF_step.h"
#include "eHWFLC_KF_step_initialize.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

#define SUPPRESSION_CONTROL_MAX_DIAGNOSTIC_FREQUENCY_HZ 50.0

static SuppressionControl *active_owner = NULL;
static uint8_t active_estimator_kind = 0U;
static uint8_t active_estimator_kind_valid = 0U;

static uint8_t estimator_kind_is_valid(uint8_t estimator_kind)
{
    return (uint8_t)((estimator_kind == (uint8_t)SUPPRESSION_ESTIMATOR_BMFLC) ||
                     (estimator_kind ==
                      (uint8_t)SUPPRESSION_ESTIMATOR_EHWFLC_KF));
}

static void estimator_reset(uint8_t estimator_kind)
{
    if (estimator_kind == (uint8_t)SUPPRESSION_ESTIMATOR_BMFLC) {
        BMFLC_step_initialize();
    } else if (estimator_kind ==
               (uint8_t)SUPPRESSION_ESTIMATOR_EHWFLC_KF) {
        eHWFLC_KF_step_initialize();
    }
}

static void all_estimators_reset(void)
{
    BMFLC_step_initialize();
    eHWFLC_KF_step_initialize();
}

static void clear_output(SuppressionControlOutput *output)
{
    if (output != NULL) {
        memset(output, 0, sizeof(*output));
    }
}

static void copy_fault_status(const SuppressionControl *control,
                              SuppressionControlOutput *output)
{
    output->fault_count = control->fault_count;
    output->current_fault = control->current_fault;
    output->last_fault = control->last_fault;
}

static void record_fault(SuppressionControl *control,
                         SuppressionControlFault fault)
{
    uint8_t fault_value = (uint8_t)fault;

    if (control->current_fault != fault_value) {
        if (control->fault_count < UINT32_MAX) {
            control->fault_count++;
        }
        control->last_fault = fault_value;
    }
    control->current_fault = fault_value;
}

static uint8_t inhibit_and_reset(SuppressionControl *control,
                                 SuppressionControlOutput *output,
                                 SuppressionControlFault fault,
                                 uint8_t require_reinit)
{
    if ((fault == SUPPRESSION_CONTROL_FAULT_CONFIG) ||
        (fault == SUPPRESSION_CONTROL_FAULT_IDENTITY)) {
        all_estimators_reset();
    } else {
        estimator_reset(control->estimator_kind);
    }
    TremorGate_Reset(&control->gate);
    record_fault(control, fault);
    if (require_reinit != 0U) {
        control->initialized = 0U;
    }
    clear_output(output);
    copy_fault_status(control, output);
    return 0U;
}

uint8_t SuppressionControl_Init(SuppressionControl *control,
                                SuppressionEstimatorKind estimator_kind,
                                const TremorGateConfig *gate_config)
{
    if (control == NULL) {
        return 0U;
    }

    if ((active_owner != NULL) && (active_owner != control)) {
        memset(control, 0, sizeof(*control));
        control->estimator_kind = (uint8_t)estimator_kind;
        control->initialized_estimator_kind = (uint8_t)estimator_kind;
        record_fault(control, SUPPRESSION_CONTROL_FAULT_OWNER);
        return 0U;
    }

    memset(control, 0, sizeof(*control));
    control->estimator_kind = (uint8_t)estimator_kind;
    control->initialized_estimator_kind = (uint8_t)estimator_kind;
    if (estimator_kind_is_valid(control->estimator_kind) == 0U) {
        record_fault(control, SUPPRESSION_CONTROL_FAULT_CONFIG);
        return 0U;
    }

    TremorGate_Init(&control->gate, gate_config);
    if (TremorGate_IsReady(&control->gate) == 0U) {
        record_fault(control, SUPPRESSION_CONTROL_FAULT_CONFIG);
        return 0U;
    }

    estimator_reset(control->estimator_kind);
    control->initialized = 1U;
    active_owner = control;
    active_estimator_kind = control->estimator_kind;
    active_estimator_kind_valid = 1U;
    return 1U;
}

uint8_t SuppressionControl_Release(SuppressionControl *control)
{
    if ((control == NULL) || (active_owner != control)) {
        return 0U;
    }
    all_estimators_reset();
    memset(control, 0, sizeof(*control));
    active_owner = NULL;
    active_estimator_kind = 0U;
    active_estimator_kind_valid = 0U;
    return 1U;
}

uint8_t SuppressionControl_Update(SuppressionControl *control,
                                  double raw_gyro_dps,
                                  uint8_t sensor_valid,
                                  uint8_t sensor_stale,
                                  uint8_t driver_fault,
                                  uint32_t inhibit_flags,
                                  SuppressionControlOutput *output)
{
    double tremor_estimate;
    double diagnostic_frequency = 0.0;
    uint8_t gate_enabled;

    clear_output(output);
    if ((control == NULL) || (output == NULL)) {
        return 0U;
    }
    if (active_owner != control) {
        output->current_fault = (uint8_t)SUPPRESSION_CONTROL_FAULT_OWNER;
        output->last_fault = (uint8_t)SUPPRESSION_CONTROL_FAULT_OWNER;
        return 0U;
    }
    if ((control->initialized != 1U) ||
        (estimator_kind_is_valid(control->estimator_kind) == 0U)) {
        all_estimators_reset();
        TremorGate_Init(&control->gate, NULL);
        control->initialized = 0U;
        record_fault(control, SUPPRESSION_CONTROL_FAULT_NOT_INITIALIZED);
        copy_fault_status(control, output);
        return 0U;
    }
    if ((active_estimator_kind_valid != 1U) ||
        (control->estimator_kind != control->initialized_estimator_kind) ||
        (control->estimator_kind != active_estimator_kind)) {
        return inhibit_and_reset(control, output,
                                 SUPPRESSION_CONTROL_FAULT_IDENTITY, 1U);
    }
    if ((control->gate.config_valid != 1U) ||
        (TremorGate_ConfigIsValid(&control->gate.config) == 0U) ||
        (TremorGate_ConfigFingerprint(&control->gate.config) !=
         control->gate.config_fingerprint)) {
        return inhibit_and_reset(control, output,
                                 SUPPRESSION_CONTROL_FAULT_CONFIG, 1U);
    }
    if (TremorGate_IsReady(&control->gate) == 0U) {
        return inhibit_and_reset(control, output,
                                 SUPPRESSION_CONTROL_FAULT_GATE, 0U);
    }
    if (sensor_valid == 0U) {
        return inhibit_and_reset(control, output,
                                 SUPPRESSION_CONTROL_FAULT_SENSOR_INVALID, 0U);
    }
    if (sensor_stale != 0U) {
        return inhibit_and_reset(control, output,
                                 SUPPRESSION_CONTROL_FAULT_SENSOR_STALE, 0U);
    }
    if (driver_fault != 0U) {
        return inhibit_and_reset(control, output,
                                 SUPPRESSION_CONTROL_FAULT_DRIVER, 0U);
    }
    if (inhibit_flags != 0U) {
        (void)inhibit_and_reset(control, output,
                                SUPPRESSION_CONTROL_FAULT_LOCAL_INHIBIT, 0U);
        output->active_inhibit_flags = inhibit_flags;
        return 0U;
    }
    if (!isfinite(raw_gyro_dps) ||
        (fabs(raw_gyro_dps) > TREMOR_GATE_MAX_ABS_INPUT_DPS)) {
        return inhibit_and_reset(control, output,
                                 SUPPRESSION_CONTROL_FAULT_INPUT, 0U);
    }

    if (control->estimator_kind == (uint8_t)SUPPRESSION_ESTIMATOR_BMFLC) {
        tremor_estimate = BMFLC_step(raw_gyro_dps);
    } else {
        eHWFLC_KF_step(raw_gyro_dps, &tremor_estimate, &diagnostic_frequency);
    }
    if (!isfinite(tremor_estimate) ||
        (fabs(tremor_estimate) > TREMOR_GATE_MAX_ABS_INPUT_DPS) ||
        !isfinite(diagnostic_frequency) ||
        (diagnostic_frequency < 0.0) ||
        (diagnostic_frequency >
         SUPPRESSION_CONTROL_MAX_DIAGNOSTIC_FREQUENCY_HZ)) {
        return inhibit_and_reset(
            control, output, SUPPRESSION_CONTROL_FAULT_ESTIMATOR_OUTPUT, 0U);
    }

    gate_enabled = TremorGate_Update(&control->gate, raw_gyro_dps);
    if ((TremorGate_IsReady(&control->gate) == 0U) ||
        (control->gate.last_fault != (uint8_t)TREMOR_GATE_FAULT_NONE) ||
        ((gate_enabled != 0U) && (gate_enabled != 1U))) {
        return inhibit_and_reset(control, output,
                                 SUPPRESSION_CONTROL_FAULT_GATE, 0U);
    }

    control->current_fault = (uint8_t)SUPPRESSION_CONTROL_FAULT_NONE;
    output->tremor_estimate_dps = tremor_estimate;
    output->diagnostic_frequency_hz = diagnostic_frequency;
    output->gate_enabled = gate_enabled;
    copy_fault_status(control, output);
    if (gate_enabled != 1U) {
        return 0U;
    }

    output->compensation_request_dps = -tremor_estimate;
    if (!isfinite(output->compensation_request_dps)) {
        return inhibit_and_reset(
            control, output, SUPPRESSION_CONTROL_FAULT_ESTIMATOR_OUTPUT, 0U);
    }
    output->actuation_permitted = 1U;
    return 1U;
}
