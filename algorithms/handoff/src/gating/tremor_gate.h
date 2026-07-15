#ifndef TREMOR_GATE_H
#define TREMOR_GATE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * V2 tremor gate for one gyro axis sampled at exactly 100 Hz.
 * Input unit: degree/second (raw BNO055 gyro after raw / 16 conversion).
 * Output: 0 = motor must remain disabled, 1 = suppression may run.
 */
typedef struct {
    float amp_on;
    float amp_off;
    float ratio_on;
    float ratio_off;
    float envelope_decay;
    uint16_t samples_on;
    uint16_t samples_off;
} TremorGateConfig;

typedef struct {
    TremorGateConfig config;
    double tremor_filter_state[4];
    double voluntary_filter_state[4];
    float tremor_envelope;
    float voluntary_envelope;
    float tremor_ratio;
    uint16_t on_count;
    uint16_t off_count;
    uint8_t enabled;
} TremorGate;

TremorGateConfig TremorGate_DefaultConfig(void);
void TremorGate_Init(TremorGate *gate, const TremorGateConfig *config);
void TremorGate_Reset(TremorGate *gate);
uint8_t TremorGate_Update(TremorGate *gate, double raw_gyro_dps);

#ifdef __cplusplus
}
#endif

#endif
