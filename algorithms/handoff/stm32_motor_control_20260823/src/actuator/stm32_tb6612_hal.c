#include "stm32_tb6612_hal.h"

/* Platform-specific GPIO/PWM ordering; compile this file only for STM32. */

#include <stddef.h>
#include <string.h>

#define CONFIG_GUARD_DOMAIN_ACTIVE \
    UINT64_C(0x2A6F91C4D8375BE0)
#define CONFIG_GUARD_DOMAIN_INITIALIZED \
    UINT64_C(0xD5906E3B27C8A41F)
#define ADAPTER_LIFECYCLE_MAGIC \
    UINT64_C(0x5348544236363132)

typedef enum {
    ADAPTER_IDENTITY_FRESH = 0,
    ADAPTER_IDENTITY_VALID = 1,
    ADAPTER_IDENTITY_CORRUPT = 2
} AdapterIdentityStatus;

_Static_assert(sizeof(TIM_HandleTypeDef *) <= sizeof(uint64_t),
               "timer pointer must fit fingerprint word");
_Static_assert(sizeof(GPIO_TypeDef *) <= sizeof(uint64_t),
               "GPIO pointer must fit fingerprint word");

/*
 * Serialize adapter authority checks, hardware writes, and state commits with
 * the encoder EXTI fail-safe path.  Restoring the exact saved PRIMASK makes
 * these helpers safe when the caller is already in an ISR/critical section.
 * The barriers keep compiler/CPU ordering across the interrupt-mask boundary.
 */
static uint32_t enter_critical_section(void)
{
    uint32_t saved_primask = __get_PRIMASK();

    __disable_irq();
    __DMB();
    return saved_primask;
}

static void exit_critical_section(uint32_t saved_primask)
{
    __DMB();
    __set_PRIMASK(saved_primask);
}

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

