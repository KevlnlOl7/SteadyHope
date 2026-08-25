#include "tremor_gate.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

_Static_assert(sizeof(float) == sizeof(uint32_t),
               "TremorGate requires 32-bit float");
_Static_assert(sizeof(double) == sizeof(uint64_t),
               "TremorGate requires 64-bit double");

/* 2nd-order Butterworth band-pass filters designed for fs = 100 Hz. */
static const double TREMOR_B[5] = {
    0.0036216815149286408, 0.0, -0.0072433630298572816, 0.0,
    0.0036216815149286408
};
static const double TREMOR_A[5] = {
    1.0, -3.6427871266953296, 5.1461877540722814,
    -3.3324758952732241, 0.83718165125602273
};
static const double VOLUNTARY_B[5] = {
    0.0036216815149286382, 0.0, -0.0072433630298572764, 0.0,
    0.0036216815149286382
};
static const double VOLUNTARY_A[5] = {
    1.0, -3.8000503652844575, 5.4393397877934069,
    -3.4763426471814802, 0.83718165125602251
};

static double df2t_step(double input,
                        const double numerator[5],
                        const double denominator[5],
                        double state[4])
{
    double output = numerator[0] * input + state[0];

    state[0] = numerator[1] * input - denominator[1] * output + state[1];
    state[1] = numerator[2] * input - denominator[2] * output + state[2];
    state[2] = numerator[3] * input - denominator[3] * output + state[3];
    state[3] = numerator[4] * input - denominator[4] * output;
    return output;
}

static uint8_t filter_state_is_finite(const double state[4])
{
    return (uint8_t)(isfinite(state[0]) && isfinite(state[1]) &&
                     isfinite(state[2]) && isfinite(state[3]));
}

static uint32_t fnv1a_u32(uint32_t hash, uint32_t value)
{
    uint32_t shift;

    for (shift = 0U; shift < 32U; shift += 8U) {
        hash ^= (value >> shift) & 0xFFU;
        hash *= 16777619U;
    }
    return hash;
}

uint32_t TremorGate_ConfigFingerprint(const TremorGateConfig *config)
{
    uint32_t hash = 2166136261U;
    uint32_t bits;

    if (config == NULL) {
        return 0U;
    }
    memcpy(&bits, &config->amp_on, sizeof(bits));
    hash = fnv1a_u32(hash, bits);
    memcpy(&bits, &config->amp_off, sizeof(bits));
    hash = fnv1a_u32(hash, bits);
    memcpy(&bits, &config->ratio_on, sizeof(bits));
    hash = fnv1a_u32(hash, bits);
    memcpy(&bits, &config->ratio_off, sizeof(bits));
    hash = fnv1a_u32(hash, bits);
    memcpy(&bits, &config->envelope_decay, sizeof(bits));
    hash = fnv1a_u32(hash, bits);
    hash = fnv1a_u32(hash, (uint32_t)config->samples_on);
    hash = fnv1a_u32(hash, (uint32_t)config->samples_off);
    return hash;
}

static uint8_t config_bits_equal(const TremorGateConfig *left,
                                 const TremorGateConfig *right)
{
    uint32_t left_bits;
    uint32_t right_bits;

#define FLOAT_FIELD_EQUAL(field)                                             \
    (memcpy(&left_bits, &left->field, sizeof(left_bits)),                    \
     memcpy(&right_bits, &right->field, sizeof(right_bits)),                 \
     left_bits == right_bits)

    return (uint8_t)(
        FLOAT_FIELD_EQUAL(amp_on) && FLOAT_FIELD_EQUAL(amp_off) &&
        FLOAT_FIELD_EQUAL(ratio_on) && FLOAT_FIELD_EQUAL(ratio_off) &&
        FLOAT_FIELD_EQUAL(envelope_decay) &&
        (left->samples_on == right->samples_on) &&
        (left->samples_off == right->samples_off));

#undef FLOAT_FIELD_EQUAL
}

