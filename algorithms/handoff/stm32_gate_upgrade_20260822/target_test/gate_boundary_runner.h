#ifndef GATE_BOUNDARY_RUNNER_H
#define GATE_BOUNDARY_RUNNER_H

#include <stdint.h>

#include "gate_shadow_adapter.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char *test_case_id;
    uint32_t sample_index;
    uint32_t sample_tick_ms;
    int16_t gyro_x_raw_lsb;
    float tremor_envelope;
    float voluntary_envelope;
    float tremor_ratio;
    uint16_t on_count;
    uint16_t off_count;
    uint8_t gate_enabled;
    uint8_t gate_config_valid;
    uint8_t gate_last_fault;
    uint8_t actuation_authority;
} GateBoundaryRow;

typedef struct {
    GateShadowRuntime shadow;
    uint32_t vector_index;
    uint32_t sample_index;
    uint8_t complete;
    uint8_t error;
} GateBoundaryRunner;

void GateBoundaryRunner_Init(GateBoundaryRunner *runner);

/*
 * Call exactly once per 100 Hz tick.  Returns 1 when a row was produced.
 * The caller must buffer rows and transmit outside the timer ISR.
 */
uint8_t GateBoundaryRunner_Step(GateBoundaryRunner *runner,
                                GateBoundaryRow *row);

#ifdef __cplusplus
}
#endif

#endif
