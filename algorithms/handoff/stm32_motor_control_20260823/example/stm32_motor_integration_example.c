/*
 * BENCH-ONLY ILLUSTRATIVE GLUE CODE -- NOT TARGET-BUILT OR BOARD-TESTED.
 *
 * Preconditions:
 *   - MX_GPIO_Init() and MX_TIM1_Init() have completed.
 *   - STBY is wired to D4/PK1 with an external pulldown, not to 3V3.
 *   - CubeMX labels below resolve to D2/PG3, D3/PA6, D4/PK1,
 *     D6/PE6 and D7/PI8; PA8 is TIM1_CH1.
 *   - The supplied configs are reviewed release inputs, not unit-test values.
 *   - All tests are 6 V, current-limited, fixture-only, with no human load.
 *
 * This file intentionally contains no duty, gain, travel or timeout default.
 * Integrate the pattern into the latest CubeIDE project; do not add this file
 * to a powered build until every placeholder/pin/timer assumption is checked.
 */

#include "main.h"

#include "motor_command_mapper.h"
#include "motor_position_guard.h"
#include "quadrature_encoder.h"
#include "stm32_tb6612_hal.h"
#include "tb6612_driver.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

/* These names are generated only after assigning the labels in CubeMX. */
#if !defined(MOTOR_AIN1_GPIO_Port) || !defined(MOTOR_AIN1_Pin) || \
    !defined(MOTOR_AIN2_GPIO_Port) || !defined(MOTOR_AIN2_Pin) || \
    !defined(MOTOR_STBY_GPIO_Port) || !defined(MOTOR_STBY_Pin) || \
    !defined(ENCODER_A_GPIO_Port) || !defined(ENCODER_A_Pin) || \
    !defined(ENCODER_B_GPIO_Port) || !defined(ENCODER_B_Pin)
#error "Assign and verify the motor/encoder CubeMX pin labels first"
#endif

extern TIM_HandleTypeDef htim1;

typedef struct {
    int32_t encoder_count;
    int64_t relative_position_counts;
    uint32_t command_ccr;
    uint8_t gate_enabled;
    uint8_t actuation_permitted;
    uint8_t motor_output_active;
    uint8_t calibration_required;
    uint8_t encoder_valid;
    uint8_t encoder_invalid_transition_latched;
    uint8_t encoder_overflow_latched;
    uint8_t position_fault;
    uint8_t driver_fault;
    uint8_t hal_error;
    int8_t command_direction;
} MotorControlExampleTelemetry;

static QuadratureEncoder g_encoder;
static MotorPositionGuard g_position_guard;
static Tb6612Driver g_driver;
static Stm32Tb6612Hal g_motor_hal;
static MotorControlExampleTelemetry g_telemetry;
static uint8_t g_initialized;

static uint8_t read_level(GPIO_TypeDef *port, uint16_t pin)
{
    return (HAL_GPIO_ReadPin(port, pin) == GPIO_PIN_SET) ? 1U : 0U;
}

static uint8_t snapshot_encoder(QuadratureEncoderSnapshot *snapshot)
{
    uint8_t snapshot_ok;

    if (snapshot == NULL) {
        return 0U;
    }
    snapshot_ok = QuadratureEncoder_Snapshot(&g_encoder, snapshot);
    if (snapshot_ok == 0U) {
        return 0U;
    }
    return (uint8_t)((snapshot->initialized == 1U) &&
                     (snapshot->invalid_transition_latched == 0U) &&
                     (snapshot->overflow_latched == 0U));
}

static void publish_encoder_telemetry(
    const QuadratureEncoderSnapshot *snapshot,
    uint8_t encoder_valid)
{
    g_telemetry.encoder_valid = encoder_valid;
    if (snapshot != NULL) {
        g_telemetry.encoder_count = snapshot->count;
        g_telemetry.encoder_invalid_transition_latched =
            snapshot->invalid_transition_latched;
        g_telemetry.encoder_overflow_latched =
            snapshot->overflow_latched;
    }
}

/*
 * A software-safe command is generated as well as a direct HAL force-safe.
 * A real integration must also assert the independent hardware power cutoff.
 */