static void build_runtime_guard(const TremorGate *gate, uint64_t guard[11])
{
    uint64_t bits64;
    uint32_t bits_a;
    uint32_t bits_b;
    uint32_t index;

    for (index = 0U; index < 4U; ++index) {
        memcpy(&bits64, &gate->tremor_filter_state[index], sizeof(bits64));
        guard[index * 2U] = bits64;
        memcpy(&bits64, &gate->voluntary_filter_state[index], sizeof(bits64));
        guard[index * 2U + 1U] = bits64;
    }
    memcpy(&bits_a, &gate->tremor_envelope, sizeof(bits_a));
    memcpy(&bits_b, &gate->voluntary_envelope, sizeof(bits_b));
    guard[8] = (uint64_t)bits_a | ((uint64_t)bits_b << 32U);
    memcpy(&bits_a, &gate->tremor_ratio, sizeof(bits_a));
    guard[9] = (uint64_t)bits_a |
               ((uint64_t)gate->on_count << 32U) |
               ((uint64_t)gate->off_count << 48U);
    guard[10] = (uint64_t)gate->enabled |
                ((uint64_t)gate->last_fault << 8U);
}

static void refresh_runtime_guard(TremorGate *gate)
{
    build_runtime_guard(gate, gate->runtime_guard);
}

static uint8_t runtime_guard_matches(const TremorGate *gate)
{
    uint64_t expected[11];
    uint32_t index;

    build_runtime_guard(gate, expected);
    for (index = 0U; index < 11U; ++index) {
        if (gate->runtime_guard[index] != expected[index]) {
            return 0U;
        }
    }
    return 1U;
}

static uint8_t dynamic_state_shape_is_valid(const TremorGate *gate)
{
    if ((gate->enabled > 1U) ||
        (gate->on_count > gate->config.samples_on) ||
        (gate->off_count > gate->config.samples_off) ||
        !isfinite((double)gate->tremor_envelope) ||
        !isfinite((double)gate->voluntary_envelope) ||
        !isfinite((double)gate->tremor_ratio) ||
        (gate->tremor_envelope < 0.0F) ||
        (gate->voluntary_envelope < 0.0F) ||
        (gate->tremor_ratio < 0.0F) ||
        (gate->tremor_ratio > 1.0F) ||
        (gate->last_fault > (uint8_t)TREMOR_GATE_FAULT_NUMERIC) ||
        (filter_state_is_finite(gate->tremor_filter_state) == 0U) ||
        (filter_state_is_finite(gate->voluntary_filter_state) == 0U)) {
        return 0U;
    }
    if (((gate->enabled == 0U) &&
         (gate->on_count >= gate->config.samples_on)) ||
        ((gate->enabled == 1U) &&
         ((gate->on_count != gate->config.samples_on) ||
          (gate->off_count >= gate->config.samples_off)))) {
        return 0U;
    }
    return 1U;
}

static uint8_t dynamic_state_is_valid(const TremorGate *gate)
{
    return (uint8_t)(
        (dynamic_state_shape_is_valid(gate) != 0U) &&
        (runtime_guard_matches(gate) != 0U));
}

static void fail_safe_clear(TremorGate *gate, TremorGateFault fault)
{
    TremorGateConfig config = gate->config;
    TremorGateConfig initialized_config = gate->initialized_config;
    uint32_t config_fingerprint = gate->config_fingerprint;
    uint8_t config_valid = gate->config_valid;

    memset(gate, 0, sizeof(*gate));
    gate->config = config;
    gate->initialized_config = initialized_config;
    gate->config_fingerprint = config_fingerprint;
    gate->config_valid = config_valid;
    gate->last_fault = (uint8_t)fault;
    refresh_runtime_guard(gate);
}

TremorGateConfig TremorGate_DefaultConfig(void)
{
    TremorGateConfig config;

    config.amp_on = 6.0F;
    config.amp_off = 3.0F;
    config.ratio_on = 0.55F;
    config.ratio_off = 0.45F;
    config.envelope_decay = 0.94F;
    config.samples_on = 20U;
    config.samples_off = 15U;
    return config;
}

