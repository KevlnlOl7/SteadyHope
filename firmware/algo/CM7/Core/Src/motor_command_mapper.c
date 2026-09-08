#include "motor_command_mapper.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

_Static_assert(sizeof(double) == sizeof(uint64_t),
               "MotorCommandMapper requires 64-bit double");

#define MOTOR_MAPPER_MAX_REQUEST_LIMIT_DPS 2048.0
#define MOTOR_MAPPER_MAX_DEAD_TICKS 1000U

static void clear_output(MotorCommandOutput *output)
{
    if (output != NULL) {
        memset(output, 0, sizeof(*output));
    }
}

static void copy_status(const MotorCommandMapper *mapper,
                        MotorCommandOutput *output)
{
    output->fault_count = mapper->fault_count;
    output->current_fault = mapper->current_fault;
    output->last_fault = mapper->last_fault;
    output->dead_ticks_remaining = mapper->dead_ticks_remaining;
}

static void record_fault(MotorCommandMapper *mapper,
                         MotorCommandMapperFault fault)
{
    uint8_t value = (uint8_t)fault;

    if (mapper->current_fault != value) {
        if (mapper->fault_count < UINT32_MAX) {
            mapper->fault_count++;
        }
        mapper->last_fault = value;
    }
    mapper->current_fault = value;
}

static void clear_dynamic_state(MotorCommandMapper *mapper)
{
    mapper->duty_fraction = 0.0;
    mapper->direction = 0;
    mapper->last_energized_direction = 0;
    mapper->dead_ticks_remaining = 0U;
}

static void build_runtime_guard(const MotorCommandMapper *mapper,
                                uint64_t guard[3])
{
    uint64_t duty_bits;

    memcpy(&duty_bits, &mapper->duty_fraction, sizeof(duty_bits));
    guard[0] = duty_bits;
    guard[1] = (uint64_t)mapper->fault_count |
               ((uint64_t)mapper->dead_ticks_remaining << 32U) |
               ((uint64_t)(uint8_t)mapper->direction << 48U) |
               ((uint64_t)(uint8_t)mapper->last_energized_direction << 56U);
    guard[2] = (uint64_t)mapper->initialized |
               ((uint64_t)mapper->current_fault << 8U) |
               ((uint64_t)mapper->last_fault << 16U);
}

static void refresh_runtime_guard(MotorCommandMapper *mapper)
{
    build_runtime_guard(mapper, mapper->runtime_guard);
}

static uint8_t runtime_guard_matches(const MotorCommandMapper *mapper)
{
    uint64_t expected[3];
    uint32_t index;

    build_runtime_guard(mapper, expected);
    for (index = 0U; index < 3U; ++index) {
        if (mapper->runtime_guard[index] != expected[index]) {
            return 0U;
        }
    }
    return 1U;
}

static void enter_or_advance_safe_stop(MotorCommandMapper *mapper)
{
    if (mapper->direction != 0) {
        mapper->last_energized_direction = mapper->direction;
        mapper->dead_ticks_remaining =
            mapper->config.reversal_dead_ticks;
    } else if (mapper->dead_ticks_remaining > 0U) {
        mapper->dead_ticks_remaining--;
    }
    mapper->duty_fraction = 0.0;
    mapper->direction = 0;
}

static uint8_t fail_closed(MotorCommandMapper *mapper,
                           MotorCommandOutput *output,
                           MotorCommandMapperFault fault,
                           uint32_t inhibit_flags,
                           uint8_t require_reinit)
{
    if (require_reinit != 0U) {
        clear_dynamic_state(mapper);
    } else {
        enter_or_advance_safe_stop(mapper);
    }
    record_fault(mapper, fault);
    if (require_reinit != 0U) {
        mapper->initialized = 0U;
    }
    refresh_runtime_guard(mapper);
    clear_output(output);
    output->active_inhibit_flags = inhibit_flags;
    copy_status(mapper, output);
    return 0U;
}