static void force_safe(void)
{
    Tb6612Output safe_output;
    Tb6612DriverResult result;

    memset(&safe_output, 0, sizeof(safe_output));
    if (g_driver.initialized == 1U) {
        result = TB6612Driver_Update(&g_driver, 0, 0.0, 0U,
                                    &safe_output);
        if (result != TB6612_DRIVER_ERROR) {
            (void)STM32_TB6612_HAL_Apply(&g_motor_hal, &safe_output);
        }
    }
    if (STM32_TB6612_HAL_ForceSafe(&g_motor_hal) != HAL_OK) {
        g_telemetry.hal_error = 1U;
    }
    g_telemetry.motor_output_active = 0U;
    g_telemetry.command_direction = 0;
    g_telemetry.command_ccr = 0U;
}

/*
 * Call after MX_GPIO_Init() and MX_TIM1_Init(), before motor VM is enabled.
 * The caller must obtain both configs from a reviewed, build-bound registry.
 */
uint8_t MotorControlExample_Init(
    const Tb6612DriverConfig *driver_config,
    const MotorPositionGuardConfig *position_config,
    int8_t encoder_count_polarity)
{
    Stm32Tb6612HalConfig hal_config;
    Tb6612Output initial_output;
    uint8_t initial_a;
    uint8_t initial_b;

    memset(&g_encoder, 0, sizeof(g_encoder));
    memset(&g_position_guard, 0, sizeof(g_position_guard));
    memset(&g_driver, 0, sizeof(g_driver));
    memset(&g_motor_hal, 0, sizeof(g_motor_hal));
    memset(&g_telemetry, 0, sizeof(g_telemetry));
    memset(&initial_output, 0, sizeof(initial_output));
    g_initialized = 0U;
    g_telemetry.calibration_required = 1U;

    if ((driver_config == NULL) || (position_config == NULL)) {
        return 0U;
    }

    hal_config.pwm_timer = &htim1;
    hal_config.pwm_channel = TIM_CHANNEL_1;
    /* HAL validates this value against the actual ARR + 1. */
    hal_config.pwm_full_scale_ccr = driver_config->pwm_full_scale_ccr;
    hal_config.ain1_port = MOTOR_AIN1_GPIO_Port;
    hal_config.ain1_pin = MOTOR_AIN1_Pin;
    hal_config.ain2_port = MOTOR_AIN2_GPIO_Port;
    hal_config.ain2_pin = MOTOR_AIN2_Pin;
    hal_config.stby_port = MOTOR_STBY_GPIO_Port;
    hal_config.stby_pin = MOTOR_STBY_Pin;

    HAL_NVIC_DisableIRQ(EXTI9_5_IRQn);

    if (STM32_TB6612_HAL_Init(&g_motor_hal, &hal_config) != HAL_OK) {
        g_telemetry.hal_error = 1U;
        goto fail;
    }
    if (TB6612Driver_Init(&g_driver, driver_config,
                          &initial_output) == TB6612_DRIVER_ERROR) {
        g_telemetry.driver_fault = initial_output.fault;
        goto fail;
    }
    if (STM32_TB6612_HAL_Apply(&g_motor_hal,
                               &initial_output) != HAL_OK) {
        g_telemetry.hal_error = 1U;
        goto fail;
    }
    if (MotorPositionGuard_Init(&g_position_guard,
                                position_config) == 0U) {
        goto fail;
    }

    initial_a = read_level(ENCODER_A_GPIO_Port, ENCODER_A_Pin);
    initial_b = read_level(ENCODER_B_GPIO_Port, ENCODER_B_Pin);
    if (QuadratureEncoder_Init(&g_encoder, initial_a, initial_b,
                               encoder_count_polarity) == 0U) {
        goto fail;
    }

    __HAL_GPIO_EXTI_CLEAR_IT(ENCODER_A_Pin);
    __HAL_GPIO_EXTI_CLEAR_IT(ENCODER_B_Pin);
    g_initialized = 1U;
    HAL_NVIC_EnableIRQ(EXTI9_5_IRQn);
    return 1U;

fail:
    force_safe();
    HAL_NVIC_EnableIRQ(EXTI9_5_IRQn);
    return 0U;
}

/*
 * Call this from the project's existing HAL_GPIO_EXTI_Callback().  The
 * EXTI9_5_IRQHandler generated by CubeMX must dispatch both encoder pins.
 */
