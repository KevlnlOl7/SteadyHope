#include "quadrature_encoder.h"

#include <limits.h>
#include <stdint.h>
#include <stdio.h>

static int snapshot_matches(const QuadratureEncoder *encoder,
                            int32_t expected_count,
                            uint8_t expected_a,
                            uint8_t expected_b)
{
    QuadratureEncoderSnapshot snapshot;

    return (QuadratureEncoder_Snapshot(encoder, &snapshot) != 0U) &&
           (snapshot.count == expected_count) &&
           (snapshot.level_a == expected_a) &&
           (snapshot.level_b == expected_b);
}

static int test_init_validation_and_explicit_state(void)
{
    QuadratureEncoder encoder;
    QuadratureEncoderSnapshot snapshot;

    if ((QuadratureEncoder_Init(NULL, 0U, 0U, 1) != 0U) ||
        (QuadratureEncoder_Init(&encoder, 2U, 0U, 1) != 0U) ||
        (QuadratureEncoder_Snapshot(&encoder, &snapshot) != 0U) ||
        (QuadratureEncoder_Init(&encoder, 0U, 2U, 1) != 0U) ||
        (QuadratureEncoder_Init(&encoder, 0U, 0U, 0) != 0U) ||
        (QuadratureEncoder_Init(&encoder, 0U, 0U, 2) != 0U) ||
        (QuadratureEncoder_Snapshot(NULL, &snapshot) != 0U) ||
        (QuadratureEncoder_Snapshot(&encoder, NULL) != 0U)) {
        return 0;
    }

    if ((QuadratureEncoder_Init(&encoder, 1U, 1U, -1) == 0U) ||
        (QuadratureEncoder_Snapshot(&encoder, &snapshot) == 0U)) {
        return 0;
    }
    return (snapshot.count == 0) && (snapshot.level_a == 1U) &&
           (snapshot.level_b == 1U) &&
           (snapshot.count_polarity == -1) &&
           (snapshot.valid_transition_count == 0U) &&
           (snapshot.invalid_transition_count == 0U) &&
           (snapshot.invalid_transition_latched == 0U) &&
           (snapshot.overflow_latched == 0U);
}

static int test_forward_reverse_and_duplicate_samples(void)
{
    static const uint8_t forward[4][2] = {
        {0U, 1U}, {1U, 1U}, {1U, 0U}, {0U, 0U}
    };
    static const uint8_t reverse[4][2] = {
        {1U, 0U}, {1U, 1U}, {0U, 1U}, {0U, 0U}
    };
    QuadratureEncoder encoder;
    QuadratureEncoderSnapshot snapshot;
    uint32_t i;

    if (QuadratureEncoder_Init(&encoder, 0U, 0U, 1) == 0U) {
        return 0;
    }
    for (i = 0U; i < 4U; ++i) {
        if (QuadratureEncoder_OnEdge(
                &encoder, forward[i][0], forward[i][1]) != 1) {
            return 0;
        }
    }
    if (!snapshot_matches(&encoder, 4, 0U, 0U)) {
        return 0;
    }

    if (QuadratureEncoder_OnEdge(&encoder, 0U, 0U) != 0) {
        return 0;
    }
    for (i = 0U; i < 4U; ++i) {
        if (QuadratureEncoder_OnEdge(
                &encoder, reverse[i][0], reverse[i][1]) != -1) {
            return 0;
        }
    }
    if ((QuadratureEncoder_Snapshot(&encoder, &snapshot) == 0U) ||
        (snapshot.count != 0) ||
        (snapshot.valid_transition_count != 8U) ||
        (snapshot.invalid_transition_count != 0U) ||
        (snapshot.invalid_transition_latched != 0U)) {
        return 0;
    }
    return 1;
}

static int test_negative_polarity(void)
{
    QuadratureEncoder encoder;

    if (QuadratureEncoder_Init(&encoder, 0U, 0U, -1) == 0U) {
        return 0;
    }
    return (QuadratureEncoder_OnEdge(&encoder, 0U, 1U) == -1) &&
           (QuadratureEncoder_OnEdge(&encoder, 1U, 1U) == -1) &&
           (QuadratureEncoder_OnEdge(&encoder, 1U, 0U) == -1) &&
           (QuadratureEncoder_OnEdge(&encoder, 0U, 0U) == -1) &&
           snapshot_matches(&encoder, -4, 0U, 0U);
}

static int test_invalid_transition_latch_and_resynchronization(void)
{
    QuadratureEncoder encoder;
    QuadratureEncoderSnapshot snapshot;

    if (QuadratureEncoder_Init(&encoder, 0U, 0U, 1) == 0U) {
        return 0;
    }

    /* 00 -> 11 changes both bits, contributes no count, and resynchronizes
     * at 11.  The following 11 -> 10 transition is then valid. */
    if ((QuadratureEncoder_OnEdge(&encoder, 1U, 1U) != 0) ||
        (QuadratureEncoder_OnEdge(&encoder, 1U, 0U) != 1) ||
        (QuadratureEncoder_OnEdge(&encoder, 2U, 0U) != 0) ||
        (QuadratureEncoder_OnEdge(&encoder, 1U, 0U) != 0) ||
        (QuadratureEncoder_Snapshot(&encoder, &snapshot) == 0U)) {
        return 0;
    }
    return (snapshot.count == 1) &&
           (snapshot.valid_transition_count == 1U) &&
           (snapshot.invalid_transition_count == 2U) &&
           (snapshot.invalid_transition_latched == 1U) &&
           (snapshot.level_a == 1U) && (snapshot.level_b == 0U);
}

