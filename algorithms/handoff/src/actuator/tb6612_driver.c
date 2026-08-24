#include "tb6612_driver.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

_Static_assert(sizeof(double) == sizeof(uint64_t),
               "TB6612Driver requires 64-bit double");

static void safe_output(Tb6612Output *output,
                        Tb6612DriverFault fault,
                        uint16_t dead_ticks_remaining)
{
    if (output == NULL) {
        return;
    }
    memset(output, 0, sizeof(*output));
    output->fault = (uint8_t)fault;
    output->reversal_dead_ticks_remaining = dead_ticks_remaining;
}

static uint8_t config_equal(const Tb6612DriverConfig *left,
                            const Tb6612DriverConfig *right)
{
    uint64_t left_duty_bits;
    uint64_t right_duty_bits;

    memcpy(&left_duty_bits, &left->max_duty_fraction,
           sizeof(left_duty_bits));
    memcpy(&right_duty_bits, &right->max_duty_fraction,
           sizeof(right_duty_bits));
    return (uint8_t)(
        (left->pwm_full_scale_ccr == right->pwm_full_scale_ccr) &&
        (left_duty_bits == right_duty_bits) &&
        (left->reversal_dead_ticks == right->reversal_dead_ticks) &&
        (left->release_ain1_level == right->release_ain1_level));
}

uint8_t TB6612Driver_ConfigIsValid(const Tb6612DriverConfig *config)
{
    double maximum_ccr;

    if (config == NULL) {
        return 0U;
    }
    maximum_ccr = config->max_duty_fraction *
                  (double)config->pwm_full_scale_ccr;
    if (!isfinite(config->max_duty_fraction) ||
        !isfinite(maximum_ccr) ||
        (config->pwm_full_scale_ccr == 0U) ||
        (config->max_duty_fraction <= 0.0) ||
        (config->max_duty_fraction > 1.0) ||
        (maximum_ccr < 1.0) ||
        (config->reversal_dead_ticks == 0U) ||
        (config->release_ain1_level > 1U)) {
        return 0U;
    }
    return 1U;
}

static uint64_t state_snapshot(const Tb6612Driver *driver)
{
    return (uint64_t)driver->reversal_dead_ticks_remaining |
           ((uint64_t)(uint8_t)driver->last_energized_direction << 16U) |
           ((uint64_t)(uint8_t)driver->pending_direction << 24U) |
           ((uint64_t)driver->initialized << 32U) |
           ((uint64_t)driver->current_fault << 40U);
}

static void refresh_runtime_guard(Tb6612Driver *driver)
{
    uint64_t snapshot = state_snapshot(driver);

    driver->runtime_guard[0] = snapshot;
    driver->runtime_guard[1] =
        (~snapshot) ^ UINT64_C(0xA59C3F0876D21BE4);
}

static uint8_t runtime_guard_matches(const Tb6612Driver *driver)
{
    uint64_t snapshot = state_snapshot(driver);

    return (uint8_t)(
        (driver->runtime_guard[0] == snapshot) &&
        (driver->runtime_guard[1] ==
         ((~snapshot) ^ UINT64_C(0xA59C3F0876D21BE4))));
}

static uint8_t state_is_valid(const Tb6612Driver *driver)
{
    if (((driver->last_energized_direction != -1) &&
         (driver->last_energized_direction != 0) &&
         (driver->last_energized_direction != 1)) ||
        ((driver->pending_direction != -1) &&
         (driver->pending_direction != 0) &&
         (driver->pending_direction != 1)) ||
        (driver->reversal_dead_ticks_remaining >
         driver->config.reversal_dead_ticks) ||
        (driver->current_fault > (uint8_t)TB6612_DRIVER_FAULT_STATE)) {
        return 0U;
    }
    if (driver->pending_direction == 0) {
        return (uint8_t)(
            (driver->reversal_dead_ticks_remaining == 0U) &&
            (runtime_guard_matches(driver) != 0U));
    }
    return (uint8_t)(
        (driver->last_energized_direction != 0) &&
        (driver->pending_direction ==
         -driver->last_energized_direction) &&
        (runtime_guard_matches(driver) != 0U));
}

static Tb6612DriverResult fail_closed(Tb6612Driver *driver,
                                      Tb6612Output *output,
                                      Tb6612DriverFault fault,
                                      uint8_t require_reinit)
{
    uint16_t remaining = 0U;

    if (driver != NULL) {
        driver->current_fault = (uint8_t)fault;
        if (require_reinit != 0U) {
            driver->initialized = 0U;
            driver->last_energized_direction = 0;
            driver->pending_direction = 0;
            driver->reversal_dead_ticks_remaining = 0U;
        } else {
            remaining = driver->reversal_dead_ticks_remaining;
        }
        refresh_runtime_guard(driver);
    }
    safe_output(output, fault, remaining);
    return TB6612_DRIVER_ERROR;
}

Tb6612DriverResult TB6612Driver_Init(
    Tb6612Driver *driver,
    const Tb6612DriverConfig *config,
    Tb6612Output *output)
{
    safe_output(output, TB6612_DRIVER_FAULT_CONFIG, 0U);
    if ((driver == NULL) || (output == NULL)) {
        return TB6612_DRIVER_ERROR;
    }
    memset(driver, 0, sizeof(*driver));
    if (TB6612Driver_ConfigIsValid(config) == 0U) {
        driver->current_fault = (uint8_t)TB6612_DRIVER_FAULT_CONFIG;
        refresh_runtime_guard(driver);
        return TB6612_DRIVER_ERROR;
    }
    driver->config = *config;
    driver->initialized_config = *config;
    driver->initialized = 1U;
    driver->current_fault = (uint8_t)TB6612_DRIVER_FAULT_NONE;
    refresh_runtime_guard(driver);
    safe_output(output, TB6612_DRIVER_FAULT_NONE, 0U);
    return TB6612_DRIVER_SAFE;
}

