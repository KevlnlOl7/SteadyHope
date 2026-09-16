#include "gate_shadow_adapter.h"

#include <stddef.h>
#include <string.h>

static void write_snapshot(const GateShadowRuntime *runtime,
                           GateShadowInhibitReason reason,
                           uint8_t allow_gate_output,
                           GateShadowOutput *output)
{
    uint8_t ready = 0U;

    memset(output, 0, sizeof(*output));
    output->inhibit_reason = (uint8_t)reason;
    output->actuation_authority = GATE_SHADOW_ACTUATION_AUTHORITY;

    if (runtime == NULL) {
        return;
    }

    ready = TremorGate_IsReady(&runtime->gate);
    output->tremor_envelope_dps = runtime->gate.tremor_envelope;
    output->voluntary_envelope_dps = runtime->gate.voluntary_envelope;
    output->tremor_ratio = runtime->gate.tremor_ratio;
    output->processed_samples = runtime->processed_samples;
    output->reset_count = runtime->reset_count;
    output->config_fingerprint = runtime->gate.config_fingerprint;
    output->on_count = runtime->gate.on_count;
    output->off_count = runtime->gate.off_count;
    output->gate_ready = ready;
    output->gate_last_fault = runtime->gate.last_fault;
    output->gate_enabled = (uint8_t)(
        (allow_gate_output == 1U) &&
        (ready == 1U) &&
        (runtime->gate.last_fault == (uint8_t)TREMOR_GATE_FAULT_NONE) &&
        (runtime->gate.enabled == 1U));
}

static void cold_inhibit(GateShadowRuntime *runtime,
                         GateShadowInhibitReason reason,
                         GateShadowOutput *output)
{
    TremorGate_Reset(&runtime->gate);
    runtime->reset_count++;
    if (TremorGate_IsReady(&runtime->gate) == 0U) {
        runtime->initialized = 0U;
    }
    write_snapshot(runtime, reason, 0U, output);
}

uint8_t GateShadow_Init(GateShadowRuntime *runtime)
{
    TremorGateConfig config;

    if (runtime == NULL) {
        return 0U;
    }

    memset(runtime, 0, sizeof(*runtime));
    config = TremorGate_DefaultConfig();
    TremorGate_Init(&runtime->gate, &config);
    runtime->initialized = (uint8_t)(
        (TremorGate_IsReady(&runtime->gate) == 1U) &&
        (runtime->gate.last_fault == (uint8_t)TREMOR_GATE_FAULT_NONE));
    return runtime->initialized;
}

void GateShadow_Reset(GateShadowRuntime *runtime)
{
    if ((runtime == NULL) || (runtime->initialized != 1U)) {
        return;
    }

    TremorGate_Reset(&runtime->gate);
    runtime->processed_samples = 0U;
    runtime->reset_count++;
    if (TremorGate_IsReady(&runtime->gate) == 0U) {
        runtime->initialized = 0U;
    }
}

void GateShadow_Update(GateShadowRuntime *runtime,
                       double gyro_x_dps,
                       uint8_t sensor_valid,
                       uint8_t sensor_stale,
                       uint8_t driver_fault,
                       uint8_t local_inhibit,
                       GateShadowOutput *output)
{
    uint8_t gate_enabled;

    if (output == NULL) {
        return;
    }
    if ((runtime == NULL) || (runtime->initialized != 1U)) {
        write_snapshot(runtime, GATE_SHADOW_INHIBIT_NOT_INITIALIZED,
                       0U, output);
        return;
    }
    if ((sensor_valid > 1U) || (sensor_stale > 1U) ||
        (driver_fault > 1U) || (local_inhibit > 1U)) {
        cold_inhibit(runtime, GATE_SHADOW_INHIBIT_INVALID_FLAGS, output);
        return;
    }
    if (sensor_valid == 0U) {
        cold_inhibit(runtime, GATE_SHADOW_INHIBIT_SENSOR_INVALID, output);
        return;
    }
    if (sensor_stale != 0U) {
        cold_inhibit(runtime, GATE_SHADOW_INHIBIT_SENSOR_STALE, output);
        return;
    }
    if (driver_fault != 0U) {
        cold_inhibit(runtime, GATE_SHADOW_INHIBIT_DRIVER_FAULT, output);
        return;
    }
    if (local_inhibit != 0U) {
        cold_inhibit(runtime, GATE_SHADOW_INHIBIT_LOCAL, output);
        return;
    }
    if (TremorGate_IsReady(&runtime->gate) == 0U) {
        cold_inhibit(runtime, GATE_SHADOW_INHIBIT_GATE_NOT_READY, output);
        return;
    }

    gate_enabled = TremorGate_Update(&runtime->gate, gyro_x_dps);
    runtime->processed_samples++;
    if ((TremorGate_IsReady(&runtime->gate) == 0U) ||
        (runtime->gate.last_fault != (uint8_t)TREMOR_GATE_FAULT_NONE)) {
        write_snapshot(runtime, GATE_SHADOW_INHIBIT_GATE_FAULT, 0U, output);
        return;
    }

    write_snapshot(runtime, GATE_SHADOW_INHIBIT_NONE,
                   gate_enabled, output);
}