uint8_t MotorCommandMapper_ConfigIsValid(
    const MotorCommandMapperConfig *config)
{
    if (config == NULL) {
        return 0U;
    }
    if (!isfinite(config->deadband_dps) ||
        !isfinite(config->gain_duty_fraction_per_dps) ||
        !isfinite(config->max_duty_fraction) ||
        !isfinite(config->max_duty_step_per_tick) ||
        !isfinite(config->max_abs_request_dps)) {
        return 0U;
    }
    if ((config->deadband_dps < 0.0) ||
        (config->gain_duty_fraction_per_dps <= 0.0) ||
        (config->gain_duty_fraction_per_dps > 1.0) ||
        (config->max_duty_fraction <= 0.0) ||
        (config->max_duty_fraction > 1.0) ||
        (config->max_duty_step_per_tick <= 0.0) ||
        (config->max_duty_step_per_tick > 1.0) ||
        (config->max_abs_request_dps <= 0.0) ||
        (config->max_abs_request_dps > MOTOR_MAPPER_MAX_REQUEST_LIMIT_DPS) ||
        (config->deadband_dps >= config->max_abs_request_dps) ||
        (config->reversal_dead_ticks == 0U) ||
        (config->reversal_dead_ticks > MOTOR_MAPPER_MAX_DEAD_TICKS) ||
        ((config->direction_polarity != 1) &&
         (config->direction_polarity != -1))) {
        return 0U;
    }
    return 1U;
}

static uint32_t fnv1a_u64(uint32_t hash, uint64_t value)
{
    uint32_t shift;

    for (shift = 0U; shift < 64U; shift += 8U) {
        hash ^= (uint32_t)((value >> shift) & 0xFFU);
        hash *= 16777619U;
    }
    return hash;
}

uint32_t MotorCommandMapper_ConfigFingerprint(
    const MotorCommandMapperConfig *config)
{
    uint32_t hash = 2166136261U;
    uint64_t bits;

    if (config == NULL) {
        return 0U;
    }
    memcpy(&bits, &config->deadband_dps, sizeof(bits));
    hash = fnv1a_u64(hash, bits);
    memcpy(&bits, &config->gain_duty_fraction_per_dps, sizeof(bits));
    hash = fnv1a_u64(hash, bits);
    memcpy(&bits, &config->max_duty_fraction, sizeof(bits));
    hash = fnv1a_u64(hash, bits);
    memcpy(&bits, &config->max_duty_step_per_tick, sizeof(bits));
    hash = fnv1a_u64(hash, bits);
    memcpy(&bits, &config->max_abs_request_dps, sizeof(bits));
    hash = fnv1a_u64(hash, bits);
    hash = fnv1a_u64(hash, (uint64_t)config->reversal_dead_ticks);
    hash = fnv1a_u64(
        hash, (uint64_t)(uint8_t)config->direction_polarity);
    return hash;
}

static uint8_t config_bits_equal(const MotorCommandMapperConfig *left,
                                 const MotorCommandMapperConfig *right)
{
    uint64_t left_bits;
    uint64_t right_bits;

#define DOUBLE_FIELD_EQUAL(field)                                            \
    (memcpy(&left_bits, &left->field, sizeof(left_bits)),                    \
     memcpy(&right_bits, &right->field, sizeof(right_bits)),                 \
     left_bits == right_bits)

    return (uint8_t)(
        DOUBLE_FIELD_EQUAL(deadband_dps) &&
        DOUBLE_FIELD_EQUAL(gain_duty_fraction_per_dps) &&
        DOUBLE_FIELD_EQUAL(max_duty_fraction) &&
        DOUBLE_FIELD_EQUAL(max_duty_step_per_tick) &&
        DOUBLE_FIELD_EQUAL(max_abs_request_dps) &&
        (left->reversal_dead_ticks == right->reversal_dead_ticks) &&
        (left->direction_polarity == right->direction_polarity));

#undef DOUBLE_FIELD_EQUAL
}