void MotorControlExample_OnExti(uint16_t gpio_pin)
{
    uint8_t level_a;
    uint8_t level_b;

    if ((g_initialized != 1U) ||
        ((gpio_pin != ENCODER_A_Pin) &&
         (gpio_pin != ENCODER_B_Pin))) {
        return;
    }

    level_a = read_level(ENCODER_A_GPIO_Port, ENCODER_A_Pin);
    level_b = read_level(ENCODER_B_GPIO_Port, ENCODER_B_Pin);
    (void)QuadratureEncoder_OnEdge(&g_encoder, level_a, level_b);
}

/*
 * This is the only position-fault recovery path.  The operator must first
 * place the mechanism at its verified physical neutral position.
 */
uint8_t MotorControlExample_SetZero(void)
{
    QuadratureEncoderSnapshot snapshot;
    uint8_t encoder_valid;

    if (g_initialized != 1U) {
        return 0U;
    }

    force_safe();
    if ((g_telemetry.hal_error != 0U) ||
        (HAL_GPIO_ReadPin(MOTOR_STBY_GPIO_Port,
                          MOTOR_STBY_Pin) != GPIO_PIN_RESET) ||
        (HAL_GPIO_ReadPin(MOTOR_AIN1_GPIO_Port,
                          MOTOR_AIN1_Pin) != GPIO_PIN_RESET) ||
        (HAL_GPIO_ReadPin(MOTOR_AIN2_GPIO_Port,
                          MOTOR_AIN2_Pin) != GPIO_PIN_RESET) ||
        (__HAL_TIM_GET_COMPARE(&htim1, TIM_CHANNEL_1) != 0U)) {
        return 0U;
    }

    memset(&snapshot, 0, sizeof(snapshot));
    encoder_valid = snapshot_encoder(&snapshot);
    publish_encoder_telemetry(&snapshot, encoder_valid);
    if (MotorPositionGuard_SetZero(&g_position_guard, snapshot.count,
                                   encoder_valid, 1U) == 0U) {
        g_telemetry.position_fault = g_position_guard.fault;
        g_telemetry.calibration_required = 1U;
        return 0U;
    }

    g_telemetry.position_fault =
        (uint8_t)MOTOR_POSITION_FAULT_NONE;
    g_telemetry.relative_position_counts = 0;
    g_telemetry.calibration_required = 0U;
    return 1U;
}

static uint8_t mapped_output_is_coherent(
    const MotorCommandOutput *mapped)
{
    if ((mapped == NULL) || (mapped->bridge_enable > 1U) ||
        !isfinite(mapped->duty_fraction)) {
        return 0U;
    }
    if (mapped->bridge_enable == 0U) {
        return (uint8_t)((mapped->direction == 0) &&
                         (mapped->duty_fraction == 0.0));
    }
    return (uint8_t)(
        (mapped->current_fault == (uint8_t)MOTOR_MAPPER_FAULT_NONE) &&
        (mapped->active_inhibit_flags == 0U) &&
        ((mapped->direction == -1) || (mapped->direction == 1)) &&
        (mapped->duty_fraction > 0.0));
}

/*
 * Call once per measured 100 Hz control tick, after SuppressionControl and
 * MotorCommandMapper have produced their outputs.
 *
 * Driver MUST run before the position guard.  During reversal holdoff the
 * driver publishes SAFE/STOP; the guard must see STOP so it does not count
 * dead ticks as commanded motion.
 */
