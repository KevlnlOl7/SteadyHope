#include "quadrature_encoder.h"

#include <limits.h>
#include <stddef.h>
#include <string.h>

#define QUADRATURE_ENCODER_INVALID_DELTA 2
#define QUADRATURE_ENCODER_SNAPSHOT_ATTEMPTS 8U

static const int8_t transition_delta[16] = {
    0,  1, -1, QUADRATURE_ENCODER_INVALID_DELTA,
   -1,  0, QUADRATURE_ENCODER_INVALID_DELTA,  1,
    1, QUADRATURE_ENCODER_INVALID_DELTA,  0, -1,
    QUADRATURE_ENCODER_INVALID_DELTA, -1,  1,  0
};

static uint8_t level_is_valid(uint8_t level)
{
    return (uint8_t)(level <= 1U);
}

static uint8_t make_state(uint8_t level_a, uint8_t level_b)
{
    return (uint8_t)((level_a << 1U) | level_b);
}

static void begin_write(QuadratureEncoder *encoder)
{
    encoder->sequence++;
}

static void end_write(QuadratureEncoder *encoder)
{
    encoder->sequence++;
}

static void increment_saturating(volatile uint32_t *value)
{
    if (*value < UINT32_MAX) {
        (*value)++;
    }
}

static void record_invalid_transition(QuadratureEncoder *encoder)
{
    increment_saturating(&encoder->invalid_transition_count);
    encoder->invalid_transition_latched = 1U;
}

uint8_t QuadratureEncoder_Init(QuadratureEncoder *encoder,
                               uint8_t initial_a,
                               uint8_t initial_b,
                               int8_t count_polarity)
{
    if (encoder == NULL) {
        return 0U;
    }

    memset(encoder, 0, sizeof(*encoder));
    if ((level_is_valid(initial_a) == 0U) ||
        (level_is_valid(initial_b) == 0U) ||
        ((count_polarity != 1) && (count_polarity != -1))) {
        return 0U;
    }

    encoder->count_polarity = count_polarity;
    encoder->state_ab = make_state(initial_a, initial_b);
    encoder->initialized = 1U;
    return 1U;
}

int8_t QuadratureEncoder_OnEdge(QuadratureEncoder *encoder,
                                uint8_t level_a,
                                uint8_t level_b)
{
    uint8_t next_state;
    uint8_t table_index;
    int8_t raw_delta;
    int8_t applied_delta = 0;

    if ((encoder == NULL) || (encoder->initialized != 1U)) {
        return 0;
    }

    begin_write(encoder);
    if ((level_is_valid(level_a) == 0U) ||
        (level_is_valid(level_b) == 0U)) {
        record_invalid_transition(encoder);
        end_write(encoder);
        return 0;
    }

    next_state = make_state(level_a, level_b);
    if ((encoder->state_ab > 3U) ||
        ((encoder->count_polarity != 1) &&
         (encoder->count_polarity != -1))) {
        record_invalid_transition(encoder);
        encoder->initialized = 0U;
        end_write(encoder);
        return 0;
    }

    table_index = (uint8_t)((encoder->state_ab << 2U) | next_state);
    raw_delta = transition_delta[table_index];
    encoder->state_ab = next_state;

    if (raw_delta == QUADRATURE_ENCODER_INVALID_DELTA) {
        record_invalid_transition(encoder);
        end_write(encoder);
        return 0;
    }
    if (raw_delta == 0) {
        end_write(encoder);
        return 0;
    }

    increment_saturating(&encoder->valid_transition_count);
    raw_delta = (int8_t)(raw_delta * encoder->count_polarity);
    if (encoder->overflow_latched == 0U) {
        if (((raw_delta > 0) && (encoder->count == INT32_MAX)) ||
            ((raw_delta < 0) && (encoder->count == INT32_MIN))) {
            encoder->overflow_latched = 1U;
        } else {
            encoder->count += (int32_t)raw_delta;
            applied_delta = raw_delta;
        }
    }

    end_write(encoder);
    return applied_delta;
}

uint8_t QuadratureEncoder_Snapshot(
    const QuadratureEncoder *encoder,
    QuadratureEncoderSnapshot *snapshot)
{
    uint32_t attempt;

    if (snapshot == NULL) {
        return 0U;
    }
    memset(snapshot, 0, sizeof(*snapshot));
    if (encoder == NULL) {
        return 0U;
    }

    for (attempt = 0U; attempt < QUADRATURE_ENCODER_SNAPSHOT_ATTEMPTS;
         ++attempt) {
        uint32_t sequence_before = encoder->sequence;
        uint32_t sequence_after;
        QuadratureEncoderSnapshot candidate;
        uint8_t state;

        if ((sequence_before & 1U) != 0U) {
            continue;
        }

        candidate.count = encoder->count;
        candidate.valid_transition_count =
            encoder->valid_transition_count;
        candidate.invalid_transition_count =
            encoder->invalid_transition_count;
        candidate.count_polarity = encoder->count_polarity;
        state = encoder->state_ab;
        candidate.level_a = (uint8_t)((state >> 1U) & 1U);
        candidate.level_b = (uint8_t)(state & 1U);
        candidate.initialized = encoder->initialized;
        candidate.invalid_transition_latched =
            encoder->invalid_transition_latched;
        candidate.overflow_latched = encoder->overflow_latched;

        sequence_after = encoder->sequence;
        if ((sequence_before == sequence_after) &&
            ((sequence_after & 1U) == 0U)) {
            *snapshot = candidate;
            return (uint8_t)(candidate.initialized == 1U);
        }
    }

    return 0U;
}
