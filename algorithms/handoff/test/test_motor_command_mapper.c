#include "motor_command_mapper.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>

#define MAPPER_SOAK_TICKS 1000000U

static MotorCommandMapperConfig valid_config(void)
{
    MotorCommandMapperConfig config;

    config.deadband_dps = 1.0;
    config.gain_duty_fraction_per_dps = 0.05;
    config.max_duty_fraction = 0.30;
    config.max_duty_step_per_tick = 0.05;
    config.max_abs_request_dps = 100.0;
    config.reversal_dead_ticks = 2U;
    config.direction_polarity = 1;
    return config;
}

static uint8_t init_fixture_mapper(
    MotorCommandMapper *mapper, const MotorCommandMapperConfig *config)
{
    return MotorCommandMapper_Init(mapper, config, config);
}

static int output_is_safe(const MotorCommandOutput *output)
{
    return isfinite(output->duty_fraction) &&
           (output->duty_fraction == 0.0) &&
           (output->direction == 0) && (output->bridge_enable == 0U);
}

static int test_invalid_configs(void)
{
    MotorCommandMapper mapper;
    MotorCommandMapperConfig config = valid_config();

    if ((MotorCommandMapper_ConfigIsValid(NULL) != 0U) ||
        (MotorCommandMapper_Init(&mapper, NULL, NULL) != 0U)) {
        return 0;
    }
    {
        MotorCommandMapperConfig other = config;
        other.max_duty_fraction = 0.31;
        if (MotorCommandMapper_Init(&mapper, &config, &other) != 0U) {
            return 0;
        }
    }
    config.deadband_dps = NAN;
    if (init_fixture_mapper(&mapper, &config) != 0U) {
        return 0;
    }
    config = valid_config();
    config.gain_duty_fraction_per_dps = 0.0;
    if (init_fixture_mapper(&mapper, &config) != 0U) {
        return 0;
    }
    config = valid_config();
    config.max_duty_fraction = 1.01;
    if (init_fixture_mapper(&mapper, &config) != 0U) {
        return 0;
    }
    config = valid_config();
    config.max_duty_step_per_tick = -0.1;
    if (init_fixture_mapper(&mapper, &config) != 0U) {
        return 0;
    }
    config = valid_config();
    config.max_abs_request_dps = INFINITY;
    if (init_fixture_mapper(&mapper, &config) != 0U) {
        return 0;
    }
    config = valid_config();
    config.reversal_dead_ticks = 0U;
    if (init_fixture_mapper(&mapper, &config) != 0U) {
        return 0;
    }
    config = valid_config();
    config.direction_polarity = 0;
    return init_fixture_mapper(&mapper, &config) == 0U;
}

static int test_config_fingerprint_collision_does_not_authorize(void)
{
    MotorCommandMapper mapper;
    MotorCommandMapperConfig config_a = {
        97.8, 0.021, 0.9, 0.053, 106.0, 78U, -1
    };
    MotorCommandMapperConfig config_b = {
        25.5, 0.086, 0.98, 0.048, 61.0, 90U, -1
    };

    if ((MotorCommandMapper_ConfigIsValid(&config_a) == 0U) ||
        (MotorCommandMapper_ConfigIsValid(&config_b) == 0U) ||
        (MotorCommandMapper_ConfigFingerprint(&config_a) !=
         MotorCommandMapper_ConfigFingerprint(&config_b))) {
        return 0;
    }
    return MotorCommandMapper_Init(&mapper, &config_a, &config_b) == 0U;
}

static int test_mapping_saturation_and_safe_stop(void)
{
    MotorCommandMapper mapper;
    MotorCommandMapperConfig config = valid_config();
    MotorCommandOutput output;

    if (init_fixture_mapper(&mapper, &config) == 0U) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, 5.0, 1U, 0U, 0U,
                                   &output) == 0U) ||
        (fabs(output.duty_fraction - 0.05) > 1.0e-12) ||
        (output.direction != 1) || (output.bridge_enable == 0U)) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, 99.0, 1U, 0U, 0U,
                                   &output) == 0U) ||
        (fabs(output.duty_fraction - 0.10) > 1.0e-12)) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, 99.0, 1U, 0U, 0U,
                                   &output) == 0U) ||
        (fabs(output.duty_fraction - 0.15) > 1.0e-12)) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, 99.0, 0U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safe(&output)) {
        return 0;
    }
    return (MotorCommandMapper_Update(&mapper, 0.5, 1U, 0U, 0U,
                                      &output) == 0U) &&
           output_is_safe(&output);
}

