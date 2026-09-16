#ifndef QUADRATURE_ENCODER_H
#define QUADRATURE_ENCODER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * With count_polarity == +1, this AB sequence increments the count:
 *
 *     00 -> 01 -> 11 -> 10 -> 00
 *
 * A polarity of -1 reverses that convention.  Both A and B must be sampled
 * on every EXTI edge and passed to QuadratureEncoder_OnEdge().
 */
typedef struct {
    volatile uint32_t sequence;
    volatile int32_t count;
    volatile uint32_t valid_transition_count;
    volatile uint32_t invalid_transition_count;
    volatile int8_t count_polarity;
    volatile uint8_t state_ab;
    volatile uint8_t initialized;
    volatile uint8_t invalid_transition_latched;
    volatile uint8_t overflow_latched;
} QuadratureEncoder;

typedef struct {
    int32_t count;
    uint32_t valid_transition_count;
    uint32_t invalid_transition_count;
    int8_t count_polarity;
    uint8_t level_a;
    uint8_t level_b;
    uint8_t initialized;
    uint8_t invalid_transition_latched;
    uint8_t overflow_latched;
} QuadratureEncoderSnapshot;

/*
 * Initializes the decoder from the actual boot-time A and B pin levels.
 * initial_a and initial_b must each be exactly zero or one, and polarity must
 * be +1 or -1.  Initialization clears the position and both fault latches.
 * Call this while the associated EXTI interrupts are disabled.
 */
uint8_t QuadratureEncoder_Init(QuadratureEncoder *encoder,
                               uint8_t initial_a,
                               uint8_t initial_b,
                               int8_t count_polarity);

/*
 * Processes one EXTI event after sampling both A and B pins.  The return value
 * is the signed step actually applied to count: -1, 0, or +1.
 *
 * A two-bit jump is an invalid transition.  It contributes no position step,
 * latches invalid_transition_latched, and adopts the observed AB state so the
 * next valid edge can resynchronize.  Repeated identical samples contribute
 * no step and are not considered invalid.  Once count overflows, its value is
 * frozen and overflow_latched remains set until the next successful Init.
 * This function is intended for a non-reentrant EXTI handler.
 */
int8_t QuadratureEncoder_OnEdge(QuadratureEncoder *encoder,
                                uint8_t level_a,
                                uint8_t level_b);

/*
 * Takes a bounded, internally consistent foreground snapshot while EXTI may
 * update the decoder.  Returns zero for invalid arguments, an uninitialized
 * decoder, or if a stable snapshot cannot be obtained within the bounded
 * retry count.  On zero return, snapshot is cleared or diagnostic-only and
 * must not be used as an authorized position value.
 */
uint8_t QuadratureEncoder_Snapshot(
    const QuadratureEncoder *encoder,
    QuadratureEncoderSnapshot *snapshot);

#ifdef __cplusplus
}
#endif

#endif
