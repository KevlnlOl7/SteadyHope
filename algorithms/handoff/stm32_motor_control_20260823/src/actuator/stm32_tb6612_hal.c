#include "stm32_tb6612_hal.h"

/* Platform-specific GPIO/PWM ordering; compile this file only for STM32. */

#include <stddef.h>
#include <string.h>

static uint8_t pin_is_one_hot(uint16_t pin)
{
    return (uint8_t)((pin != 0U) &&
                     ((pin & (uint16_t)(pin - 1U)) == 0U));
}

static uint8_t same_pin(GPIO_TypeDef *left_port,
                        uint16_t left_pin,
                        GPIO_TypeDef *right_port,
                        uint16_t right_pin)
{
    return (uint8_t)((left_port == right_port) &&
                     (left_pin == right_pin));
}

static uint8_t base_config_is_valid(
    const Stm32Tb6612HalConfig *config)
{
    uint8_t channel_valid;

    if (config == NULL) {
        return 0U;
    }
    channel_valid = (uint8_t)(
        (config->pwm_channel == TIM_CHANNEL_1) ||
        (config->pwm_channel == TIM_CHANNEL_2) ||
        (config->pwm_channel == TIM_CHANNEL_3) ||
        (config->pwm_channel == TIM_CHANNEL_4));
    if ((config->pwm_timer == NULL) ||
        (config->pwm_timer->Instance == NULL) ||
        (channel_valid == 0U) ||
        (config->ain1_port == NULL) ||
        (config->ain2_port == NULL) ||
        (config->stby_port == NULL) ||
        (pin_is_one_hot(config->ain1_pin) == 0U) ||
        (pin_is_one_hot(config->ain2_pin) == 0U) ||
        (pin_is_one_hot(config->stby_pin) == 0U) ||
        (same_pin(config->ain1_port, config->ain1_pin,
                  config->ain2_port, config->ain2_pin) != 0U) ||
        (same_pin(config->ain1_port, config->ain1_pin,
                  config->stby_port, config->stby_pin) != 0U) ||
        (same_pin(config->ain2_port, config->ain2_pin,
                  config->stby_port, config->stby_pin) != 0U)) {
        return 0U;
    }
    return 1U;
}

uint8_t STM32_TB6612_HAL_ConfigIsValid(
    const Stm32Tb6612HalConfig *config)
{
    uint32_t autoreload;

    if (base_config_is_valid(config) == 0U) {
        return 0U;
    }
    autoreload = __HAL_TIM_GET_AUTORELOAD(config->pwm_timer);
    if ((config->pwm_full_scale_ccr == 0U) ||
        (autoreload == UINT32_MAX) ||
        (config->pwm_full_scale_ccr != (autoreload + 1U))) {
        return 0U;
    }
    return 1U;
}

static uint8_t config_equal(const Stm32Tb6612HalConfig *left,
                            const Stm32Tb6612HalConfig *right)
{
    return (uint8_t)(
        (left->pwm_timer == right->pwm_timer) &&
        (left->pwm_channel == right->pwm_channel) &&
        (left->pwm_full_scale_ccr == right->pwm_full_scale_ccr) &&
        (left->ain1_port == right->ain1_port) &&
        (left->ain1_pin == right->ain1_pin) &&
        (left->ain2_port == right->ain2_port) &&
        (left->ain2_pin == right->ain2_pin) &&
        (left->stby_port == right->stby_port) &&
        (left->stby_pin == right->stby_pin));
}

