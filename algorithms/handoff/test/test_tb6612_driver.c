#include "tb6612_driver.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>

static Tb6612DriverConfig valid_config(void)
{
    Tb6612DriverConfig config;

    config.pwm_full_scale_ccr = 1000U;
    config.max_duty_fraction = 0.25;
    config.reversal_dead_ticks = 3U;
    config.release_ain1_level = 1U;
    return config;
}

static int output_is_safe(const Tb6612Output *output)
{
    return (output->ccr == 0U) && (output->direction == 0) &&
           (output->ain1 == 0U) && (output->ain2 == 0U) &&
           (output->stby == 0U);
}

static int init_fixture(Tb6612Driver *driver,
                        const Tb6612DriverConfig *config)
{
    Tb6612Output output;

    return (TB6612Driver_Init(driver, config, &output) ==
            TB6612_DRIVER_SAFE) && output_is_safe(&output) &&
           (output.fault == (uint8_t)TB6612_DRIVER_FAULT_NONE);
}

static int test_invalid_config_and_nulls(void)
{
    Tb6612Driver driver;
    Tb6612DriverConfig config = valid_config();
    Tb6612Output output;

    if ((TB6612Driver_ConfigIsValid(NULL) != 0U) ||
        (TB6612Driver_Init(NULL, &config, &output) !=
         TB6612_DRIVER_ERROR) ||
        (TB6612Driver_Init(&driver, &config, NULL) !=
         TB6612_DRIVER_ERROR)) {
        return 0;
    }
    config.pwm_full_scale_ccr = 0U;
    if (init_fixture(&driver, &config)) {
        return 0;
    }
    config = valid_config();
    config.max_duty_fraction = NAN;
    if (init_fixture(&driver, &config)) {
        return 0;
    }
    config = valid_config();
    config.max_duty_fraction = 0.0;
    if (init_fixture(&driver, &config)) {
        return 0;
    }
    config = valid_config();
    config.max_duty_fraction = 1.01;
    if (init_fixture(&driver, &config)) {
        return 0;
    }
    config = valid_config();
    config.pwm_full_scale_ccr = 2U;
    config.max_duty_fraction = 0.25;
    if (init_fixture(&driver, &config)) {
        return 0;
    }
    config = valid_config();
    config.reversal_dead_ticks = 0U;
    if (init_fixture(&driver, &config)) {
        return 0;
    }
    config = valid_config();
    config.release_ain1_level = 2U;
    return !init_fixture(&driver, &config);
}

static int test_direction_mapping_and_ccr(void)
{
    Tb6612Driver driver;
    Tb6612DriverConfig config = valid_config();
    Tb6612Output output;

    if (!init_fixture(&driver, &config)) {
        return 0;
    }
    if ((TB6612Driver_Update(&driver, 1, 0.10, 1U, &output) !=
         TB6612_DRIVER_ACTIVE) || (output.direction != 1) ||
        (output.ain1 != 1U) || (output.ain2 != 0U) ||
        (output.stby != 1U) || (output.ccr != 100U)) {
        return 0;
    }
    if ((TB6612Driver_Update(&driver, 1, 0.250, 1U, &output) !=
         TB6612_DRIVER_ACTIVE) || (output.ccr != 250U)) {
        return 0;
    }

    config.release_ain1_level = 0U;
    if (!init_fixture(&driver, &config)) {
        return 0;
    }
    return (TB6612Driver_Update(&driver, 1, 0.10, 1U, &output) ==
            TB6612_DRIVER_ACTIVE) && (output.ain1 == 0U) &&
           (output.ain2 == 1U);
}

static int test_safe_permission_and_zero_duty(void)
{
    Tb6612Driver driver;
    Tb6612DriverConfig config = valid_config();
    Tb6612Output output;

    if (!init_fixture(&driver, &config)) {
        return 0;
    }
    if ((TB6612Driver_Update(&driver, 0, 0.0, 0U, &output) !=
         TB6612_DRIVER_SAFE) || !output_is_safe(&output)) {
        return 0;
    }
    if ((TB6612Driver_Update(&driver, 1, 0.1, 1U, &output) !=
         TB6612_DRIVER_ACTIVE) ||
        (TB6612Driver_Update(&driver, 1, 0.0, 1U, &output) !=
         TB6612_DRIVER_SAFE) || !output_is_safe(&output)) {
        return 0;
    }
    if ((TB6612Driver_Update(&driver, 0, 0.0, 0U, &output) !=
         TB6612_DRIVER_SAFE) ||
        (TB6612Driver_Update(&driver, 1, 0.1, 1U, &output) !=
         TB6612_DRIVER_ACTIVE)) {
        return 0;
    }
    return (output.direction == 1) && (output.ccr == 100U);
}

static int expect_fault(Tb6612Driver *driver,
                        int8_t direction,
                        double duty,
                        uint8_t permission,
                        Tb6612DriverFault expected,
                        Tb6612Output *output)
{
    return (TB6612Driver_Update(driver, direction, duty, permission,
                                output) == TB6612_DRIVER_ERROR) &&
           output_is_safe(output) &&
           (output->fault == (uint8_t)expected);
}

