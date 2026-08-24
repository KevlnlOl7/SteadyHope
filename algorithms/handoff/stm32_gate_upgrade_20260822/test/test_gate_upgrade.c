#include "gate_boundary_runner.h"
#include "gating_6to7_boundary_vectors.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>

static uint32_t run_boundary_vectors(FILE *trace)
{
    GateBoundaryRunner runner;
    GateBoundaryRow row;
    uint32_t rows = 0U;
    uint32_t mismatches = 0U;

    GateBoundaryRunner_Init(&runner);
    while (GateBoundaryRunner_Step(&runner, &row) != 0U) {
        uint32_t vector_index = rows / GATING_6TO7_SAMPLE_COUNT;
        uint32_t sample_index = rows % GATING_6TO7_SAMPLE_COUNT;
        uint8_t expected =
            GATING_6TO7_EXPECTED_ENABLED[vector_index][sample_index];

        if ((row.gate_enabled != expected) ||
            (row.gate_config_valid != 1U) ||
            (row.gate_last_fault != (uint8_t)TREMOR_GATE_FAULT_NONE) ||
            (row.actuation_authority != 0U)) {
            if (mismatches < 10U) {
                fprintf(stderr,
                        "mismatch case=%s sample=%lu expected=%u actual=%u "
                        "valid=%u fault=%u authority=%u\n",
                        row.test_case_id,
                        (unsigned long)row.sample_index,
                        (unsigned)expected,
                        (unsigned)row.gate_enabled,
                        (unsigned)row.gate_config_valid,
                        (unsigned)row.gate_last_fault,
                        (unsigned)row.actuation_authority);
            }
            mismatches++;
        }

        if (trace != NULL) {
            fprintf(trace,
                    "%s,%lu,%lu,%d,%.9g,%.9g,%.9g,%u,%u,%u,%u,%u,%u\n",
                    row.test_case_id,
                    (unsigned long)row.sample_index,
                    (unsigned long)row.sample_tick_ms,
                    (int)row.gyro_x_raw_lsb,
                    (double)row.tremor_envelope,
                    (double)row.voluntary_envelope,
                    (double)row.tremor_ratio,
                    (unsigned)row.on_count,
                    (unsigned)row.off_count,
                    (unsigned)row.gate_enabled,
                    (unsigned)row.gate_config_valid,
                    (unsigned)row.gate_last_fault,
                    (unsigned)row.actuation_authority);
        }
        rows++;
    }

    if ((runner.error != 0U) ||
        (runner.complete != 1U) ||
        (rows != GATING_6TO7_VECTOR_COUNT * GATING_6TO7_SAMPLE_COUNT)) {
        fprintf(stderr,
                "runner incomplete rows=%lu complete=%u error=%u\n",
                (unsigned long)rows,
                (unsigned)runner.complete,
                (unsigned)runner.error);
        mismatches++;
    }
    return mismatches;
}

static uint32_t run_fail_closed_smoke(void)
{
    GateShadowRuntime runtime;
    GateShadowOutput output;
    uint32_t sample_index;
    uint32_t failures = 0U;

    if (GateShadow_Init(&runtime) != 1U) {
        return 1U;
    }
    for (sample_index = 0U; sample_index < GATING_6TO7_SAMPLE_COUNT;
         ++sample_index) {
        double gyro_dps =
            (double)GATING_6TO7_GYRO_X_RAW_LSB[0][sample_index] /
            GATING_6TO7_RAW_LSB_PER_DPS;
        GateShadow_Update(&runtime, gyro_dps, 1U, 0U, 0U, 0U, &output);
    }
    if (output.gate_enabled != 0U) {
        /* The vector has returned to rest by its final sample. */
        failures++;
    }

    GateShadow_Update(&runtime, 0.0, 0U, 0U, 0U, 0U, &output);
    if ((output.gate_enabled != 0U) ||
        (output.actuation_authority != 0U) ||
        (output.inhibit_reason !=
         (uint8_t)GATE_SHADOW_INHIBIT_SENSOR_INVALID) ||
        (output.on_count != 0U) || (output.off_count != 0U)) {
        failures++;
    }

    GateShadow_Update(&runtime, NAN, 1U, 0U, 0U, 0U, &output);
    if ((output.gate_enabled != 0U) ||
        (output.actuation_authority != 0U) ||
        (output.inhibit_reason !=
         (uint8_t)GATE_SHADOW_INHIBIT_GATE_FAULT) ||
        (output.gate_last_fault != (uint8_t)TREMOR_GATE_FAULT_INPUT)) {
        failures++;
    }

    GateShadow_Update(&runtime, 0.0, 2U, 0U, 0U, 0U, &output);
    if ((output.gate_enabled != 0U) ||
        (output.actuation_authority != 0U) ||
        (output.inhibit_reason !=
         (uint8_t)GATE_SHADOW_INHIBIT_INVALID_FLAGS)) {
        failures++;
    }
    return failures;
}

int main(int argc, char **argv)
{
    FILE *trace = NULL;
    uint32_t failures;

    if (argc > 2) {
        fprintf(stderr, "usage: %s [actual_trace.csv]\n", argv[0]);
        return 2;
    }
    if (argc == 2) {
        trace = fopen(argv[1], "w");
        if (trace == NULL) {
            perror(argv[1]);
            return 2;
        }
        fprintf(trace,
                "test_case_id,sample_index,sample_tick_ms,gyro_x_raw_lsb,"
                "tremor_envelope,voluntary_envelope,tremor_ratio,on_count,"
                "off_count,gate_enabled,gate_config_valid,gate_last_fault,"
                "actuation_authority\n");
    }

    failures = run_boundary_vectors(trace);
    failures += run_fail_closed_smoke();
    if (trace != NULL) {
        fclose(trace);
    }

    printf("gate upgrade host test: %s (%lu failures)\n",
           failures == 0U ? "PASS" : "FAIL",
           (unsigned long)failures);
    return failures == 0U ? 0 : 1;
}