static void force_safe_with_config(const Stm32Tb6612HalConfig *config)
{
    HAL_GPIO_WritePin(config->stby_port, config->stby_pin, GPIO_PIN_RESET);
    __HAL_TIM_SET_COMPARE(config->pwm_timer, config->pwm_channel, 0U);
    HAL_GPIO_WritePin(config->ain1_port, config->ain1_pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(config->ain2_port, config->ain2_pin, GPIO_PIN_RESET);
}

static const Stm32Tb6612HalConfig *known_safe_config(
    const Stm32Tb6612Hal *adapter)
{
    if (adapter == NULL) {
        return NULL;
    }
    if (base_config_is_valid(&adapter->initialized_config) != 0U) {
        return &adapter->initialized_config;
    }
    if (base_config_is_valid(&adapter->config) != 0U) {
        return &adapter->config;
    }
    return NULL;
}

HAL_StatusTypeDef STM32_TB6612_HAL_ForceSafe(
    Stm32Tb6612Hal *adapter)
{
    const Stm32Tb6612HalConfig *config = known_safe_config(adapter);

    if (config == NULL) {
        return HAL_ERROR;
    }
    force_safe_with_config(config);
    return HAL_OK;
}

HAL_StatusTypeDef STM32_TB6612_HAL_Init(
    Stm32Tb6612Hal *adapter,
    const Stm32Tb6612HalConfig *config)
{
    HAL_StatusTypeDef status;

    if (adapter == NULL) {
        return HAL_ERROR;
    }
    memset(adapter, 0, sizeof(*adapter));
    if (base_config_is_valid(config) == 0U) {
        return HAL_ERROR;
    }
    adapter->config = *config;
    adapter->initialized_config = *config;

    force_safe_with_config(&adapter->initialized_config);
    if (STM32_TB6612_HAL_ConfigIsValid(config) == 0U) {
        return HAL_ERROR;
    }
    status = HAL_TIM_PWM_Start(config->pwm_timer, config->pwm_channel);
    if (status != HAL_OK) {
        force_safe_with_config(&adapter->initialized_config);
        return status;
    }
    force_safe_with_config(&adapter->initialized_config);
    adapter->initialized = 1U;
    return HAL_OK;
}

static uint8_t output_is_safe(const Tb6612Output *output)
{
    return (uint8_t)((output->ccr == 0U) &&
                     (output->direction == 0) &&
                     (output->ain1 == 0U) &&
                     (output->ain2 == 0U) &&
                     (output->stby == 0U));
}

static uint8_t output_is_active(const Stm32Tb6612Hal *adapter,
                                const Tb6612Output *output)
{
    return (uint8_t)(
        (output->fault == (uint8_t)TB6612_DRIVER_FAULT_NONE) &&
        ((output->direction == -1) || (output->direction == 1)) &&
        (output->ain1 <= 1U) && (output->ain2 <= 1U) &&
        (output->ain1 != output->ain2) && (output->stby == 1U) &&
        (output->ccr > 0U) &&
        (output->ccr <= adapter->initialized_config.pwm_full_scale_ccr) &&
        (output->reversal_dead_ticks_remaining == 0U));
}

HAL_StatusTypeDef STM32_TB6612_HAL_Apply(
    Stm32Tb6612Hal *adapter,
    const Tb6612Output *output)
{
    const Stm32Tb6612HalConfig *config;

    if (adapter == NULL) {
        return HAL_ERROR;
    }
    config = known_safe_config(adapter);
    if ((config == NULL) || (output == NULL) ||
        (adapter->initialized != 1U) ||
        (STM32_TB6612_HAL_ConfigIsValid(&adapter->config) == 0U) ||
        (config_equal(&adapter->config,
                      &adapter->initialized_config) == 0U)) {
        if (config != NULL) {
            force_safe_with_config(config);
        }
        return HAL_ERROR;
    }

    if (output_is_safe(output) != 0U) {
        force_safe_with_config(config);
        return (output->fault == (uint8_t)TB6612_DRIVER_FAULT_NONE) ?
               HAL_OK : HAL_ERROR;
    }
    if (output_is_active(adapter, output) == 0U) {
        force_safe_with_config(config);
        return HAL_ERROR;
    }

    __HAL_TIM_SET_COMPARE(config->pwm_timer, config->pwm_channel, 0U);
    HAL_GPIO_WritePin(config->ain1_port, config->ain1_pin,
                      (output->ain1 != 0U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
    HAL_GPIO_WritePin(config->ain2_port, config->ain2_pin,
                      (output->ain2 != 0U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
    HAL_GPIO_WritePin(config->stby_port, config->stby_pin, GPIO_PIN_SET);
    __HAL_TIM_SET_COMPARE(config->pwm_timer, config->pwm_channel,
                          output->ccr);
    return HAL_OK;
}
