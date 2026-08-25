#ifndef TREMOR_GATE_H
#define TREMOR_GATE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* BNO055 gyro raw data is signed int16 with 1/16 degree/second per LSB. */
#define TREMOR_GATE_MAX_ABS_INPUT_DPS 2048.0

typedef enum {
    TREMOR_GATE_FAULT_NONE = 0,
    TREMOR_GATE_FAULT_CONFIG = 1,
    TREMOR_GATE_FAULT_INPUT = 2,
    TREMOR_GATE_FAULT_NUMERIC = 3
} TremorGateFault;

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
    /* Treat as read-only after Init; use Init again to change configuration. */
    TremorGateConfig config;
    TremorGateConfig initialized_config;
    double tremor_filter_state[4];
    double voluntary_filter_state[4];
    float tremor_envelope;
    float voluntary_envelope;
    float tremor_ratio;
    uint16_t on_count;
    uint16_t off_count;
    uint32_t config_fingerprint;
    uint64_t runtime_guard[11];
    uint8_t enabled;
    uint8_t config_valid;
    uint8_t last_fault;
} TremorGate;

TremorGateConfig TremorGate_DefaultConfig(void);
uint8_t TremorGate_ConfigIsValid(const TremorGateConfig *config);
uint32_t TremorGate_ConfigFingerprint(const TremorGateConfig *config);
void TremorGate_Init(TremorGate *gate, const TremorGateConfig *config);
void TremorGate_Reset(TremorGate *gate);
uint8_t TremorGate_IsReady(const TremorGate *gate);
uint8_t TremorGate_Update(TremorGate *gate, double raw_gyro_dps);

#ifdef __cplusplus
}
#endif

#endif
