/* STM32H745 target adapter; portable logic remains in handoff/src/actuator. */
#ifndef STM32_TB6612_HAL_H
#define STM32_TB6612_HAL_H

#include <stdint.h>

#include "stm32h7xx_hal.h"
#include "tb6612_driver.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    TIM_HandleTypeDef *pwm_timer;
    uint32_t pwm_channel;
    /* Must equal the configured edge-aligned timer ARR + 1. */
    uint32_t pwm_full_scale_ccr;
    /* Independent final HAL cap. Must be 1..pwm_full_scale_ccr. */
    uint32_t max_active_ccr;
    /* Electrical convention used to cross-check direction vs AIN1/AIN2. */
    uint8_t release_ain1_level;
    GPIO_TypeDef *ain1_port;
    uint16_t ain1_pin;
    GPIO_TypeDef *ain2_port;
    uint16_t ain2_pin;
    GPIO_TypeDef *stby_port;
    uint16_t stby_pin;
} Stm32Tb6612HalConfig;

typedef struct {
    Stm32Tb6612HalConfig config;
    Stm32Tb6612HalConfig initialized_config;
    uint8_t initialized;
} Stm32Tb6612Hal;

uint8_t STM32_TB6612_HAL_ConfigIsValid(
    const Stm32Tb6612HalConfig *config);

/* Starts the already-configured PWM timer channel with a safe bridge state. */
HAL_StatusTypeDef STM32_TB6612_HAL_Init(
    Stm32Tb6612Hal *adapter,
    const Stm32Tb6612HalConfig *config);

/* Safe ordering: STBY low, CCR zero, then both direction inputs low. */
HAL_StatusTypeDef STM32_TB6612_HAL_ForceSafe(
    Stm32Tb6612Hal *adapter);

/*
 * Active ordering: CCR zero, direction pins, STBY high, then target CCR.
 * Any malformed command or adapter state is forced safe before HAL_ERROR is
 * returned.
 */
HAL_StatusTypeDef STM32_TB6612_HAL_Apply(
    Stm32Tb6612Hal *adapter,
    const Tb6612Output *output);

#ifdef __cplusplus
}
#endif

#endif