static uint32_t duty_to_ccr(const Tb6612Driver *driver,
                            double duty_fraction)
{
    double scaled = duty_fraction *
                    (double)driver->config.pwm_full_scale_ccr;
    double rounded;
    uint32_t ccr;

    if (scaled >= (double)driver->config.pwm_full_scale_ccr) {
        return driver->config.pwm_full_scale_ccr;
    }
    rounded = scaled + 0.5;
    if (rounded >= (double)driver->config.pwm_full_scale_ccr) {
        return driver->config.pwm_full_scale_ccr;
    }
    ccr = (uint32_t)rounded;
    return (ccr == 0U) ? 1U : ccr;
}

static void advance_existing_dead_time(Tb6612Driver *driver)
{
    if (driver->reversal_dead_ticks_remaining > 0U) {
        driver->reversal_dead_ticks_remaining--;
    }
}

Tb6612DriverResult TB6612Driver_Update(
    Tb6612Driver *driver,
    int8_t direction,
    double duty_fraction,
    uint8_t permission,
    Tb6612Output *output)
{
    uint8_t release_ain1;
    uint32_t ccr;

    safe_output(output, TB6612_DRIVER_FAULT_NOT_INITIALIZED, 0U);
    if ((driver == NULL) || (output == NULL)) {
        return TB6612_DRIVER_ERROR;
    }
    if (driver->initialized != 1U) {
        return fail_closed(driver, output,
                           TB6612_DRIVER_FAULT_NOT_INITIALIZED, 1U);
    }
    if ((TB6612Driver_ConfigIsValid(&driver->config) == 0U) ||
        (config_equal(&driver->config,
                      &driver->initialized_config) == 0U)) {
        return fail_closed(driver, output, TB6612_DRIVER_FAULT_CONFIG, 1U);
    }
    if (state_is_valid(driver) == 0U) {
        return fail_closed(driver, output, TB6612_DRIVER_FAULT_STATE, 1U);
    }
    if (permission > 1U) {
        return fail_closed(driver, output,
                           TB6612_DRIVER_FAULT_PERMISSION, 1U);
    }
    if (!isfinite(duty_fraction) || (duty_fraction < 0.0) ||
        (duty_fraction > driver->config.max_duty_fraction)) {
        return fail_closed(driver, output,
                           TB6612_DRIVER_FAULT_DUTY, 1U);
    }
    if ((direction != -1) && (direction != 0) && (direction != 1)) {
        return fail_closed(driver, output,
                           TB6612_DRIVER_FAULT_DIRECTION, 1U);
    }
    if ((permission == 1U) && (direction == 0)) {
        return fail_closed(driver, output,
                           TB6612_DRIVER_FAULT_DIRECTION, 1U);
    }

    if ((permission == 0U) || (duty_fraction == 0.0)) {
        advance_existing_dead_time(driver);
        driver->current_fault = (uint8_t)TB6612_DRIVER_FAULT_NONE;
        refresh_runtime_guard(driver);
        safe_output(output, TB6612_DRIVER_FAULT_NONE,
                    driver->reversal_dead_ticks_remaining);
        return TB6612_DRIVER_SAFE;
    }

    if ((driver->last_energized_direction != 0) &&
        (direction != driver->last_energized_direction)) {
        if (driver->pending_direction != direction) {
            driver->pending_direction = direction;
            driver->reversal_dead_ticks_remaining =
                driver->config.reversal_dead_ticks;
        }
        if (driver->reversal_dead_ticks_remaining > 0U) {
            driver->reversal_dead_ticks_remaining--;
            driver->current_fault = (uint8_t)TB6612_DRIVER_FAULT_NONE;
            refresh_runtime_guard(driver);
            safe_output(output, TB6612_DRIVER_FAULT_NONE,
                        driver->reversal_dead_ticks_remaining);
            return TB6612_DRIVER_SAFE;
        }
    } else {
        driver->pending_direction = 0;
        driver->reversal_dead_ticks_remaining = 0U;
    }

    ccr = duty_to_ccr(driver, duty_fraction);
    if ((ccr == 0U) ||
        (ccr > driver->config.pwm_full_scale_ccr)) {
        return fail_closed(driver, output, TB6612_DRIVER_FAULT_STATE, 1U);
    }

    driver->last_energized_direction = direction;
    driver->pending_direction = 0;
    driver->reversal_dead_ticks_remaining = 0U;
    driver->current_fault = (uint8_t)TB6612_DRIVER_FAULT_NONE;
    refresh_runtime_guard(driver);

    release_ain1 = driver->config.release_ain1_level;
    output->ccr = ccr;
    output->direction = direction;
    output->ain1 = (direction == 1) ? release_ain1 :
                                      (uint8_t)(1U - release_ain1);
    output->ain2 = (uint8_t)(1U - output->ain1);
    output->stby = 1U;
    output->fault = (uint8_t)TB6612_DRIVER_FAULT_NONE;
    output->reversal_dead_ticks_remaining = 0U;
    return TB6612_DRIVER_ACTIVE;
}
