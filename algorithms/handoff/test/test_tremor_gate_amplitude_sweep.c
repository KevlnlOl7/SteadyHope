#include "tremor_gate.h"
#include "gating_amplitude_sweep_vectors.h"

#include <stdint.h>
#include <stdio.h>

int main(void)
{
    TremorGate gate;
    TremorGateConfig config = TremorGate_DefaultConfig();
    uint32_t samples = 0U;
    uint32_t mismatches = 0U;
    uint32_t vector_index;

    for (vector_index = 0U; vector_index < GATING_SWEEP_VECTOR_COUNT;
         ++vector_index) {
        uint32_t sample_index;
        uint32_t tone_enabled = 0U;

        TremorGate_Init(&gate, &config);
        for (sample_index = 0U; sample_index < GATING_SWEEP_SAMPLE_COUNT;
             ++sample_index) {
            const double gyro_x_dps =
                (double)GATING_SWEEP_GYRO_X_RAW_LSB[vector_index][sample_index] /
                GATING_SWEEP_RAW_LSB_PER_DPS;
            const uint8_t actual = TremorGate_Update(&gate, gyro_x_dps);
            const uint8_t expected =
                GATING_SWEEP_EXPECTED_ENABLED[vector_index][sample_index];

            if ((sample_index >= GATING_SWEEP_TONE_START_SAMPLE) &&
                (sample_index < GATING_SWEEP_TONE_END_SAMPLE) &&
                (actual != 0U)) {
                ++tone_enabled;
            }
            ++samples;
            if (actual != expected) {
                if (mismatches < 10U) {
                    fprintf(stderr,
                            "sweep mismatch vector=%lu sample=%lu expected=%u actual=%u\n",
                            (unsigned long)vector_index,
                            (unsigned long)sample_index,
                            (unsigned)expected,
                            (unsigned)actual);
                }
                ++mismatches;
            }
        }

        if ((uint8_t)(tone_enabled != 0U) !=
            GATING_SWEEP_REFERENCE_DID_ENABLE[vector_index]) {
            fprintf(stderr, "sweep summary mismatch vector=%lu\n",
                    (unsigned long)vector_index);
            ++mismatches;
        }

        if ((vector_index + 1U == GATING_SWEEP_VECTOR_COUNT) ||
            (GATING_SWEEP_FREQUENCY_HZ[vector_index] !=
             GATING_SWEEP_FREQUENCY_HZ[vector_index + 1U])) {
            const uint8_t frequency = GATING_SWEEP_FREQUENCY_HZ[vector_index];
            uint32_t start = vector_index + 1U - 7U;
            uint32_t first_enabled = GATING_SWEEP_VECTOR_COUNT;
            uint32_t scan;

            for (scan = start; scan <= vector_index; ++scan) {
                if (GATING_SWEEP_REFERENCE_DID_ENABLE[scan] != 0U) {
                    first_enabled = scan;
                    break;
                }
            }
            if (first_enabled == GATING_SWEEP_VECTOR_COUNT) {
                printf("%u Hz: first enabled amplitude = never\n",
                       (unsigned)frequency);
            } else {
                printf("%u Hz: first enabled amplitude = %u deg/s%s\n",
                       (unsigned)frequency,
                       (unsigned)GATING_SWEEP_AMPLITUDE_DPS[first_enabled],
                       (GATING_SWEEP_IN_TARGET_BAND[first_enabled] != 0U)
                           ? "" : " (out-of-band activation)");
            }
        }
    }

    printf("amplitude sweep C/reference: %lu samples, %lu mismatches\n",
           (unsigned long)samples, (unsigned long)mismatches);
    return mismatches == 0U ? 0 : 1;
}
