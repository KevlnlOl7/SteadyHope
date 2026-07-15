#include "tremor_gate.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

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

void TremorGate_Reset(TremorGate *gate)
{
    TremorGateConfig config;

    if (gate == NULL) {
        return;
    }

    config = gate->config;
    memset(gate, 0, sizeof(*gate));
    gate->config = config;
}

void TremorGate_Init(TremorGate *gate, const TremorGateConfig *config)
{
    if (gate == NULL) {
        return;
    }

    memset(gate, 0, sizeof(*gate));
    gate->config = (config != NULL) ? *config : TremorGate_DefaultConfig();
}

uint8_t TremorGate_Update(TremorGate *gate, double raw_gyro_dps)
{
    float tremor_sample;
    float voluntary_sample;
    float decayed_tremor;
    float decayed_voluntary;
    uint8_t condition;

    if (gate == NULL) {
        return 0U;
    }
    if (!isfinite(raw_gyro_dps)) {
        /* Invalid sensor data is always fail-safe and clears debounce state. */
        gate->enabled = 0U;
        gate->on_count = 0U;
        gate->off_count = 0U;
        return 0U;
    }

    tremor_sample = (float)fabs(df2t_step(raw_gyro_dps, TREMOR_B, TREMOR_A,
                                         gate->tremor_filter_state));
    voluntary_sample = (float)fabs(df2t_step(raw_gyro_dps, VOLUNTARY_B, VOLUNTARY_A,
                                            gate->voluntary_filter_state));

    decayed_tremor = gate->tremor_envelope * gate->config.envelope_decay;
    decayed_voluntary = gate->voluntary_envelope * gate->config.envelope_decay;
    gate->tremor_envelope =
        (tremor_sample > decayed_tremor) ? tremor_sample : decayed_tremor;
    gate->voluntary_envelope =
        (voluntary_sample > decayed_voluntary) ? voluntary_sample : decayed_voluntary;
    gate->tremor_ratio = gate->tremor_envelope /
        (gate->tremor_envelope + gate->voluntary_envelope + 1.0e-9F);

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

    return gate->enabled;
}
