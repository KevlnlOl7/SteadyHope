#include "motor_command_mapper.h"
#include "tb6612_driver.h"

#include <stdint.h>
#include <stdio.h>

/* All values in this file are host-test fixtures, not motor settings. */
static MotorCommandMapperConfig mapper_fixture(void)
{
    MotorCommandMapperConfig config;

    config.deadband_dps = 0.0;
    config.gain_duty_fraction_per_dps = 0.02;
    config.max_duty_fraction = 0.25;
    config.max_duty_step_per_tick = 0.04;
    config.max_abs_request_dps = 100.0;
    config.reversal_dead_ticks = 2U;
    config.direction_polarity = 1;
    return config;
}

static Tb6612DriverConfig driver_fixture(void)
{
    Tb6612DriverConfig config;

    config.pwm_full_scale_ccr = 1000U;
    config.max_duty_fraction = 0.25;
    config.reversal_dead_ticks = 2U;
    config.release_ain1_level = 1U;
    return config;
}

static int output_is_safe(const Tb6612Output *output)
{
    return (output->ccr == 0U) && (output->direction == 0) &&
           (output->ain1 == 0U) && (output->ain2 == 0U) &&
           (output->stby == 0U);
}

static int init_chain(MotorCommandMapper *mapper,
                      Tb6612Driver *driver,
                      const MotorCommandMapperConfig *mapper_config,
                      const Tb6612DriverConfig *driver_config)
{
    Tb6612Output output;

    return (MotorCommandMapper_Init(
                mapper, mapper_config, mapper_config) != 0U) &&
           (TB6612Driver_Init(driver, driver_config, &output) ==
            TB6612_DRIVER_SAFE) && output_is_safe(&output);
}

static Tb6612DriverResult chain_step(
    MotorCommandMapper *mapper,
    Tb6612Driver *driver,
    double request_dps,
    MotorCommandOutput *mapped,
    Tb6612Output *physical)
{
    (void)MotorCommandMapper_Update(
        mapper, request_dps, 1U, 0U, 0U, mapped);
    return TB6612Driver_Update(
        driver, mapped->direction, mapped->duty_fraction,
        mapped->bridge_enable, physical);
}

/*
 * Exercise alternating square-wave requests whose half-cycle lengths are
 * the 100 Hz discrete-time representations of 4 Hz (13/12 ticks), 5 Hz
 * (10/10), and 6 Hz (8/9/8/8/9/8).  This is a state-machine trace, not a
 * motor-performance claim.
 */
static int test_4_5_6_hz_reversal_trace(void)
{
    static const uint8_t half_cycle_ticks[] = {
        13U, 12U, 13U, 12U,
        10U, 10U, 10U, 10U,
        8U, 9U, 8U, 8U, 9U, 8U
    };
    MotorCommandMapper mapper;
    Tb6612Driver driver;
    MotorCommandMapperConfig mapper_config = mapper_fixture();
    Tb6612DriverConfig driver_config = driver_fixture();
    MotorCommandOutput mapped;
    Tb6612Output physical;
    uint32_t safe_ticks_since_active = 0U;
    uint32_t plus_to_minus_gap = UINT32_MAX;
    uint32_t minus_to_plus_gap = UINT32_MAX;
    uint32_t plus_to_minus_count = 0U;
    uint32_t minus_to_plus_count = 0U;
    uint32_t driver_added_safe_ticks = 0U;
    uint32_t segment;
    int8_t last_physical_direction = 0;

    if (!init_chain(&mapper, &driver, &mapper_config, &driver_config)) {
        return 0;
    }

    for (segment = 0U;
         segment < (uint32_t)(sizeof(half_cycle_ticks) /
                              sizeof(half_cycle_ticks[0]));
         ++segment) {
        int8_t request_direction = ((segment & 1U) == 0U) ? 1 : -1;
        uint32_t tick;

        for (tick = 0U; tick < half_cycle_ticks[segment]; ++tick) {
            Tb6612DriverResult result = chain_step(
                &mapper, &driver, 20.0 * (double)request_direction,
                &mapped, &physical);

            if (result == TB6612_DRIVER_ERROR) {
                return 0;
            }
            if (result == TB6612_DRIVER_SAFE) {
                if (!output_is_safe(&physical)) {
                    return 0;
                }
                safe_ticks_since_active++;
                if (mapped.bridge_enable != 0U) {
                    driver_added_safe_ticks++;
                }
                continue;
            }

            if ((mapped.bridge_enable != 1U) ||
                (physical.direction != mapped.direction) ||
                (physical.direction != request_direction) ||
                (physical.ccr == 0U)) {
                return 0;
            }
            if ((last_physical_direction != 0) &&
                (physical.direction != last_physical_direction)) {
                uint32_t expected_mapper_safe_ticks =
                    (uint32_t)mapper_config.reversal_dead_ticks + 1U;

                if ((safe_ticks_since_active <
                     driver_config.reversal_dead_ticks) ||
                    (safe_ticks_since_active !=
                     expected_mapper_safe_ticks) ||
                    (mapped.duty_fraction >
                     mapper_config.max_duty_step_per_tick)) {
                    return 0;
                }
                if (last_physical_direction == 1) {
                    if ((plus_to_minus_gap != UINT32_MAX) &&
                        (plus_to_minus_gap != safe_ticks_since_active)) {
                        return 0;
                    }
                    plus_to_minus_gap = safe_ticks_since_active;
                    plus_to_minus_count++;
                } else {
                    if ((minus_to_plus_gap != UINT32_MAX) &&
                        (minus_to_plus_gap != safe_ticks_since_active)) {
                        return 0;
                    }
                    minus_to_plus_gap = safe_ticks_since_active;
                    minus_to_plus_count++;
                }
            } else if (safe_ticks_since_active != 0U) {
                return 0;
            }
            safe_ticks_since_active = 0U;
            last_physical_direction = physical.direction;
        }
    }

    return (driver_added_safe_ticks == 0U) &&
           (plus_to_minus_count >= 5U) &&
           (minus_to_plus_count >= 5U) &&
           (plus_to_minus_gap == minus_to_plus_gap) &&
           (plus_to_minus_gap ==
            (uint32_t)mapper_config.reversal_dead_ticks + 1U);
}