uint8_t TremorGate_ConfigIsValid(const TremorGateConfig *config)
{
    if (config == NULL) {
        return 0U;
    }

    return (uint8_t)(
        isfinite(config->amp_on) &&
        isfinite(config->amp_off) &&
        isfinite(config->ratio_on) &&
        isfinite(config->ratio_off) &&
        isfinite(config->envelope_decay) &&
        (config->amp_on > config->amp_off) &&
        (config->amp_off >= 0.0F) &&
        (config->amp_on <= (float)TREMOR_GATE_MAX_ABS_INPUT_DPS) &&
        (config->ratio_on > config->ratio_off) &&
        (config->ratio_off >= 0.0F) &&
        (config->ratio_on <= 1.0F) &&
        (config->envelope_decay > 0.0F) &&
        (config->envelope_decay < 1.0F) &&
        (config->samples_on > 0U) &&
        (config->samples_off > 0U));
}

void TremorGate_Reset(TremorGate *gate)
{
    TremorGateConfig config;
    TremorGateConfig initialized_config;
    uint32_t expected_fingerprint;
    uint8_t config_valid;

    if (gate == NULL) {
        return;
    }

    config = gate->config;
    initialized_config = gate->initialized_config;
    expected_fingerprint = gate->config_fingerprint;
    config_valid = (uint8_t)(
        (gate->config_valid == 1U) &&
        (TremorGate_ConfigIsValid(&config) != 0U) &&
        (config_bits_equal(&config, &initialized_config) != 0U) &&
        (TremorGate_ConfigFingerprint(&config) == expected_fingerprint));
    memset(gate, 0, sizeof(*gate));
    gate->config = config;
    gate->initialized_config = initialized_config;
    gate->config_fingerprint = expected_fingerprint;
    gate->config_valid = config_valid;
    if (gate->config_valid == 0U) {
        gate->last_fault = (uint8_t)TREMOR_GATE_FAULT_CONFIG;
    }
    refresh_runtime_guard(gate);
}

void TremorGate_Init(TremorGate *gate, const TremorGateConfig *config)
{
    TremorGateConfig selected_config;

    if (gate == NULL) {
        return;
    }

    selected_config = (config != NULL) ? *config : TremorGate_DefaultConfig();
    memset(gate, 0, sizeof(*gate));
    gate->config = selected_config;
    gate->initialized_config = selected_config;
    gate->config_valid = TremorGate_ConfigIsValid(&selected_config);
    if (gate->config_valid != 0U) {
        gate->config_fingerprint =
            TremorGate_ConfigFingerprint(&selected_config);
    }
    if (gate->config_valid == 0U) {
        gate->last_fault = (uint8_t)TREMOR_GATE_FAULT_CONFIG;
    }
    refresh_runtime_guard(gate);
}

uint8_t TremorGate_IsReady(const TremorGate *gate)
{
    return (uint8_t)((gate != NULL) &&
                     (gate->config_valid == 1U) &&
                     (TremorGate_ConfigIsValid(&gate->config) != 0U) &&
                     (config_bits_equal(&gate->config,
                                        &gate->initialized_config) != 0U) &&
                     (TremorGate_ConfigFingerprint(&gate->config) ==
                      gate->config_fingerprint) &&
                     (dynamic_state_is_valid(gate) != 0U));
}