static uint8_t gpio_config_is_valid(
    const Stm32Tb6612HalConfig *config)
{
    if ((config == NULL) ||
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
        (channel_valid == 0U) ||
        (config->release_ain1_level > 1U) ||
        (gpio_config_is_valid(config) == 0U)) {
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
    if (config->pwm_timer->Instance == NULL) {
        return 0U;
    }
    autoreload = __HAL_TIM_GET_AUTORELOAD(config->pwm_timer);
    if ((config->pwm_full_scale_ccr == 0U) ||
        (config->max_active_ccr > config->pwm_full_scale_ccr) ||
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
        (left->max_active_ccr == right->max_active_ccr) &&
        (left->release_ain1_level == right->release_ain1_level) &&
        (left->ain1_port == right->ain1_port) &&
        (left->ain1_pin == right->ain1_pin) &&
        (left->ain2_port == right->ain2_port) &&
        (left->ain2_pin == right->ain2_pin) &&
        (left->stby_port == right->stby_port) &&
        (left->stby_pin == right->stby_pin));
}

static uint64_t fingerprint_mix(uint64_t fingerprint, uint64_t value)
{
    value ^= value >> 30U;
    value *= UINT64_C(0xBF58476D1CE4E5B9);
    value ^= value >> 27U;
    value *= UINT64_C(0x94D049BB133111EB);
    value ^= value >> 31U;
    fingerprint ^= value;
    fingerprint *= UINT64_C(0x9E3779B185EBCA87);
    return fingerprint;
}

static uint64_t object_representation_u64(const void *object,
                                          size_t object_size)
{
    uint64_t value = 0U;

    if (object_size > sizeof(value)) {
        return UINT64_MAX;
    }
    memcpy(&value, object, object_size);
    return value;
}

static void expected_lifecycle_guards(
    const Stm32Tb6612Hal *adapter,
    uint64_t expected[2])
{
    uint64_t address_fingerprint = fingerprint_mix(
        UINT64_C(0x17C8A5E24B906D3F),
        (uint64_t)(uintptr_t)adapter);

    expected[0] =
        address_fingerprint ^ UINT64_C(0xA63F19D70C52E84B);
    expected[1] =
        (~address_fingerprint) ^ UINT64_C(0x5D08C274B1E93A60);
}

static AdapterIdentityStatus adapter_identity_status(
    const Stm32Tb6612Hal *adapter)
{
    uint64_t magic;
    uint64_t guard[2];
    uint64_t expected[2];
    uint8_t magic_matches;
    uint8_t guard0_matches;
    uint8_t guard1_matches;

    memcpy(&magic, &adapter->lifecycle_magic, sizeof(magic));
    memcpy(guard, adapter->lifecycle_guard, sizeof(guard));
    expected_lifecycle_guards(adapter, expected);
    magic_matches = (uint8_t)(magic == ADAPTER_LIFECYCLE_MAGIC);
    guard0_matches = (uint8_t)(guard[0] == expected[0]);
    guard1_matches = (uint8_t)(guard[1] == expected[1]);
    if ((magic_matches != 0U) &&
        (guard0_matches != 0U) &&
        (guard1_matches != 0U)) {
        return ADAPTER_IDENTITY_VALID;
    }
    if ((magic_matches != 0U) ||
        (guard0_matches != 0U) ||
        (guard1_matches != 0U)) {
        return ADAPTER_IDENTITY_CORRUPT;
    }
    return ADAPTER_IDENTITY_FRESH;
}

static void establish_adapter_identity(Stm32Tb6612Hal *adapter)
{
    adapter->lifecycle_magic = ADAPTER_LIFECYCLE_MAGIC;
    expected_lifecycle_guards(adapter, adapter->lifecycle_guard);
}

static void seal_expected_pwm_instance(Stm32Tb6612Hal *adapter)
{
    uint64_t fingerprint = fingerprint_mix(
        UINT64_C(0x8B42F16D3CA795E0),
        object_representation_u64(
            &adapter->expected_pwm_instance,
            sizeof(adapter->expected_pwm_instance)));

    adapter->expected_pwm_instance_guard[0] =
        fingerprint ^ UINT64_C(0x36E9A14C7B205FD8);
    adapter->expected_pwm_instance_guard[1] =
        (~fingerprint) ^ UINT64_C(0xC8245D09E17AB630);
}

static uint8_t expected_pwm_instance_is_intact(
    const Stm32Tb6612Hal *adapter)
{
    uint64_t instance_bits = object_representation_u64(
        &adapter->expected_pwm_instance,
        sizeof(adapter->expected_pwm_instance));
    uint64_t fingerprint = fingerprint_mix(
        UINT64_C(0x8B42F16D3CA795E0),
        instance_bits);

    return (uint8_t)(
        (instance_bits != 0U) &&
        (adapter->expected_pwm_instance_guard[0] ==
         (fingerprint ^ UINT64_C(0x36E9A14C7B205FD8))) &&
        (adapter->expected_pwm_instance_guard[1] ==
         ((~fingerprint) ^ UINT64_C(0xC8245D09E17AB630))));
}

/* Hash snapshot fields and pointer values only; never dereference a pointer. */
static uint64_t config_fingerprint(
    const Stm32Tb6612HalConfig *config,
    uint64_t domain)
{
    uint64_t fingerprint = UINT64_C(0xC71D43A5962BE80F);

    fingerprint = fingerprint_mix(fingerprint, domain);
    fingerprint = fingerprint_mix(
        fingerprint, object_representation_u64(
            &config->pwm_timer, sizeof(config->pwm_timer)));
    fingerprint = fingerprint_mix(
        fingerprint, object_representation_u64(
            &config->pwm_channel, sizeof(config->pwm_channel)));
    fingerprint = fingerprint_mix(
        fingerprint, object_representation_u64(
            &config->pwm_full_scale_ccr,
            sizeof(config->pwm_full_scale_ccr)));
    fingerprint = fingerprint_mix(
        fingerprint, object_representation_u64(
            &config->max_active_ccr, sizeof(config->max_active_ccr)));
    fingerprint = fingerprint_mix(
        fingerprint, object_representation_u64(
            &config->release_ain1_level,
            sizeof(config->release_ain1_level)));
    fingerprint = fingerprint_mix(
        fingerprint, object_representation_u64(
            &config->ain1_port, sizeof(config->ain1_port)));
    fingerprint = fingerprint_mix(
        fingerprint, object_representation_u64(
            &config->ain1_pin, sizeof(config->ain1_pin)));
    fingerprint = fingerprint_mix(
        fingerprint, object_representation_u64(
            &config->ain2_port, sizeof(config->ain2_port)));
    fingerprint = fingerprint_mix(
        fingerprint, object_representation_u64(
            &config->ain2_pin, sizeof(config->ain2_pin)));
    fingerprint = fingerprint_mix(
        fingerprint, object_representation_u64(
            &config->stby_port, sizeof(config->stby_port)));
    fingerprint = fingerprint_mix(
        fingerprint, object_representation_u64(
            &config->stby_pin, sizeof(config->stby_pin)));
    return fingerprint;
}

static void seal_config_snapshot(
    const Stm32Tb6612HalConfig *config,
    uint64_t guard[2],
    uint64_t domain)
{
    uint64_t fingerprint = config_fingerprint(config, domain);

    guard[0] = fingerprint ^ UINT64_C(0x4F28B7D19A63CE05);
    guard[1] = (~fingerprint) ^ UINT64_C(0x719AC5E30BF2468D);
}

static uint8_t config_snapshot_is_intact(
    const Stm32Tb6612HalConfig *config,
    const uint64_t guard[2],
    uint64_t domain)
{
    uint64_t fingerprint;

    if ((config == NULL) || (guard == NULL)) {
        return 0U;
    }
    fingerprint = config_fingerprint(config, domain);
    return (uint8_t)(
        (guard[0] ==
         (fingerprint ^ UINT64_C(0x4F28B7D19A63CE05))) &&
        (guard[1] ==
         ((~fingerprint) ^ UINT64_C(0x719AC5E30BF2468D))));
}

static uint8_t config_timer_binding_is_intact(
    const Stm32Tb6612Hal *adapter,
    const Stm32Tb6612HalConfig *config,
    const uint64_t guard[2],
    uint64_t domain)
{
    /*
     * Short-circuit order is safety-critical: validate the stored handle
     * pointer and sealed Instance value before reading handle->Instance.
     */
    return (uint8_t)(
        (config_snapshot_is_intact(config, guard, domain) != 0U) &&
        (expected_pwm_instance_is_intact(adapter) != 0U) &&
        (config->pwm_timer != NULL) &&
        (config->pwm_timer->Instance == adapter->expected_pwm_instance));
}

static uint8_t config_snapshot_pair_is_valid(
    const Stm32Tb6612Hal *adapter)
{
    /* Keep this ordering: no validation may dereference a corrupt pointer. */
    return (uint8_t)(
        (config_timer_binding_is_intact(
             adapter, &adapter->config, adapter->config_guard,
             CONFIG_GUARD_DOMAIN_ACTIVE) != 0U) &&
        (config_timer_binding_is_intact(
             adapter, &adapter->initialized_config,
             adapter->initialized_config_guard,
             CONFIG_GUARD_DOMAIN_INITIALIZED) != 0U) &&
        (config_equal(&adapter->config,
                      &adapter->initialized_config) != 0U) &&
        (STM32_TB6612_HAL_ConfigIsValid(&adapter->config) != 0U));
}

static uint64_t state_snapshot(const Stm32Tb6612Hal *adapter)
{
    return (uint64_t)(uint8_t)adapter->last_active_direction |
           ((uint64_t)adapter->initialized << 8U);
}

static void refresh_runtime_guard(Stm32Tb6612Hal *adapter)
{
    uint64_t snapshot = state_snapshot(adapter);

    adapter->runtime_guard[0] =
        snapshot ^ UINT64_C(0xD3A7C9E2514B608F);
    adapter->runtime_guard[1] =
        (~snapshot) ^ UINT64_C(0x6C18F40A9B35E7D2);
}

static uint8_t runtime_state_is_valid(const Stm32Tb6612Hal *adapter)
{
    uint64_t snapshot = state_snapshot(adapter);

    return (uint8_t)(
        ((adapter->last_active_direction == -1) ||
         (adapter->last_active_direction == 0) ||
         (adapter->last_active_direction == 1)) &&
        (adapter->initialized <= 1U) &&
        (adapter->runtime_guard[0] ==
         (snapshot ^ UINT64_C(0xD3A7C9E2514B608F))) &&
        (adapter->runtime_guard[1] ==
         ((~snapshot) ^ UINT64_C(0x6C18F40A9B35E7D2))));
}

static void force_safe_with_config(const Stm32Tb6612HalConfig *config)
{
    HAL_GPIO_WritePin(config->stby_port, config->stby_pin, GPIO_PIN_RESET);
    __HAL_TIM_SET_COMPARE(config->pwm_timer, config->pwm_channel, 0U);
    HAL_GPIO_WritePin(config->ain1_port, config->ain1_pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(config->ain2_port, config->ain2_pin, GPIO_PIN_RESET);
}

static void force_gpio_safe_without_pwm(
    const Stm32Tb6612HalConfig *config)
{
    /* A corrupt timer binding must not prevent the hardware bridge disable. */
    HAL_GPIO_WritePin(config->stby_port, config->stby_pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(config->ain1_port, config->ain1_pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(config->ain2_port, config->ain2_pin, GPIO_PIN_RESET);
}

static const Stm32Tb6612HalConfig *known_safe_config(
    const Stm32Tb6612Hal *adapter)
{
    if (adapter == NULL) {
        return NULL;
    }
    if ((config_timer_binding_is_intact(
             adapter, &adapter->initialized_config,
             adapter->initialized_config_guard,
             CONFIG_GUARD_DOMAIN_INITIALIZED) != 0U) &&
        (base_config_is_valid(&adapter->initialized_config) != 0U)) {
        return &adapter->initialized_config;
    }
    if ((config_timer_binding_is_intact(
             adapter, &adapter->config, adapter->config_guard,
             CONFIG_GUARD_DOMAIN_ACTIVE) != 0U) &&
        (base_config_is_valid(&adapter->config) != 0U)) {
        return &adapter->config;
    }
    return NULL;
}

static const Stm32Tb6612HalConfig *known_safe_gpio_config(
    const Stm32Tb6612Hal *adapter)
{
    if (adapter == NULL) {
        return NULL;
    }
    if ((config_snapshot_is_intact(
             &adapter->initialized_config,
             adapter->initialized_config_guard,
             CONFIG_GUARD_DOMAIN_INITIALIZED) != 0U) &&
        (gpio_config_is_valid(&adapter->initialized_config) != 0U)) {
        return &adapter->initialized_config;
    }
    if ((config_snapshot_is_intact(
             &adapter->config, adapter->config_guard,
             CONFIG_GUARD_DOMAIN_ACTIVE) != 0U) &&
        (gpio_config_is_valid(&adapter->config) != 0U)) {
        return &adapter->config;
    }
    return NULL;
}

HAL_StatusTypeDef STM32_TB6612_HAL_ForceSafe(
    Stm32Tb6612Hal *adapter)
{
    const Stm32Tb6612HalConfig *config;
    const Stm32Tb6612HalConfig *gpio_config;
    HAL_StatusTypeDef status = HAL_ERROR;
    AdapterIdentityStatus identity_status;
    uint8_t authority_valid;
    uint32_t saved_primask = enter_critical_section();

    if (adapter == NULL) {
        goto done;
    }
    identity_status = adapter_identity_status(adapter);
    config = known_safe_config(adapter);
    if (config == NULL) {
        gpio_config = known_safe_gpio_config(adapter);
        if (gpio_config != NULL) {
            force_gpio_safe_without_pwm(gpio_config);
        }
        adapter->initialized = 0U;
        adapter->last_active_direction = 0;
        refresh_runtime_guard(adapter);
        goto done;
    }
    authority_valid = (identity_status == ADAPTER_IDENTITY_VALID) ?
                      runtime_state_is_valid(adapter) : 0U;
    if (config_snapshot_pair_is_valid(adapter) == 0U) {
        authority_valid = 0U;
    }
    force_safe_with_config(config);
    adapter->last_active_direction = 0;
    if (authority_valid == 0U) {
        adapter->initialized = 0U;
        refresh_runtime_guard(adapter);
        goto done;
    }
    refresh_runtime_guard(adapter);
    status = HAL_OK;

done:
    exit_critical_section(saved_primask);
    return status;
}

HAL_StatusTypeDef STM32_TB6612_HAL_Init(
    Stm32Tb6612Hal *adapter,
    const Stm32Tb6612HalConfig *config)
{
    HAL_StatusTypeDef status = HAL_ERROR;
    AdapterIdentityStatus identity_status;
    uint8_t old_config_recognizable;
    uint32_t saved_primask = enter_critical_section();

    if (adapter == NULL) {
        goto done;
    }
    identity_status = adapter_identity_status(adapter);
    old_config_recognizable = (uint8_t)(
        (known_safe_config(adapter) != NULL) ||
        (known_safe_gpio_config(adapter) != NULL));
    if (identity_status == ADAPTER_IDENTITY_VALID) {
        if (STM32_TB6612_HAL_ForceSafe(adapter) != HAL_OK) {
            goto done;
        }
        if (STM32_TB6612_HAL_ConfigIsValid(config) == 0U) {
            adapter->initialized = 0U;
            adapter->last_active_direction = 0;
            refresh_runtime_guard(adapter);
            goto done;
        }
    } else if ((identity_status == ADAPTER_IDENTITY_CORRUPT) ||
               (old_config_recognizable != 0U)) {
        (void)STM32_TB6612_HAL_ForceSafe(adapter);
        goto done;
    }
    memset(adapter, 0, sizeof(*adapter));
    if ((base_config_is_valid(config) == 0U) ||
        (config->pwm_timer->Instance == NULL)) {
        goto done;
    }
    adapter->config = *config;
    adapter->initialized_config = *config;
    adapter->expected_pwm_instance = config->pwm_timer->Instance;
    seal_config_snapshot(&adapter->config, adapter->config_guard,
                         CONFIG_GUARD_DOMAIN_ACTIVE);
    seal_config_snapshot(&adapter->initialized_config,
                         adapter->initialized_config_guard,
                         CONFIG_GUARD_DOMAIN_INITIALIZED);
    seal_expected_pwm_instance(adapter);
    establish_adapter_identity(adapter);

    force_safe_with_config(&adapter->initialized_config);
    if (config_snapshot_pair_is_valid(adapter) == 0U) {
        refresh_runtime_guard(adapter);
        goto done;
    }
    /* HAL_TIM_PWM_Start only updates timer registers; it does not wait. */
    status = HAL_TIM_PWM_Start(
        adapter->initialized_config.pwm_timer,
        adapter->initialized_config.pwm_channel);
    if (status != HAL_OK) {
        force_safe_with_config(&adapter->initialized_config);
        refresh_runtime_guard(adapter);
        goto done;
    }
    force_safe_with_config(&adapter->initialized_config);
    adapter->initialized = 1U;
    adapter->last_active_direction = 0;
    refresh_runtime_guard(adapter);
    status = HAL_OK;

done:
    exit_critical_section(saved_primask);
    return status;
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
    uint8_t expected_ain1 =
        (output->direction == 1) ?
        adapter->initialized_config.release_ain1_level :
        (uint8_t)(1U -
                  adapter->initialized_config.release_ain1_level);

    return (uint8_t)(
        (output->fault == (uint8_t)TB6612_DRIVER_FAULT_NONE) &&
        ((output->direction == -1) || (output->direction == 1)) &&
        (output->ain1 <= 1U) && (output->ain2 <= 1U) &&
        (output->ain1 == expected_ain1) &&
        (output->ain2 == (uint8_t)(1U - expected_ain1)) &&
        (output->stby == 1U) &&
        (output->ccr > 0U) &&
        (adapter->initialized_config.max_active_ccr > 0U) &&
        (output->ccr <= adapter->initialized_config.max_active_ccr) &&
        (output->ccr <=
         adapter->initialized_config.pwm_full_scale_ccr) &&
        (output->reversal_dead_ticks_remaining == 0U));
}

HAL_StatusTypeDef STM32_TB6612_HAL_Apply(
    Stm32Tb6612Hal *adapter,
    const Tb6612Output *output)
{
    const Stm32Tb6612HalConfig *config;
    const Stm32Tb6612HalConfig *gpio_config;
    HAL_StatusTypeDef status = HAL_ERROR;
    AdapterIdentityStatus identity_status;
    uint32_t saved_primask = enter_critical_section();

    if (adapter == NULL) {
        goto done;
    }
    identity_status = adapter_identity_status(adapter);
    config = known_safe_config(adapter);
    if ((identity_status != ADAPTER_IDENTITY_VALID) ||
        (config == NULL) || (output == NULL) ||
        (adapter->initialized != 1U) ||
        (runtime_state_is_valid(adapter) == 0U) ||
        (config_snapshot_pair_is_valid(adapter) == 0U)) {
        if (config != NULL) {
            force_safe_with_config(config);
        } else {
            gpio_config = known_safe_gpio_config(adapter);
            if (gpio_config != NULL) {
                force_gpio_safe_without_pwm(gpio_config);
            }
        }
        adapter->initialized = 0U;
        adapter->last_active_direction = 0;
        refresh_runtime_guard(adapter);
        goto done;
    }

    if (output_is_safe(output) != 0U) {
        force_safe_with_config(config);
        adapter->last_active_direction = 0;
        refresh_runtime_guard(adapter);
        status = (output->fault == (uint8_t)TB6612_DRIVER_FAULT_NONE) ?
                 HAL_OK : HAL_ERROR;
        goto done;
    }
    if (output_is_active(adapter, output) == 0U) {
        force_safe_with_config(config);
        goto done;
    }
    if ((adapter->last_active_direction != 0) &&
        (output->direction != adapter->last_active_direction)) {
        force_safe_with_config(config);
        goto done;
    }

    __HAL_TIM_SET_COMPARE(config->pwm_timer, config->pwm_channel, 0U);
    HAL_GPIO_WritePin(config->ain1_port, config->ain1_pin,
                      (output->ain1 != 0U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
    HAL_GPIO_WritePin(config->ain2_port, config->ain2_pin,
                      (output->ain2 != 0U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
    HAL_GPIO_WritePin(config->stby_port, config->stby_pin, GPIO_PIN_SET);
    __HAL_TIM_SET_COMPARE(config->pwm_timer, config->pwm_channel,
                          output->ccr);
    adapter->last_active_direction = output->direction;
    refresh_runtime_guard(adapter);
    status = HAL_OK;

done:
    exit_critical_section(saved_primask);
    return status;
}