static int test_faults_config_mutation_and_inhibit(void)
{
    MotorCommandMapper mapper;
    MotorCommandMapperConfig config = valid_config();
    MotorCommandOutput output;

    if (init_fixture_mapper(&mapper, &config) == 0U) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, NAN, 1U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safe(&output) ||
        (output.current_fault != (uint8_t)MOTOR_MAPPER_FAULT_INPUT)) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, 10.0, 1U, 1U, 0U,
                                   &output) != 0U) ||
        !output_is_safe(&output) ||
        (output.current_fault != (uint8_t)MOTOR_MAPPER_FAULT_DRIVER)) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, 10.0, 1U, 0U, 0x80000000U,
                                   &output) != 0U) ||
        !output_is_safe(&output) ||
        (output.active_inhibit_flags != 0x80000000U) ||
        (output.current_fault != (uint8_t)MOTOR_MAPPER_FAULT_INHIBIT)) {
        return 0;
    }
    mapper.config.max_duty_fraction = 2.0;
    if ((MotorCommandMapper_Update(&mapper, 10.0, 1U, 0U, 0U,
                                   &output) != 0U) ||
        (mapper.initialized != 0U) || !output_is_safe(&output) ||
        (output.current_fault != (uint8_t)MOTOR_MAPPER_FAULT_CONFIG)) {
        return 0;
    }
    mapper.config = config;
    return (MotorCommandMapper_Update(&mapper, 10.0, 1U, 0U, 0U,
                                      &output) == 0U) &&
           (output.current_fault ==
            (uint8_t)MOTOR_MAPPER_FAULT_NOT_INITIALIZED);
}

static int test_reversal_deadtime(void)
{
    MotorCommandMapper mapper;
    MotorCommandMapperConfig config = valid_config();
    MotorCommandOutput output;

    if (init_fixture_mapper(&mapper, &config) == 0U) {
        return 0;
    }
    if (MotorCommandMapper_Update(&mapper, 10.0, 1U, 0U, 0U,
                                  &output) == 0U) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, -10.0, 1U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safe(&output) || (output.dead_ticks_remaining != 2U)) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, -10.0, 1U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safe(&output) || (output.dead_ticks_remaining != 1U)) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, -10.0, 1U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safe(&output) || (output.dead_ticks_remaining != 0U)) {
        return 0;
    }
    return (MotorCommandMapper_Update(&mapper, -10.0, 1U, 0U, 0U,
                                      &output) != 0U) &&
           (output.direction == -1) && (output.bridge_enable != 0U);
}

static int test_runtime_state_corruption_requires_reinit(void)
{
    MotorCommandMapper mapper;
    MotorCommandMapperConfig config = valid_config();
    MotorCommandOutput output;

    if (init_fixture_mapper(&mapper, &config) == 0U) {
        return 0;
    }
    mapper.duty_fraction = NAN;
    mapper.direction = 1;
    if ((MotorCommandMapper_Update(&mapper, 10.0, 1U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safe(&output) || (mapper.initialized != 0U) ||
        (output.current_fault != (uint8_t)MOTOR_MAPPER_FAULT_NUMERIC)) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, 10.0, 1U, 0U, 0U,
                                   &output) != 0U) ||
        (output.current_fault !=
         (uint8_t)MOTOR_MAPPER_FAULT_NOT_INITIALIZED)) {
        return 0;
    }

    if (init_fixture_mapper(&mapper, &config) == 0U) {
        return 0;
    }
    mapper.initialized = 2U;
    if ((MotorCommandMapper_Update(&mapper, 10.0, 1U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safe(&output) || (mapper.initialized != 0U) ||
        (output.current_fault !=
         (uint8_t)MOTOR_MAPPER_FAULT_NOT_INITIALIZED)) {
        return 0;
    }

    /* These values are individually valid and mutually coherent, but they
     * were not produced by the previous mapper update and must not bypass
     * the configured slew limit. */
    if (init_fixture_mapper(&mapper, &config) == 0U) {
        return 0;
    }
    mapper.duty_fraction = config.max_duty_fraction;
    mapper.direction = 1;
    mapper.last_energized_direction = 1;
    mapper.dead_ticks_remaining = 0U;
    return (MotorCommandMapper_Update(&mapper, 99.0, 1U, 0U, 0U,
                                      &output) == 0U) &&
           output_is_safe(&output) && (mapper.initialized == 0U) &&
           (output.current_fault == (uint8_t)MOTOR_MAPPER_FAULT_NUMERIC);
}

static int test_valid_config_mutation_is_rejected(void)
{
    MotorCommandMapper mapper;
    MotorCommandMapperConfig config = valid_config();
    MotorCommandOutput output;

    if (init_fixture_mapper(&mapper, &config) == 0U) {
        return 0;
    }
    mapper.config.max_duty_fraction = 0.25;
    if (MotorCommandMapper_ConfigIsValid(&mapper.config) == 0U) {
        return 0;
    }
    return (MotorCommandMapper_Update(&mapper, 10.0, 1U, 0U, 0U,
                                      &output) == 0U) &&
           output_is_safe(&output) && (mapper.initialized == 0U) &&
           (output.current_fault == (uint8_t)MOTOR_MAPPER_FAULT_CONFIG);
}

static int test_stop_and_fault_preserve_reversal_deadtime(void)
{
    MotorCommandMapper mapper;
    MotorCommandMapperConfig config = valid_config();
    MotorCommandOutput output;

    if ((init_fixture_mapper(&mapper, &config) == 0U) ||
        (MotorCommandMapper_Update(&mapper, 10.0, 1U, 0U, 0U,
                                   &output) == 0U)) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, 0.0, 0U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safe(&output) || (output.dead_ticks_remaining != 2U)) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, -10.0, 1U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safe(&output) || (output.dead_ticks_remaining != 1U)) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, -10.0, 1U, 0U, 0U,
                                   &output) != 0U) ||
        !output_is_safe(&output) || (output.dead_ticks_remaining != 0U)) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, -10.0, 1U, 0U, 0U,
                                   &output) == 0U) ||
        (output.direction != -1)) {
        return 0;
    }

    if ((init_fixture_mapper(&mapper, &config) == 0U) ||
        (MotorCommandMapper_Update(&mapper, 10.0, 1U, 0U, 0U,
                                   &output) == 0U) ||
        (MotorCommandMapper_Update(&mapper, 0.0, 1U, 1U, 0U,
                                   &output) != 0U) ||
        !output_is_safe(&output) || (output.dead_ticks_remaining != 2U)) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, -10.0, 1U, 0U, 0U,
                                   &output) != 0U) ||
        (MotorCommandMapper_Update(&mapper, -10.0, 1U, 0U, 0U,
                                   &output) != 0U)) {
        return 0;
    }
    return (MotorCommandMapper_Update(&mapper, -10.0, 1U, 0U, 0U,
                                      &output) != 0U) &&
           (output.direction == -1);
}