static uint8_t dynamic_state_is_valid(const MotorCommandMapper *mapper)
{
    if (!isfinite(mapper->duty_fraction) ||
        (mapper->duty_fraction < 0.0) ||
        (mapper->duty_fraction > mapper->config.max_duty_fraction) ||
        (mapper->duty_fraction > 1.0) ||
        ((mapper->direction != -1) && (mapper->direction != 0) &&
         (mapper->direction != 1)) ||
        ((mapper->last_energized_direction != -1) &&
         (mapper->last_energized_direction != 0) &&
         (mapper->last_energized_direction != 1)) ||
        (mapper->dead_ticks_remaining >
         mapper->config.reversal_dead_ticks) ||
        (mapper->current_fault > (uint8_t)MOTOR_MAPPER_FAULT_NUMERIC) ||
        (mapper->last_fault > (uint8_t)MOTOR_MAPPER_FAULT_NUMERIC)) {
        return 0U;
    }
    if ((mapper->dead_ticks_remaining > 0U) &&
        ((mapper->duty_fraction != 0.0) || (mapper->direction != 0))) {
        return 0U;
    }
    if (((mapper->duty_fraction == 0.0) && (mapper->direction != 0)) ||
        ((mapper->duty_fraction > 0.0) && (mapper->direction == 0))) {
        return 0U;
    }
    if (((mapper->direction != 0) &&
         ((mapper->last_energized_direction != mapper->direction) ||
          (mapper->dead_ticks_remaining != 0U))) ||
        ((mapper->last_energized_direction == 0) &&
         (mapper->dead_ticks_remaining != 0U))) {
        return 0U;
    }
    return runtime_guard_matches(mapper);
}

uint8_t MotorCommandMapper_Init(MotorCommandMapper *mapper,
                                const MotorCommandMapperConfig *config,
                                const MotorCommandMapperConfig *approved_config)
{
    uint32_t actual_fingerprint;

    if (mapper == NULL) {
        return 0U;
    }
    memset(mapper, 0, sizeof(*mapper));
    actual_fingerprint = MotorCommandMapper_ConfigFingerprint(config);
    if ((MotorCommandMapper_ConfigIsValid(config) == 0U) ||
        (MotorCommandMapper_ConfigIsValid(approved_config) == 0U) ||
        (config_bits_equal(config, approved_config) == 0U)) {
        record_fault(mapper, MOTOR_MAPPER_FAULT_CONFIG);
        return 0U;
    }
    mapper->config = *config;
    mapper->initialized_config = *approved_config;
    mapper->config_fingerprint = actual_fingerprint;
    mapper->initialized = 1U;
    refresh_runtime_guard(mapper);
    return 1U;
}

static double move_toward(double current, double target, double step)
{
    if (current < target) {
        double next = current + step;
        return (next < target) ? next : target;
    }
    if (current > target) {
        double next = current - step;
        return (next > target) ? next : target;
    }
    return target;
}

