#include "tremor_gate.h"
#include "gating_mixed_boundary_vectors.h"

#include <stdint.h>
#include <stdio.h>

int main(void)
{
    TremorGate gate;
    TremorGateConfig config = TremorGate_DefaultConfig();
    unsigned long samples = 0UL;
    unsigned long mismatches = 0UL;
    uint32_t vector_index;

    for (vector_index = 0U; vector_index < GATING_MIXED_VECTOR_COUNT;
         ++vector_index) {
        uint32_t sample_index;
        uint8_t did_enable = 0U;
        TremorGate_Init(&gate, &config);
        for (sample_index = 0U; sample_index < GATING_MIXED_SAMPLE_COUNT;
             ++sample_index) {
            const double gyro_x_dps =
                (double)GATING_MIXED_GYRO_X_RAW_LSB[vector_index][sample_index] /
                GATING_MIXED_RAW_LSB_PER_DPS;
            const uint8_t actual = TremorGate_Update(&gate, gyro_x_dps);
            const uint8_t expected =
                GATING_MIXED_EXPECTED_ENABLED[vector_index][sample_index];
            did_enable = (uint8_t)(did_enable || actual);
            ++samples;
            if (actual != expected) {
                if (mismatches < 10UL) {
                    fprintf(stderr,
                            "mixed mismatch vector=%lu sample=%lu expected=%u actual=%u\n",
                            (unsigned long)vector_index,
                            (unsigned long)sample_index,
                            (unsigned)expected,
                            (unsigned)actual);
                }
                ++mismatches;
            }
        }
        if (did_enable != GATING_MIXED_REFERENCE_DID_ENABLE[vector_index]) {
            fprintf(stderr, "mixed summary mismatch vector=%lu\n",
                    (unsigned long)vector_index);
            ++mismatches;
        }
        printf("%s: current_reference=%u\n",
               GATING_MIXED_CASE_IDS[vector_index], (unsigned)did_enable);
    }

    printf("mixed boundary C/reference: %lu samples, %lu mismatches\n",
           samples, mismatches);
    return mismatches == 0UL ? 0 : 1;
}