static int input_fault_latches(const Tb6612DriverConfig *config,
                               int8_t direction,
                               double duty,
                               uint8_t permission,
                               Tb6612DriverFault expected)
{
    Tb6612Driver driver;
    Tb6612Output output;

    if (!init_fixture(&driver, config) ||
        !expect_fault(&driver, direction, duty, permission,
                      expected, &output) ||
        (driver.initialized != 0U)) {
        return 0;
    }
    return expect_fault(&driver, 1, 0.1, 1U,
                        TB6612_DRIVER_FAULT_NOT_INITIALIZED, &output);
}

static int test_invalid_inputs_latch_safe(void)
{
    Tb6612DriverConfig config = valid_config();
    Tb6612Output output;

    if (!input_fault_latches(&config, 1, NAN, 1U,
                             TB6612_DRIVER_FAULT_DUTY) ||
        !input_fault_latches(&config, 1, INFINITY, 1U,
                             TB6612_DRIVER_FAULT_DUTY) ||
        !input_fault_latches(&config, 1, -0.01, 1U,
                             TB6612_DRIVER_FAULT_DUTY) ||
        !input_fault_latches(&config, 1, 0.251, 1U,
                             TB6612_DRIVER_FAULT_DUTY) ||
        !input_fault_latches(&config, 2, 0.1, 1U,
                             TB6612_DRIVER_FAULT_DIRECTION) ||
        !input_fault_latches(&config, 0, 0.1, 1U,
                             TB6612_DRIVER_FAULT_DIRECTION) ||
        !input_fault_latches(&config, 1, 0.1, 2U,
                             TB6612_DRIVER_FAULT_PERMISSION)) {
        return 0;
    }
    return TB6612Driver_Update(NULL, 1, 0.1, 1U, &output) ==
           TB6612_DRIVER_ERROR;
}

static int test_exact_reversal_dead_ticks(void)
{
    Tb6612Driver driver;
    Tb6612DriverConfig config = valid_config();
    Tb6612Output output;
    uint16_t expected_remaining[3] = {2U, 1U, 0U};
    uint32_t i;

    if (!init_fixture(&driver, &config) ||
        (TB6612Driver_Update(&driver, 1, 0.1, 1U, &output) !=
         TB6612_DRIVER_ACTIVE)) {
        return 0;
    }
    for (i = 0U; i < 3U; ++i) {
        if ((TB6612Driver_Update(&driver, -1, 0.1, 1U, &output) !=
             TB6612_DRIVER_SAFE) || !output_is_safe(&output) ||
            (output.reversal_dead_ticks_remaining !=
             expected_remaining[i])) {
            return 0;
        }
    }
    return (TB6612Driver_Update(&driver, -1, 0.1, 1U, &output) ==
            TB6612_DRIVER_ACTIVE) && (output.direction == -1) &&
           (output.ain1 == 0U) && (output.ain2 == 1U) &&
           (output.ccr == 100U);
}

static int test_reversal_cancellation_and_safe_time(void)
{
    Tb6612Driver driver;
    Tb6612DriverConfig config = valid_config();
    Tb6612Output output;

    if (!init_fixture(&driver, &config) ||
        (TB6612Driver_Update(&driver, 1, 0.1, 1U, &output) !=
         TB6612_DRIVER_ACTIVE) ||
        (TB6612Driver_Update(&driver, -1, 0.1, 1U, &output) !=
         TB6612_DRIVER_SAFE) ||
        (output.reversal_dead_ticks_remaining != 2U)) {
        return 0;
    }
    /* A safe permission tick is also real zero-output dead time. */
    if ((TB6612Driver_Update(&driver, 0, 0.0, 0U, &output) !=
         TB6612_DRIVER_SAFE) ||
        (output.reversal_dead_ticks_remaining != 1U)) {
        return 0;
    }
    /* Returning to the previous physical direction cancels the reversal. */
    return (TB6612Driver_Update(&driver, 1, 0.1, 1U, &output) ==
            TB6612_DRIVER_ACTIVE) && (output.direction == 1);
}

static int test_config_and_state_corruption_require_reinit(void)
{
    Tb6612Driver driver;
    Tb6612DriverConfig config = valid_config();
    Tb6612Output output;

    if (!init_fixture(&driver, &config)) {
        return 0;
    }
    driver.config.max_duty_fraction = 0.20;
    if (!expect_fault(&driver, 1, 0.1, 1U,
                      TB6612_DRIVER_FAULT_CONFIG, &output) ||
        (driver.initialized != 0U)) {
        return 0;
    }
    if (!expect_fault(&driver, 1, 0.1, 1U,
                      TB6612_DRIVER_FAULT_NOT_INITIALIZED, &output)) {
        return 0;
    }

    if (!init_fixture(&driver, &config)) {
        return 0;
    }
    /* Coherent-looking public fields still cannot bypass the guard. */
    driver.pending_direction = -1;
    driver.last_energized_direction = 1;
    driver.reversal_dead_ticks_remaining = 1U;
    return expect_fault(&driver, 1, 0.1, 1U,
                        TB6612_DRIVER_FAULT_STATE, &output) &&
           (driver.initialized == 0U);
}