void MotorControlExample_100HzStep(
    uint8_t gate_enabled,
    uint8_t actuation_permitted,
    const MotorCommandOutput *mapped)
{
    Tb6612Output candidate;
    Tb6612Output safe_output;
    Tb6612DriverResult driver_result;
    Tb6612DriverResult safe_result;
    QuadratureEncoderSnapshot snapshot;
    MotorPositionGuardOutput position_output;
    uint8_t encoder_valid;
    uint8_t upstream_active;
    uint8_t candidate_active;
    uint8_t position_allowed;

    memset(&candidate, 0, sizeof(candidate));
    memset(&safe_output, 0, sizeof(safe_output));
    memset(&snapshot, 0, sizeof(snapshot));
    memset(&position_output, 0, sizeof(position_output));

    g_telemetry.gate_enabled = (gate_enabled == 1U) ? 1U : 0U;
    g_telemetry.actuation_permitted =
        (actuation_permitted == 1U) ? 1U : 0U;
    g_telemetry.motor_output_active = 0U;
    g_telemetry.command_direction = 0;
    g_telemetry.command_ccr = 0U;

    if ((g_initialized != 1U) || (g_telemetry.hal_error != 0U) ||
        (gate_enabled > 1U) ||
        (actuation_permitted > 1U) ||
        (mapped_output_is_coherent(mapped) == 0U)) {
        force_safe();
        return;
    }
    if (g_position_guard.zeroed != 1U) {
        g_telemetry.calibration_required = 1U;
        force_safe();
        return;
    }

    upstream_active = (uint8_t)(
        (gate_enabled == 1U) && (actuation_permitted == 1U) &&
        (mapped->bridge_enable == 1U));

    /* An active mapper output while either upstream permission is false is
     * an integration inconsistency and must not be silently energized. */
    if ((mapped->bridge_enable == 1U) && (upstream_active == 0U)) {
        force_safe();
        return;
    }

    driver_result = TB6612Driver_Update(
        &g_driver,
        (upstream_active != 0U) ? mapped->direction : 0,
        (upstream_active != 0U) ? mapped->duty_fraction : 0.0,
        upstream_active,
        &candidate);
    g_telemetry.driver_fault = candidate.fault;
    if (driver_result == TB6612_DRIVER_ERROR) {
        force_safe();
        return;
    }

    /* Strict encoder validity contract required by MotorPositionGuard. */
    encoder_valid = snapshot_encoder(&snapshot);
    publish_encoder_telemetry(&snapshot, encoder_valid);

    candidate_active = (uint8_t)(
        (driver_result == TB6612_DRIVER_ACTIVE) &&
        (candidate.stby == 1U) && (candidate.ccr > 0U));
    position_allowed = MotorPositionGuard_Update(
        &g_position_guard,
        snapshot.count,
        encoder_valid,
        (candidate_active != 0U) ? candidate.direction :
                                  MOTOR_POSITION_DIRECTION_STOP,
        candidate_active,
        &position_output);

    g_telemetry.position_fault = position_output.fault;
    g_telemetry.relative_position_counts =
        position_output.relative_position_counts;
    g_telemetry.calibration_required =
        (position_output.zeroed == 1U) ? 0U : 1U;

    if ((candidate_active != 0U) && (position_allowed != 1U)) {
        /* Guard veto: never send the stale ACTIVE candidate to HAL. */
        safe_result = TB6612Driver_Update(&g_driver, 0, 0.0, 0U,
                                          &safe_output);
        if ((safe_result == TB6612_DRIVER_ERROR) ||
            (STM32_TB6612_HAL_Apply(&g_motor_hal,
                                    &safe_output) != HAL_OK)) {
            g_telemetry.hal_error = 1U;
            force_safe();
        }
        return;
    }
    if ((candidate_active == 0U) && (position_allowed != 0U)) {
        /* The guard must never turn a SAFE driver candidate into ACTIVE. */
        force_safe();
        return;
    }

    if (STM32_TB6612_HAL_Apply(&g_motor_hal, &candidate) != HAL_OK) {
        g_telemetry.hal_error = 1U;
        force_safe();
        return;
    }

    g_telemetry.command_direction = candidate.direction;
    g_telemetry.command_ccr = candidate.ccr;
    g_telemetry.motor_output_active =
        (uint8_t)((candidate_active != 0U) &&
                  (position_allowed == 1U));
}

/* Call immediately on watchdog/scheduler/system inhibit, then ensure the
 * next normal 100 Hz call also carries an upstream inhibit/STOP command. */
void MotorControlExample_ForceSafe(void)
{
    force_safe();
}

const MotorControlExampleTelemetry *
MotorControlExample_GetTelemetry(void)
{
    return &g_telemetry;
}

/* Example callback hook; merge this into the project's existing callback:
 *
 * void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
 * {
 *     MotorControlExample_OnExti(GPIO_Pin);
 *     // Dispatch other EXTI users here.
 * }
 */