static int test_duty_decrease_is_immediate(void)
{
    MotorCommandMapper mapper;
    MotorCommandMapperConfig config = valid_config();
    MotorCommandOutput output;

    if (init_fixture_mapper(&mapper, &config) == 0U) {
        return 0;
    }
    if ((MotorCommandMapper_Update(&mapper, 99.0, 1U, 0U, 0U,
                                   &output) == 0U) ||
        (MotorCommandMapper_Update(&mapper, 99.0, 1U, 0U, 0U,
                                   &output) == 0U) ||
        (MotorCommandMapper_Update(&mapper, 99.0, 1U, 0U, 0U,
                                   &output) == 0U) ||
        (fabs(output.duty_fraction - 0.15) > 1.0e-12)) {
        return 0;
    }
    return (MotorCommandMapper_Update(&mapper, 3.0, 1U, 0U, 0U,
                                      &output) != 0U) &&
           (fabs(output.duty_fraction - 0.10) <= 1.0e-12);
}

static int test_deterministic_fault_soak(void)
{
    MotorCommandMapper mapper;
    MotorCommandMapperConfig config = valid_config();
    MotorCommandOutput output;
    uint32_t i;
    uint32_t active_count = 0U;
    uint32_t injected_count = 0U;

    if (init_fixture_mapper(&mapper, &config) == 0U) {
        return 0;
    }
    for (i = 0U; i < MAPPER_SOAK_TICKS; ++i) {
        double request = 20.0 * sin(0.031415926535897934 * (double)i);
        uint8_t permitted = 1U;
        uint8_t driver_fault = 0U;
        uint32_t inhibit = 0U;
        uint8_t fault_tick = 0U;
        uint8_t active;

        if ((i != 0U) && ((i % 100003U) == 0U)) {
            request = NAN;
            fault_tick = 1U;
        } else if ((i != 0U) && ((i % 130003U) == 0U)) {
            request = INFINITY;
            fault_tick = 1U;
        } else if ((i != 0U) && ((i % 170003U) == 0U)) {
            permitted = 0U;
            fault_tick = 1U;
        } else if ((i != 0U) && ((i % 190001U) == 0U)) {
            driver_fault = 1U;
            fault_tick = 1U;
        } else if ((i != 0U) && ((i % 230003U) == 0U)) {
            inhibit = 0x40000000U;
            fault_tick = 1U;
        }

        active = MotorCommandMapper_Update(
            &mapper, request, permitted, driver_fault, inhibit, &output);
        if (!isfinite(output.duty_fraction) ||
            (output.duty_fraction < 0.0) ||
            (output.duty_fraction > config.max_duty_fraction) ||
            (active != output.bridge_enable) ||
            ((active != 0U) &&
             ((output.direction == 0) || (permitted != 1U) ||
              (driver_fault != 0U) || (inhibit != 0U)))) {
            return 0;
        }
        if (fault_tick != 0U) {
            if ((active != 0U) || !output_is_safe(&output)) {
                return 0;
            }
            injected_count++;
        }
        if (active != 0U) {
            active_count++;
        }
    }
    return (active_count > 0U) && (injected_count >= 20U);
}

int main(void)
{
    int pass = 1;

    pass &= test_invalid_configs();
    pass &= test_config_fingerprint_collision_does_not_authorize();
    pass &= test_mapping_saturation_and_safe_stop();
    pass &= test_faults_config_mutation_and_inhibit();
    pass &= test_reversal_deadtime();
    pass &= test_runtime_state_corruption_requires_reinit();
    pass &= test_valid_config_mutation_is_rejected();
    pass &= test_stop_and_fault_preserve_reversal_deadtime();
    pass &= test_duty_decrease_is_immediate();
    pass &= test_deterministic_fault_soak();

    printf("motor_command_mapper abstract fail-closed mapper: %s\n",
           pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}