static int test_small_positive_duty_never_becomes_zero_ccr(void)
{
    Tb6612Driver driver;
    Tb6612DriverConfig config = valid_config();
    Tb6612Output output;

    return init_fixture(&driver, &config) &&
           (TB6612Driver_Update(&driver, 1, 0.00001, 1U, &output) ==
            TB6612_DRIVER_ACTIVE) && (output.ccr == 1U) &&
           (output.stby == 1U);
}

static int test_active_ccr_never_exceeds_configured_fraction(void)
{
    Tb6612Driver driver;
    Tb6612DriverConfig config = valid_config();
    Tb6612Output output;
    uint32_t full_scale;

    config.pwm_full_scale_ccr = 3U;
    config.max_duty_fraction = 0.5;
    if (!init_fixture(&driver, &config) ||
        (TB6612Driver_Update(&driver, 1, 0.5, 1U, &output) !=
         TB6612_DRIVER_ACTIVE) ||
        (output.ccr != 1U)) {
        return 0;
    }

    /*
     * Values formed by division are useful boundary probes: their binary64
     * representation may lie immediately below or above the rational value.
     * For these small denominators, long double has enough precision to test
     * the exact binary64 setting times the integer full scale.
     */
    for (full_scale = 1U; full_scale <= 511U; ++full_scale) {
        uint32_t numerator;

        config.pwm_full_scale_ccr = full_scale;
        for (numerator = 1U; numerator <= full_scale; ++numerator) {
            long double configured_limit;

            config.max_duty_fraction =
                (double)numerator / (double)full_scale;
            if (TB6612Driver_ConfigIsValid(&config) == 0U) {
                continue;
            }
            if (!init_fixture(&driver, &config) ||
                (TB6612Driver_Update(
                     &driver, 1, config.max_duty_fraction, 1U,
                     &output) != TB6612_DRIVER_ACTIVE)) {
                return 0;
            }
            configured_limit =
                (long double)config.max_duty_fraction *
                (long double)config.pwm_full_scale_ccr;
            if ((long double)output.ccr > configured_limit) {
                return 0;
            }
        }
    }
    return 1;
}

static int test_deterministic_output_invariant_soak(void)
{
    Tb6612Driver driver;
    Tb6612DriverConfig config = valid_config();
    Tb6612Output output;
    uint32_t active_count = 0U;
    uint32_t safe_count = 0U;
    uint32_t error_count = 0U;
    uint32_t i;

    if (!init_fixture(&driver, &config)) {
        return 0;
    }
    for (i = 0U; i < 250000U; ++i) {
        int8_t direction = ((i / 37U) & 1U) ? -1 : 1;
        uint8_t permission = (uint8_t)(((i % 97U) == 0U) ? 0U : 1U);
        double duty = (double)(i % 251U) / 1000.0;
        Tb6612DriverResult result;

        if ((i != 0U) && ((i % 65537U) == 0U)) {
            duty = NAN;
        }
        result = TB6612Driver_Update(&driver, direction, duty,
                                     permission, &output);
        if (result == TB6612_DRIVER_ACTIVE) {
            if ((output.fault !=
                 (uint8_t)TB6612_DRIVER_FAULT_NONE) ||
                (output.stby != 1U) ||
                ((output.direction != -1) &&
                 (output.direction != 1)) ||
                (output.ain1 == output.ain2) ||
                (output.ccr == 0U) || (output.ccr > 250U) ||
                (output.reversal_dead_ticks_remaining != 0U)) {
                return 0;
            }
            active_count++;
        } else {
            if (!output_is_safe(&output)) {
                return 0;
            }
            if (result == TB6612_DRIVER_SAFE) {
                safe_count++;
            } else if ((result == TB6612_DRIVER_ERROR) &&
                       (output.fault ==
                        (uint8_t)TB6612_DRIVER_FAULT_DUTY)) {
                error_count++;
                if ((driver.initialized != 0U) ||
                    !init_fixture(&driver, &config)) {
                    return 0;
                }
            } else {
                return 0;
            }
        }
    }
    return (active_count > 100000U) && (safe_count > 1000U) &&
           (error_count == 3U);
}

int main(void)
{
    int pass = 1;

    pass &= test_invalid_config_and_nulls();
    pass &= test_direction_mapping_and_ccr();
    pass &= test_safe_permission_and_zero_duty();
    pass &= test_invalid_inputs_latch_safe();
    pass &= test_exact_reversal_dead_ticks();
    pass &= test_reversal_cancellation_and_safe_time();
    pass &= test_config_and_state_corruption_require_reinit();
    pass &= test_small_positive_duty_never_becomes_zero_ccr();
    pass &= test_active_ccr_never_exceeds_configured_fraction();
    pass &= test_deterministic_output_invariant_soak();

    printf("TB6612 pure command driver: %s\n", pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}