uint8_t TremorGate_Update(TremorGate *gate, double raw_gyro_dps)
{
    float tremor_sample;
    float voluntary_sample;
    float decayed_tremor;
    float decayed_voluntary;
    double tremor_output;
    double voluntary_output;
    uint8_t condition;

    if (gate == NULL) {
        return 0U;
    }
    if ((gate->config_valid != 1U) ||
        (TremorGate_ConfigIsValid(&gate->config) == 0U) ||
        (config_bits_equal(&gate->config,
                           &gate->initialized_config) == 0U) ||
        (TremorGate_ConfigFingerprint(&gate->config) !=
         gate->config_fingerprint)) {
        gate->config_valid = 0U;
        fail_safe_clear(gate, TREMOR_GATE_FAULT_CONFIG);
        return 0U;
    }
    if (dynamic_state_is_valid(gate) == 0U) {
        fail_safe_clear(gate, TREMOR_GATE_FAULT_NUMERIC);
        return 0U;
    }
    if (!isfinite(raw_gyro_dps) ||
        (fabs(raw_gyro_dps) > TREMOR_GATE_MAX_ABS_INPUT_DPS)) {
        fail_safe_clear(gate, TREMOR_GATE_FAULT_INPUT);
        return 0U;
    }

    tremor_output = df2t_step(raw_gyro_dps, TREMOR_B, TREMOR_A,
                              gate->tremor_filter_state);
    voluntary_output = df2t_step(raw_gyro_dps, VOLUNTARY_B, VOLUNTARY_A,
                                 gate->voluntary_filter_state);
    if (!isfinite(tremor_output) || !isfinite(voluntary_output) ||
        (filter_state_is_finite(gate->tremor_filter_state) == 0U) ||
        (filter_state_is_finite(gate->voluntary_filter_state) == 0U)) {
        fail_safe_clear(gate, TREMOR_GATE_FAULT_NUMERIC);
        return 0U;
    }

    tremor_sample = (float)fabs(tremor_output);
    voluntary_sample = (float)fabs(voluntary_output);

    decayed_tremor = gate->tremor_envelope * gate->config.envelope_decay;
    decayed_voluntary = gate->voluntary_envelope * gate->config.envelope_decay;
    gate->tremor_envelope =
        (tremor_sample > decayed_tremor) ? tremor_sample : decayed_tremor;
    gate->voluntary_envelope =
        (voluntary_sample > decayed_voluntary) ? voluntary_sample : decayed_voluntary;
    gate->tremor_ratio = gate->tremor_envelope /
        (gate->tremor_envelope + gate->voluntary_envelope + 1.0e-9F);

    if (!isfinite(gate->tremor_envelope) ||
        !isfinite(gate->voluntary_envelope) ||
        !isfinite(gate->tremor_ratio) ||
        (gate->tremor_envelope < 0.0F) ||
        (gate->voluntary_envelope < 0.0F) ||
        (gate->tremor_ratio < 0.0F) ||
        (gate->tremor_ratio > 1.0F)) {
        fail_safe_clear(gate, TREMOR_GATE_FAULT_NUMERIC);
        return 0U;
    }
    gate->last_fault = (uint8_t)TREMOR_GATE_FAULT_NONE;

    if (gate->enabled != 0U) {
        condition = (uint8_t)((gate->tremor_envelope >= gate->config.amp_off) &&
                              (gate->tremor_ratio >= gate->config.ratio_off));
        if (condition != 0U) {
            gate->off_count = 0U;
        } else if (gate->off_count < gate->config.samples_off) {
            gate->off_count++;
            if (gate->off_count >= gate->config.samples_off) {
                gate->enabled = 0U;
                gate->on_count = 0U;
            }
        }
    } else {
        condition = (uint8_t)((gate->tremor_envelope >= gate->config.amp_on) &&
                              (gate->tremor_ratio >= gate->config.ratio_on));
        if (condition != 0U) {
            if (gate->on_count < gate->config.samples_on) {
                gate->on_count++;
            }
            if (gate->on_count >= gate->config.samples_on) {
                gate->enabled = 1U;
                gate->off_count = 0U;
            }
        } else {
            gate->on_count = 0U;
        }
    }

    if (dynamic_state_shape_is_valid(gate) == 0U) {
        fail_safe_clear(gate, TREMOR_GATE_FAULT_NUMERIC);
        return 0U;
    }

    refresh_runtime_guard(gate);

    return gate->enabled;
}
