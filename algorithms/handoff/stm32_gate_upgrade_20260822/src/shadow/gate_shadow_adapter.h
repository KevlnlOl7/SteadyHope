#ifndef GATE_SHADOW_ADAPTER_H
#define GATE_SHADOW_ADAPTER_H

#include <stdint.h>

#include "tremor_gate.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * This adapter is intentionally observation-only.  It exposes the latest
 * gate decision for logging, but never grants actuator authority.
 */
#define GATE_SHADOW_ACTUATION_AUTHORITY 0U

typedef enum {
    GATE_SHADOW_INHIBIT_NONE = 0,
    GATE_SHADOW_INHIBIT_NOT_INITIALIZED = 1,
    GATE_SHADOW_INHIBIT_INVALID_FLAGS = 2,
    GATE_SHADOW_INHIBIT_SENSOR_INVALID = 3,
    GATE_SHADOW_INHIBIT_SENSOR_STALE = 4,
    GATE_SHADOW_INHIBIT_DRIVER_FAULT = 5,
    GATE_SHADOW_INHIBIT_LOCAL = 6,
    GATE_SHADOW_INHIBIT_GATE_NOT_READY = 7,
    GATE_SHADOW_INHIBIT_GATE_FAULT = 8
} GateShadowInhibitReason;

typedef struct {
    TremorGate gate;
    uint32_t processed_samples;
    uint32_t reset_count;
    uint8_t initialized;
} GateShadowRuntime;

typedef struct {
    float tremor_envelope_dps;
    float voluntary_envelope_dps;
    float tremor_ratio;
    uint32_t processed_samples;
    uint32_t reset_count;
    uint32_t config_fingerprint;
    uint16_t on_count;
    uint16_t off_count;
    uint8_t gate_enabled;
    uint8_t gate_ready;
    uint8_t gate_last_fault;
    uint8_t inhibit_reason;
    uint8_t actuation_authority;
} GateShadowOutput;

uint8_t GateShadow_Init(GateShadowRuntime *runtime);
void GateShadow_Reset(GateShadowRuntime *runtime);
void GateShadow_Update(GateShadowRuntime *runtime,
                       double gyro_x_dps,
                       uint8_t sensor_valid,
                       uint8_t sensor_stale,
                       uint8_t driver_fault,
                       uint8_t local_inhibit,
                       GateShadowOutput *output);

#ifdef __cplusplus
}
#endif

#endif
