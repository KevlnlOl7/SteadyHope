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
    /* Reviewed integer duty cap; zero deliberately locks ACTIVE output. */
    uint32_t max_active_ccr;
    /* Must equal the reviewed Tb6612DriverConfig polarity. */
    uint8_t release_ain1_level;
    GPIO_TypeDef *ain1_port;
    uint16_t ain1_pin;
    GPIO_TypeDef *ain2_port;
    uint16_t ain2_pin;
    GPIO_TypeDef *stby_port;
    uint16_t stby_pin;
} Stm32Tb6612HalConfig;

typedef struct {
    uint64_t lifecycle_magic;
    uint64_t lifecycle_guard[2];
    Stm32Tb6612HalConfig config;
    Stm32Tb6612HalConfig initialized_config;
    TIM_TypeDef *expected_pwm_instance;
    /*
     * Domain-separated guards are fixed after Init.  Pointer values are
     * fingerprinted without dereference; expected_pwm_instance separately
     * seals the mutable timer-handle binding.
     */
    uint64_t config_guard[2];
    uint64_t initialized_config_guard[2];
    uint64_t expected_pwm_instance_guard[2];
    uint64_t runtime_guard[2];
    int8_t last_active_direction;
    uint8_t initialized;
} Stm32Tb6612Hal;

/*
 * Init, ForceSafe, and Apply are linearized against maskable interrupts with
 * exact nested PRIMASK preservation.  A pending operation runs only after the
 * current operation restores PRIMASK; a later valid Apply may therefore
 * supersede an earlier ForceSafe.  The canonical integration keeps its final
 * authority recheck, Apply, and applied-output telemetry in one outer critical
 * section so a stale main-loop command cannot supersede an EXTI fail-safe.
 */

uint8_t STM32_TB6612_HAL_ConfigIsValid(
    const Stm32Tb6612HalConfig *config);

/*
 * Starts the already-configured PWM timer channel with a safe bridge state.
 * This is normally boot-only.  If lifecycle markers or either guarded config
 * reveal an older adapter, Init first attempts guard-aware ForceSafe; it never
 * erases a guard-recognizable live state that could not be made safe.
 * Init serializes all validation, register/state writes, and the non-blocking
 * PWM start by saving, masking, and exactly restoring PRIMASK.  This nests
 * safely when the caller already has maskable interrupts disabled.
 */
HAL_StatusTypeDef STM32_TB6612_HAL_Init(
    Stm32Tb6612Hal *adapter,
    const Stm32Tb6612HalConfig *config);

/*
 * Normal safe ordering: STBY low, CCR zero, then both direction inputs low.
 * If the sealed timer Instance binding is corrupt, HAL deliberately skips
 * the unsafe CCR access, writes STBY low before both direction inputs low,
 * latches uninitialized, and returns HAL_ERROR.
 * A successful explicit safe operation clears the remembered direction.
 * The complete operation is serialized with Apply/Init using exact nested
 * PRIMASK save/restore semantics; it performs no waiting while masked.
 */
HAL_StatusTypeDef STM32_TB6612_HAL_ForceSafe(
    Stm32Tb6612Hal *adapter);

/*
 * Active ordering: CCR zero, direction pins, STBY high, then target CCR.
 * max_active_ccr == 0 is a valid locked configuration that rejects every
 * ACTIVE output while retaining Init and ForceSafe operation.
 * Direction and AIN levels must agree with release_ain1_level.  A direct
 * active-to-opposite-active transition is rejected until an explicit SAFE
 * output has cleared the remembered direction.  A malformed command/state is
 * forced safe before HAL_ERROR only when at least one sealed full or GPIO-only
 * snapshot remains recognizable.  If none remains, HAL returns HAL_ERROR and
 * the caller must use an independent hard-coded fail-safe path.
 * Authority/output validation through all hardware and adapter-state writes is
 * one PRIMASK-serialized transaction.  The exact incoming mask is restored,
 * including when called from an ISR or an outer critical section.
 */
HAL_StatusTypeDef STM32_TB6612_HAL_Apply(
    Stm32Tb6612Hal *adapter,
    const Tb6612Output *output);

#ifdef __cplusplus
}
#endif

#endif
