#include "tremor_gate.h"
#include "gating_7hz_boundary_vectors.h"

#include <stdint.h>
#include <stdio.h>

int main(void)
{
    TremorGate gate;
    TremorGateConfig config = TremorGate_DefaultConfig();
    unsigned long samples = 0UL;
    unsigned long mismatches = 0UL;
    uint32_t vector_index;

    for (vector_index = 0U; vector_index < GATING_7HZ_VECTOR_COUNT;
         ++vector_index) {
        uint32_t sample_index;
        uint8_t did_enable = 0U;
        TremorGate_Init(&gate, &config);

        for (sample_index = 0U; sample_index < GATING_7HZ_SAMPLE_COUNT;
             ++sample_index) {
            const double gyro_x_dps =
                (double)GATING_7HZ_GYRO_X_RAW_LSB[vector_index][sample_index] /
                GATING_7HZ_RAW_LSB_PER_DPS;
            const uint8_t actual = TremorGate_Update(&gate, gyro_x_dps);
            const uint8_t expected =
                GATING_7HZ_EXPECTED_ENABLED[vector_index][sample_index];
            did_enable = (uint8_t)(did_enable || actual);
            ++samples;
            if (actual != expected) {
                if (mismatches < 10UL) {
                    fprintf(stderr,
                            "7Hz mismatch vector=%lu sample=%lu expected=%u actual=%u\n",
                            (unsigned long)vector_index,
                            (unsigned long)sample_index,
                            (unsigned)expected,
                            (unsigned)actual);
                }
                ++mismatches;
            }
        }

        if (did_enable != GATING_7HZ_REFERENCE_DID_ENABLE[vector_index]) {
            fprintf(stderr, "7Hz summary mismatch vector=%lu\n",
                    (unsigned long)vector_index);
            ++mismatches;
        }

        printf("7Hz %.0f deg/s: design=%u, current_reference=%u\n",
               (double)GATING_7HZ_AMPLITUDES_DPS[vector_index],
               (unsigned)GATING_7HZ_DESIGN_SHOULD_ENABLE[vector_index],
               (unsigned)did_enable);
    }

    printf("7Hz boundary C/reference: %lu samples, %lu mismatches\n",
           samples, mismatches);
    return mismatches == 0UL ? 0 : 1;
}
