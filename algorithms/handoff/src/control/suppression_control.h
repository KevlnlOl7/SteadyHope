#ifndef SUPPRESSION_CONTROL_H
#define SUPPRESSION_CONTROL_H

#include "tremor_gate.h"

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SUPPRESSION_ESTIMATOR_BMFLC = 0,
    SUPPRESSION_ESTIMATOR_EHWFLC_KF = 1
} SuppressionEstimatorKind;

typedef enum {
    SUPPRESSION_CONTROL_FAULT_NONE = 0,
    SUPPRESSION_CONTROL_FAULT_NOT_INITIALIZED = 1,
    SUPPRESSION_CONTROL_FAULT_CONFIG = 2,
    SUPPRESSION_CONTROL_FAULT_SENSOR_INVALID = 3,
    SUPPRESSION_CONTROL_FAULT_SENSOR_STALE = 4,
    SUPPRESSION_CONTROL_FAULT_DRIVER = 5,
    SUPPRESSION_CONTROL_FAULT_INPUT = 6,
    SUPPRESSION_CONTROL_FAULT_ESTIMATOR_OUTPUT = 7,
    SUPPRESSION_CONTROL_FAULT_GATE = 8,
    SUPPRESSION_CONTROL_FAULT_LOCAL_INHIBIT = 9,
    SUPPRESSION_CONTROL_FAULT_OWNER = 10,
    SUPPRESSION_CONTROL_FAULT_IDENTITY = 11
} SuppressionControlFault;

typedef enum {
    SUPPRESSION_CONTROL_INHIBIT_USER_STOP = (1U << 0),
    SUPPRESSION_CONTROL_INHIBIT_WATCHDOG = (1U << 1),
    SUPPRESSION_CONTROL_INHIBIT_SCHEDULER_OVERRUN = (1U << 2),
    SUPPRESSION_CONTROL_INHIBIT_SYSTEM = (1U << 3)
} SuppressionControlInhibitFlag;

typedef struct {
    TremorGate gate;
    uint32_t fault_count;
    uint8_t estimator_kind;
    uint8_t initialized_estimator_kind;
    uint8_t initialized;
    uint8_t current_fault;
    uint8_t last_fault;
} SuppressionControl;

typedef struct {
    double tremor_estimate_dps;
    double diagnostic_frequency_hz;
    double compensation_request_dps;
    uint32_t fault_count;
    uint32_t active_inhibit_flags;
    uint8_t gate_enabled;
    uint8_t actuation_permitted;
    uint8_t current_fault;
    uint8_t last_fault;
} SuppressionControlOutput;

/*
 * One process/firmware image may use only one instance at a time because the
 * generated BMFLC and eHWFLC-KF implementations contain singleton state.
 */
uint8_t SuppressionControl_Init(SuppressionControl *control,
                                SuppressionEstimatorKind estimator_kind,
                                const TremorGateConfig *gate_config);

/* Releases the single generated-estimator owner.  A second instance cannot
 * initialize until the current owner explicitly calls this function. */
uint8_t SuppressionControl_Release(SuppressionControl *control);

/*
 * Returns one only when a finite compensation request may proceed to the
 * separately limited PWM/driver layer.  A one return is permission, not proof
 * of motor motion or suppression.
 */
uint8_t SuppressionControl_Update(SuppressionControl *control,
                                  double raw_gyro_dps,
                                  uint8_t sensor_valid,
                                  uint8_t sensor_stale,
                                  uint8_t driver_fault,
                                  uint32_t inhibit_flags,
                                  SuppressionControlOutput *output);

#ifdef __cplusplus
}
#endif

#endif
