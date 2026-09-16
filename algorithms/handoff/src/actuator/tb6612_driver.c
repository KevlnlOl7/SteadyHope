#include "tb6612_driver.h"

#include <float.h>
#include <math.h>
#include <stddef.h>
#include <string.h>

_Static_assert(sizeof(double) == sizeof(uint64_t),
               "TB6612Driver requires 64-bit double");
_Static_assert(FLT_RADIX == 2,
               "TB6612Driver requires binary floating point");
_Static_assert(DBL_MANT_DIG == 53,
               "TB6612Driver requires IEEE-754 binary64 double");

/*
 * Return floor(max_duty_fraction * pwm_full_scale_ccr) exactly for the
 * represented binary64 configuration value.  A plain double multiplication
 * can round a value just below an integer up to that integer, so it is not a
 * sufficiently strong safety cap.
 *
 * The accepted duty range guarantees a positive normal double no smaller
 * than 1 / UINT32_MAX.  Its 53-bit significand times a 32-bit full scale is
 * accumulated as an explicit 96-bit value before the binary right shift.
 */
static uint32_t maximum_permitted_ccr(
    const Tb6612DriverConfig *config)
{
    const uint64_t fraction_mask = UINT64_C(0x000FFFFFFFFFFFFF);
    uint64_t duty_bits;
    uint64_t significand;
    uint64_t significand_low;
    uint64_t significand_high;
    uint64_t low_product;
    uint64_t high_product;
    uint64_t product_low;
    uint64_t product_high;
    uint64_t quotient;
    uint32_t exponent_bits;
    uint32_t right_shift;

    if ((config == NULL) ||
        !isfinite(config->max_duty_fraction) ||
        (config->max_duty_fraction <= 0.0) ||
        (config->max_duty_fraction > 1.0) ||
        (config->pwm_full_scale_ccr == 0U)) {
        return 0U;
    }

    memcpy(&duty_bits, &config->max_duty_fraction,
           sizeof(duty_bits));
    exponent_bits = (uint32_t)((duty_bits >> 52U) & UINT64_C(0x7FF));
    if ((exponent_bits == 0U) || (exponent_bits > 1023U)) {
        return 0U;
    }
    significand = (duty_bits & fraction_mask) | (UINT64_C(1) << 52U);
    right_shift = 52U + (1023U - exponent_bits);

    significand_low = significand & UINT64_C(0xFFFFFFFF);
    significand_high = significand >> 32U;
    low_product = significand_low *
                  (uint64_t)config->pwm_full_scale_ccr;
    high_product = significand_high *
                   (uint64_t)config->pwm_full_scale_ccr;
    product_low = low_product + (high_product << 32U);
    product_high = (high_product >> 32U) +
                   (uint64_t)(product_low < low_product);

    if (right_shift < 64U) {
        quotient = (product_low >> right_shift) |
                   (product_high << (64U - right_shift));
    } else if (right_shift == 64U) {
        quotient = product_high;
    } else if (right_shift < 128U) {
        quotient = product_high >> (right_shift - 64U);
    } else {
        quotient = 0U;
    }
    if (quotient > UINT32_MAX) {
        return UINT32_MAX;
    }
    return (uint32_t)quotient;
}

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
    if (config == NULL) {
        return 0U;
    }
    if (!isfinite(config->max_duty_fraction) ||
        (config->pwm_full_scale_ccr == 0U) ||
        (config->max_duty_fraction <= 0.0) ||
        (config->max_duty_fraction > 1.0) ||
        (maximum_permitted_ccr(config) == 0U) ||
        (config->reversal_dead_ticks == 0U) ||
        (config->release_ain1_level > 1U)) {
        return 0U;
    }
    return 1U;
}

static uint64_t state_snapshot(const Tb6612Driver *driver)
{
    return (uint64_t)driver->reversal_dead_ticks_remaining |
           ((uint64_t)driver->safe_ticks_since_energized << 16U) |
           ((uint64_t)(uint8_t)driver->last_energized_direction << 32U) |
           ((uint64_t)(uint8_t)driver->pending_direction << 40U) |
           ((uint64_t)driver->initialized << 48U) |
           ((uint64_t)driver->current_fault << 56U);
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
        (driver->safe_ticks_since_energized >
         driver->config.reversal_dead_ticks) ||
        (driver->current_fault > (uint8_t)TB6612_DRIVER_FAULT_STATE)) {
        return 0U;
    }
    if (driver->last_energized_direction == 0) {
        return (uint8_t)(
            (driver->pending_direction == 0) &&
            (driver->reversal_dead_ticks_remaining == 0U) &&
            (driver->safe_ticks_since_energized == 0U) &&
            (runtime_guard_matches(driver) != 0U));
    }
    if (driver->pending_direction == 0) {
        return (uint8_t)(
            (driver->reversal_dead_ticks_remaining == 0U) &&
            (runtime_guard_matches(driver) != 0U));
    }
    return (uint8_t)(
        (driver->pending_direction ==
         -driver->last_energized_direction) &&
        (driver->safe_ticks_since_energized > 0U) &&
        (driver->reversal_dead_ticks_remaining ==
         (uint16_t)(driver->config.reversal_dead_ticks -
                    driver->safe_ticks_since_energized)) &&
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
            driver->safe_ticks_since_energized = 0U;
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
    uint32_t maximum_ccr = maximum_permitted_ccr(&driver->config);

    if (scaled >= (double)maximum_ccr) {
        return maximum_ccr;
    }
    rounded = scaled + 0.5;
    if (rounded >= (double)maximum_ccr) {
        return maximum_ccr;
    }
    ccr = (uint32_t)rounded;
    return (ccr == 0U) ? 1U : ccr;
}

/*
 * Record one tick for which the driver actually emits its SAFE output.
 * The count saturates at the configured reversal requirement because older
 * safe time cannot make a later reversal any safer than "requirement met".
 */
static void record_safe_tick(Tb6612Driver *driver)
{
    if ((driver->last_energized_direction != 0) &&
        (driver->safe_ticks_since_energized <
         driver->config.reversal_dead_ticks)) {
        driver->safe_ticks_since_energized++;
    }
    if (driver->pending_direction != 0) {
        driver->reversal_dead_ticks_remaining =
            (uint16_t)(driver->config.reversal_dead_ticks -
                       driver->safe_ticks_since_energized);
    } else {
        driver->reversal_dead_ticks_remaining = 0U;
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
        record_safe_tick(driver);
        driver->current_fault = (uint8_t)TB6612_DRIVER_FAULT_NONE;
        refresh_runtime_guard(driver);
        safe_output(output, TB6612_DRIVER_FAULT_NONE,
                    driver->reversal_dead_ticks_remaining);
        return TB6612_DRIVER_SAFE;
    }

    if ((driver->last_energized_direction != 0) &&
        (direction != driver->last_energized_direction)) {
        if (driver->safe_ticks_since_energized <
            driver->config.reversal_dead_ticks) {
            driver->pending_direction = direction;
            record_safe_tick(driver);
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
    driver->safe_ticks_since_energized = 0U;
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