static int test_safe_credit_saturates_and_is_guarded(void)
{
    Tb6612Driver driver;
    Tb6612DriverConfig config = driver_fixture();
    Tb6612Output output;
    uint32_t tick;

    if ((TB6612Driver_Init(&driver, &config, &output) !=
         TB6612_DRIVER_SAFE) ||
        (TB6612Driver_Update(&driver, 1, 0.1, 1U, &output) !=
         TB6612_DRIVER_ACTIVE)) {
        return 0;
    }
    for (tick = 0U; tick < 100U; ++tick) {
        if ((TB6612Driver_Update(&driver, 0, 0.0, 0U, &output) !=
             TB6612_DRIVER_SAFE) || !output_is_safe(&output)) {
            return 0;
        }
    }
    if ((driver.safe_ticks_since_energized !=
         config.reversal_dead_ticks) ||
        (TB6612Driver_Update(&driver, -1, 0.1, 1U, &output) !=
         TB6612_DRIVER_ACTIVE) || (output.direction != -1) ||
        (driver.safe_ticks_since_energized != 0U)) {
        return 0;
    }

    /* A public-state edit must be detected even if its value looks valid. */
    if (TB6612Driver_Update(&driver, 0, 0.0, 0U, &output) !=
        TB6612_DRIVER_SAFE) {
        return 0;
    }
    driver.safe_ticks_since_energized++;
    return (TB6612Driver_Update(&driver, -1, 0.1, 1U, &output) ==
            TB6612_DRIVER_ERROR) && output_is_safe(&output) &&
           (output.fault == (uint8_t)TB6612_DRIVER_FAULT_STATE) &&
           (driver.initialized == 0U);
}

static int test_partial_safe_credit_only_supplements_missing_ticks(void)
{
    Tb6612Driver driver;
    Tb6612DriverConfig config = driver_fixture();
    Tb6612Output output;

    config.reversal_dead_ticks = 4U;
    if ((TB6612Driver_Init(&driver, &config, &output) !=
         TB6612_DRIVER_SAFE) ||
        (TB6612Driver_Update(&driver, 1, 0.1, 1U, &output) !=
         TB6612_DRIVER_ACTIVE)) {
        return 0;
    }

    /* Two upstream SAFE ticks satisfy half of the physical requirement. */
    if ((TB6612Driver_Update(&driver, 0, 0.0, 0U, &output) !=
         TB6612_DRIVER_SAFE) ||
        (TB6612Driver_Update(&driver, 0, 0.0, 0U, &output) !=
         TB6612_DRIVER_SAFE) ||
        (driver.safe_ticks_since_energized != 2U)) {
        return 0;
    }

    /* The driver supplies exactly the two missing ticks, not four more. */
    if ((TB6612Driver_Update(&driver, -1, 0.1, 1U, &output) !=
         TB6612_DRIVER_SAFE) ||
        (output.reversal_dead_ticks_remaining != 1U) ||
        (TB6612Driver_Update(&driver, -1, 0.1, 1U, &output) !=
         TB6612_DRIVER_SAFE) ||
        (output.reversal_dead_ticks_remaining != 0U)) {
        return 0;
    }
    return (TB6612Driver_Update(&driver, -1, 0.1, 1U, &output) ==
            TB6612_DRIVER_ACTIVE) && (output.direction == -1);
}

int main(void)
{
    int pass = 1;

    pass &= test_4_5_6_hz_reversal_trace();
    pass &= test_safe_credit_saturates_and_is_guarded();
    pass &= test_partial_safe_credit_only_supplements_missing_ticks();

    printf("mapper -> TB6612 full-chain reversal trace: %s\n",
           pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}