static int test_overflow_latches_and_freezes_position(void)
{
    QuadratureEncoder encoder;
    QuadratureEncoderSnapshot snapshot;

    if (QuadratureEncoder_Init(&encoder, 0U, 0U, 1) == 0U) {
        return 0;
    }
    encoder.count = INT32_MAX;
    if ((QuadratureEncoder_OnEdge(&encoder, 0U, 1U) != 0) ||
        (QuadratureEncoder_OnEdge(&encoder, 0U, 0U) != 0) ||
        (QuadratureEncoder_Snapshot(&encoder, &snapshot) == 0U) ||
        (snapshot.count != INT32_MAX) ||
        (snapshot.overflow_latched != 1U) ||
        (snapshot.valid_transition_count != 2U)) {
        return 0;
    }

    if (QuadratureEncoder_Init(&encoder, 0U, 0U, 1) == 0U) {
        return 0;
    }
    encoder.count = INT32_MIN;
    if ((QuadratureEncoder_OnEdge(&encoder, 1U, 0U) != 0) ||
        (QuadratureEncoder_OnEdge(&encoder, 0U, 0U) != 0) ||
        (QuadratureEncoder_Snapshot(&encoder, &snapshot) == 0U)) {
        return 0;
    }
    return (snapshot.count == INT32_MIN) &&
           (snapshot.overflow_latched == 1U) &&
           (snapshot.invalid_transition_latched == 0U) &&
           (snapshot.valid_transition_count == 2U);
}

static int test_latches_clear_only_on_reinitialization(void)
{
    QuadratureEncoder encoder;
    QuadratureEncoderSnapshot snapshot;

    if ((QuadratureEncoder_Init(&encoder, 0U, 0U, 1) == 0U) ||
        (QuadratureEncoder_OnEdge(&encoder, 1U, 1U) != 0) ||
        (QuadratureEncoder_OnEdge(&encoder, 1U, 0U) != 1) ||
        (QuadratureEncoder_Snapshot(&encoder, &snapshot) == 0U) ||
        (snapshot.invalid_transition_latched != 1U)) {
        return 0;
    }
    if ((QuadratureEncoder_Init(&encoder, 1U, 0U, 1) == 0U) ||
        (QuadratureEncoder_Snapshot(&encoder, &snapshot) == 0U)) {
        return 0;
    }
    return (snapshot.count == 0) &&
           (snapshot.valid_transition_count == 0U) &&
           (snapshot.invalid_transition_count == 0U) &&
           (snapshot.invalid_transition_latched == 0U) &&
           (snapshot.overflow_latched == 0U) &&
           (snapshot.level_a == 1U) && (snapshot.level_b == 0U);
}

static int test_long_deterministic_rotation(void)
{
    static const uint8_t forward[4][2] = {
        {0U, 1U}, {1U, 1U}, {1U, 0U}, {0U, 0U}
    };
    QuadratureEncoder encoder;
    QuadratureEncoderSnapshot snapshot;
    uint32_t cycle;
    uint32_t phase;

    if (QuadratureEncoder_Init(&encoder, 0U, 0U, 1) == 0U) {
        return 0;
    }
    for (cycle = 0U; cycle < 250000U; ++cycle) {
        for (phase = 0U; phase < 4U; ++phase) {
            if (QuadratureEncoder_OnEdge(
                    &encoder, forward[phase][0], forward[phase][1]) != 1) {
                return 0;
            }
        }
    }
    if (QuadratureEncoder_Snapshot(&encoder, &snapshot) == 0U) {
        return 0;
    }
    return (snapshot.count == 1000000) &&
           (snapshot.valid_transition_count == 1000000U) &&
           (snapshot.invalid_transition_count == 0U) &&
           (snapshot.invalid_transition_latched == 0U) &&
           (snapshot.overflow_latched == 0U);
}

static int test_snapshot_rejects_in_progress_write(void)
{
    QuadratureEncoder encoder;
    QuadratureEncoderSnapshot snapshot;

    if (QuadratureEncoder_Init(&encoder, 0U, 0U, 1) == 0U) {
        return 0;
    }
    encoder.sequence = 1U;
    return QuadratureEncoder_Snapshot(&encoder, &snapshot) == 0U;
}

int main(void)
{
    int pass = 1;

    pass &= test_init_validation_and_explicit_state();
    pass &= test_forward_reverse_and_duplicate_samples();
    pass &= test_negative_polarity();
    pass &= test_invalid_transition_latch_and_resynchronization();
    pass &= test_overflow_latches_and_freezes_position();
    pass &= test_latches_clear_only_on_reinitialization();
    pass &= test_long_deterministic_rotation();
    pass &= test_snapshot_rejects_in_progress_write();

    printf("quadrature_encoder EXTI x4 decoder: %s\n",
           pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}
