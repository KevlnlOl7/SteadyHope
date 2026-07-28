#include "tremor_gate.h"
#include "../test_vectors/gating_frequency/gating_frequency_vectors.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>

#define FS_HZ 100.0
#define PI 3.14159265358979323846

static double sine_sample(double frequency_hz, double amplitude_dps, uint32_t index)
{
    return amplitude_dps * sin(2.0 * PI * frequency_hz * (double)index / FS_HZ);
}

static int test_voluntary_rejection(void)
{
    TremorGate gate;
    uint32_t enabled_count = 0U;
    uint32_t i;

    TremorGate_Init(&gate, NULL);
    for (i = 0U; i < 1000U; ++i) {
        enabled_count += TremorGate_Update(&gate, sine_sample(2.0, 15.0, i));
    }

    printf("2 Hz voluntary enabled: %lu / 1000 samples\n",
           (unsigned long)enabled_count);
    return enabled_count == 0U;
}

static int test_tremor_activation(void)
{
    TremorGate gate;
    uint32_t first_enabled = UINT32_MAX;
    uint32_t enabled_after_warmup = 0U;
    uint32_t i;

    TremorGate_Init(&gate, NULL);
    for (i = 0U; i < 1000U; ++i) {
        uint8_t enabled = TremorGate_Update(&gate, sine_sample(5.0, 12.0, i));
        if ((enabled != 0U) && (first_enabled == UINT32_MAX)) {
            first_enabled = i;
        }
        if ((i >= 200U) && (enabled != 0U)) {
            enabled_after_warmup++;
        }
    }

    printf("5 Hz tremor first enabled: %lu ms; post-warmup duty: %.2f%%\n",
           (unsigned long)(first_enabled * 10U),
           100.0 * (double)enabled_after_warmup / 800.0);
    return (first_enabled != UINT32_MAX) && (enabled_after_warmup >= 760U);
}

static int test_release_and_invalid_input(void)
{
    TremorGate gate;
    uint32_t i;

    TremorGate_Init(&gate, NULL);
    for (i = 0U; i < 300U; ++i) {
        (void)TremorGate_Update(&gate, sine_sample(5.0, 12.0, i));
    }
    if (gate.enabled == 0U) {
        return 0;
    }

    for (i = 0U; i < 300U; ++i) {
        (void)TremorGate_Update(&gate, 0.0);
    }
    if (gate.enabled != 0U) {
        return 0;
    }

    gate.enabled = 1U;
    return TremorGate_Update(&gate, NAN) == 0U;
}

static int test_frequency_vectors(void)
{
    uint32_t vector_index;
    int pass = 1;

    for (vector_index = 0U;
         vector_index < GATING_TEST_VECTOR_COUNT;
         ++vector_index) {
        TremorGate gate;
        uint32_t first_enabled = UINT32_MAX;
        uint32_t enabled_during_tone = 0U;
        uint32_t sample_index;

        TremorGate_Init(&gate, NULL);
        for (sample_index = 0U;
             sample_index < GATING_TEST_SAMPLE_COUNT;
             ++sample_index) {
            double gyro_dps =
                (double)GATING_TEST_GYRO_X_RAW_LSB[vector_index][sample_index] /
                GATING_TEST_RAW_LSB_PER_DPS;
            uint8_t enabled = TremorGate_Update(&gate, gyro_dps);

            if ((enabled != 0U) && (first_enabled == UINT32_MAX)) {
                first_enabled = sample_index;
            }
            if ((sample_index >= GATING_TEST_TONE_START_SAMPLE) &&
                (sample_index < GATING_TEST_TONE_END_SAMPLE) &&
                (enabled != 0U)) {
                enabled_during_tone++;
            }
        }

        printf("%u Hz vector: first enabled = ",
               (unsigned int)GATING_TEST_FREQUENCIES_HZ[vector_index]);
        if (first_enabled == UINT32_MAX) {
            printf("never");
        } else {
            printf("%lu ms",
                   (unsigned long)(first_enabled * 10U));
        }
        printf(", tone enabled = %lu / %u, final = %u\n",
               (unsigned long)enabled_during_tone,
               (unsigned int)(GATING_TEST_TONE_END_SAMPLE -
                              GATING_TEST_TONE_START_SAMPLE),
               (unsigned int)gate.enabled);

        if (GATING_TEST_EXPECTED_SHOULD_ENABLE[vector_index] != 0U) {
            if ((first_enabled == UINT32_MAX) ||
                (first_enabled < GATING_TEST_TONE_START_SAMPLE) ||
                (first_enabled >= GATING_TEST_TONE_END_SAMPLE) ||
                (enabled_during_tone == 0U)) {
                pass = 0;
            }
        } else if (first_enabled != UINT32_MAX) {
            pass = 0;
        }
        if (gate.enabled != 0U) {
            pass = 0;
        }
    }
    return pass;
}

int main(void)
{
    int pass = 1;

    pass &= test_voluntary_rejection();
    pass &= test_tremor_activation();
    pass &= test_release_and_invalid_input();
    pass &= test_frequency_vectors();
    printf("tremor_gate: %s\n", pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}
