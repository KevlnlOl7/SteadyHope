#include "gate_boundary_runner.h"

#include "gating_6to7_boundary_vectors.h"

#include <stddef.h>
#include <string.h>

void GateBoundaryRunner_Init(GateBoundaryRunner *runner)
{
    if (runner != NULL) {
        memset(runner, 0, sizeof(*runner));
    }
}

uint8_t GateBoundaryRunner_Step(GateBoundaryRunner *runner,
                                GateBoundaryRow *row)
{
    GateShadowOutput output;
    int16_t raw_lsb;

    if ((runner == NULL) || (row == NULL) ||
        (runner->complete != 0U) || (runner->error != 0U)) {
        return 0U;
    }
    if (runner->vector_index >= GATING_6TO7_VECTOR_COUNT) {
        runner->complete = 1U;
        return 0U;
    }
    if (runner->sample_index == 0U) {
        if (GateShadow_Init(&runner->shadow) == 0U) {
            runner->error = 1U;
            return 0U;
        }
    }

    raw_lsb = GATING_6TO7_GYRO_X_RAW_LSB
        [runner->vector_index][runner->sample_index];
    GateShadow_Update(
        &runner->shadow,
        (double)raw_lsb / GATING_6TO7_RAW_LSB_PER_DPS,
        1U, 0U, 0U, 0U, &output);
    if (output.inhibit_reason != (uint8_t)GATE_SHADOW_INHIBIT_NONE) {
        runner->error = 1U;
        return 0U;
    }

    memset(row, 0, sizeof(*row));
    row->test_case_id = GATING_6TO7_CASE_ID[runner->vector_index];
    row->sample_index = runner->sample_index;
    row->sample_tick_ms = runner->sample_index * 10U;
    row->gyro_x_raw_lsb = raw_lsb;
    row->tremor_envelope = output.tremor_envelope_dps;
    row->voluntary_envelope = output.voluntary_envelope_dps;
    row->tremor_ratio = output.tremor_ratio;
    row->on_count = output.on_count;
    row->off_count = output.off_count;
    row->gate_enabled = output.gate_enabled;
    row->gate_config_valid = runner->shadow.gate.config_valid;
    row->gate_last_fault = output.gate_last_fault;
    row->actuation_authority = output.actuation_authority;

    runner->sample_index++;
    if (runner->sample_index >= GATING_6TO7_SAMPLE_COUNT) {
        runner->sample_index = 0U;
        runner->vector_index++;
        if (runner->vector_index >= GATING_6TO7_VECTOR_COUNT) {
            runner->complete = 1U;
        }
    }
    return 1U;
}
