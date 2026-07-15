#include "tremor_gate.h"

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

int main(void)
{
    int pass = 1;

    pass &= test_voluntary_rejection();
    pass &= test_tremor_activation();
    pass &= test_release_and_invalid_input();
    printf("tremor_gate: %s\n", pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}