uint8_t MotorCommandMapper_Update(MotorCommandMapper *mapper,
                                  double compensation_request_dps,
                                  uint8_t actuation_permitted,
                                  uint8_t driver_fault,
                                  uint32_t inhibit_flags,
                                  MotorCommandOutput *output)
{
    double signed_request;
    double target_duty;
    int8_t desired_direction;

    clear_output(output);
    if ((mapper == NULL) || (output == NULL)) {
        return 0U;
    }
    if (mapper->initialized != 1U) {
        return fail_closed(mapper, output,
                           MOTOR_MAPPER_FAULT_NOT_INITIALIZED, 0U, 1U);
    }
    if ((MotorCommandMapper_ConfigIsValid(&mapper->config) == 0U) ||
        (config_bits_equal(&mapper->config,
                           &mapper->initialized_config) == 0U) ||
        (MotorCommandMapper_ConfigFingerprint(&mapper->config) !=
         mapper->config_fingerprint)) {
        return fail_closed(mapper, output, MOTOR_MAPPER_FAULT_CONFIG, 0U,
                           1U);
    }
    if (dynamic_state_is_valid(mapper) == 0U) {
        return fail_closed(mapper, output, MOTOR_MAPPER_FAULT_NUMERIC, 0U,
                           1U);
    }
    if (actuation_permitted != 1U) {
        enter_or_advance_safe_stop(mapper);
        mapper->current_fault = (uint8_t)MOTOR_MAPPER_FAULT_NONE;
        refresh_runtime_guard(mapper);
        copy_status(mapper, output);
        return 0U;
    }
    if (driver_fault != 0U) {
        return fail_closed(mapper, output, MOTOR_MAPPER_FAULT_DRIVER, 0U,
                           0U);
    }
    if (inhibit_flags != 0U) {
        return fail_closed(mapper, output, MOTOR_MAPPER_FAULT_INHIBIT,
                           inhibit_flags, 0U);
    }
    if (!isfinite(compensation_request_dps) ||
        (fabs(compensation_request_dps) > mapper->config.max_abs_request_dps)) {
        return fail_closed(mapper, output, MOTOR_MAPPER_FAULT_INPUT, 0U,
                           0U);
    }

    signed_request = compensation_request_dps *
                     (double)mapper->config.direction_polarity;
    target_duty = fabs(signed_request) - mapper->config.deadband_dps;
    if (target_duty <= 0.0) {
        enter_or_advance_safe_stop(mapper);
        mapper->current_fault = (uint8_t)MOTOR_MAPPER_FAULT_NONE;
        refresh_runtime_guard(mapper);
        copy_status(mapper, output);
        return 0U;
    }
    target_duty *= mapper->config.gain_duty_fraction_per_dps;
    if (target_duty > mapper->config.max_duty_fraction) {
        target_duty = mapper->config.max_duty_fraction;
    }
    desired_direction = (signed_request > 0.0) ? 1 : -1;

    if ((mapper->direction != 0) &&
        (desired_direction != mapper->direction)) {
        enter_or_advance_safe_stop(mapper);
        mapper->current_fault = (uint8_t)MOTOR_MAPPER_FAULT_NONE;
        refresh_runtime_guard(mapper);
        copy_status(mapper, output);
        return 0U;
    }

    if ((mapper->direction == 0) &&
        (mapper->last_energized_direction != 0) &&
        (desired_direction != mapper->last_energized_direction) &&
        (mapper->dead_ticks_remaining > 0U)) {
        enter_or_advance_safe_stop(mapper);
        mapper->current_fault = (uint8_t)MOTOR_MAPPER_FAULT_NONE;
        refresh_runtime_guard(mapper);
        copy_status(mapper, output);
        return 0U;
    }
    if (desired_direction == mapper->last_energized_direction) {
        mapper->dead_ticks_remaining = 0U;
    }

    if (mapper->direction == 0) {
        mapper->direction = desired_direction;
        mapper->last_energized_direction = desired_direction;
    }
    if (target_duty < mapper->duty_fraction) {
        mapper->duty_fraction = target_duty;
    } else {
        mapper->duty_fraction = move_toward(
            mapper->duty_fraction, target_duty,
            mapper->config.max_duty_step_per_tick);
    }
    if (!isfinite(mapper->duty_fraction) ||
        (mapper->duty_fraction <= 0.0) ||
        (mapper->duty_fraction > mapper->config.max_duty_fraction) ||
        (mapper->duty_fraction > 1.0)) {
        return fail_closed(mapper, output, MOTOR_MAPPER_FAULT_NUMERIC, 0U,
                           0U);
    }

    mapper->current_fault = (uint8_t)MOTOR_MAPPER_FAULT_NONE;
    refresh_runtime_guard(mapper);
    output->duty_fraction = mapper->duty_fraction;
    output->direction = mapper->direction;
    output->bridge_enable = 1U;
    copy_status(mapper, output);
    return 1U;
}
