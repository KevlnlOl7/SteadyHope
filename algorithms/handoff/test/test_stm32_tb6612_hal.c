#include "stm32_tb6612_hal.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef enum {
    EVENT_GPIO = 1,
    EVENT_COMPARE = 2,
    EVENT_PWM_START = 3
} EventKind;

typedef struct {
    EventKind kind;
    uint32_t object;
    uint32_t argument;
    uint32_t value;
} TestEvent;

#define MAX_EVENTS 64U

static TestEvent events[MAX_EVENTS];
static uint32_t event_count;
static HAL_StatusTypeDef pwm_start_result = HAL_OK;

static TIM_TypeDef timer_instance;
static TIM_HandleTypeDef timer_handle;
static GPIO_TypeDef ain1_port;
static GPIO_TypeDef ain2_port;
static GPIO_TypeDef stby_port;

static void reset_fake_hal(void)
{
    memset(events, 0, sizeof(events));
    event_count = 0U;
    pwm_start_result = HAL_OK;
}

static void append_event(EventKind kind,
                         uint32_t object,
                         uint32_t argument,
                         uint32_t value)
{
    if (event_count < MAX_EVENTS) {
        events[event_count].kind = kind;
        events[event_count].object = object;
        events[event_count].argument = argument;
        events[event_count].value = value;
        event_count++;
    }
}

HAL_StatusTypeDef HAL_TIM_PWM_Start(TIM_HandleTypeDef *timer,
                                    uint32_t channel)
{
    append_event(EVENT_PWM_START,
                 (uint32_t)(timer == &timer_handle), channel, 0U);
    return pwm_start_result;
}

void HAL_GPIO_WritePin(GPIO_TypeDef *port,
                       uint16_t pin,
                       GPIO_PinState state)
{
    append_event(EVENT_GPIO, port->test_id, (uint32_t)pin,
                 (uint32_t)state);
}

void FakeHal_SetCompare(TIM_HandleTypeDef *timer,
                        uint32_t channel,
                        uint32_t compare)
{
    append_event(EVENT_COMPARE,
                 (uint32_t)(timer == &timer_handle), channel, compare);
}

static Stm32Tb6612HalConfig valid_hal_config(void)
{
    Stm32Tb6612HalConfig config;

    timer_instance.ARR = 3199U;
    timer_handle.Instance = &timer_instance;
    ain1_port.test_id = 1U;
    ain2_port.test_id = 2U;
    stby_port.test_id = 3U;

    config.pwm_timer = &timer_handle;
    config.pwm_channel = TIM_CHANNEL_1;
    config.pwm_full_scale_ccr = 3200U;
    config.ain1_port = &ain1_port;
    config.ain1_pin = UINT16_C(0x0008);
    config.ain2_port = &ain2_port;
    config.ain2_pin = UINT16_C(0x0040);
    config.stby_port = &stby_port;
    config.stby_pin = UINT16_C(0x0002);
    return config;
}

static int event_equals(uint32_t index,
                        EventKind kind,
                        uint32_t object,
                        uint32_t argument,
                        uint32_t value)
{
    return (index < event_count) && (events[index].kind == kind) &&
           (events[index].object == object) &&
           (events[index].argument == argument) &&
           (events[index].value == value);
}

static int safe_sequence_at(uint32_t offset)
{
    return event_equals(offset, EVENT_GPIO, 3U, UINT16_C(0x0002),
                        (uint32_t)GPIO_PIN_RESET) &&
           event_equals(offset + 1U, EVENT_COMPARE, 1U, TIM_CHANNEL_1,
                        0U) &&
           event_equals(offset + 2U, EVENT_GPIO, 1U,
                        UINT16_C(0x0008),
                        (uint32_t)GPIO_PIN_RESET) &&
           event_equals(offset + 3U, EVENT_GPIO, 2U,
                        UINT16_C(0x0040),
                        (uint32_t)GPIO_PIN_RESET);
}

static int initialize_adapter(Stm32Tb6612Hal *adapter)
{
    Stm32Tb6612HalConfig config = valid_hal_config();

    reset_fake_hal();
    return (STM32_TB6612_HAL_Init(adapter, &config) == HAL_OK) &&
           (event_count == 9U) && safe_sequence_at(0U) &&
           event_equals(4U, EVENT_PWM_START, 1U, TIM_CHANNEL_1, 0U) &&
           safe_sequence_at(5U) && (adapter->initialized == 1U);
}

static int test_init_and_timer_contract(void)
{
    Stm32Tb6612Hal adapter;
    Stm32Tb6612HalConfig config = valid_hal_config();

    if ((STM32_TB6612_HAL_ConfigIsValid(&config) == 0U) ||
        !initialize_adapter(&adapter)) {
        return 0;
    }

    config = valid_hal_config();
    config.pwm_full_scale_ccr = 3199U;
    if (STM32_TB6612_HAL_ConfigIsValid(&config) != 0U) {
        return 0;
    }
    config = valid_hal_config();
    config.ain2_port = config.ain1_port;
    config.ain2_pin = config.ain1_pin;
    if (STM32_TB6612_HAL_ConfigIsValid(&config) != 0U) {
        return 0;
    }

    config = valid_hal_config();
    reset_fake_hal();
    pwm_start_result = HAL_ERROR;
    if ((STM32_TB6612_HAL_Init(&adapter, &config) != HAL_ERROR) ||
        (adapter.initialized != 0U) || (event_count != 9U) ||
        !safe_sequence_at(0U) || !safe_sequence_at(5U)) {
        return 0;
    }
    return 1;
}

static int test_active_and_safe_apply_order(void)
{
    Stm32Tb6612Hal adapter;
    Tb6612Output output;

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    memset(&output, 0, sizeof(output));
    output.ccr = 320U;
    output.direction = 1;
    output.ain1 = 1U;
    output.ain2 = 0U;
    output.stby = 1U;
    output.fault = (uint8_t)TB6612_DRIVER_FAULT_NONE;

    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) ||
        (event_count != 5U) ||
        !event_equals(0U, EVENT_COMPARE, 1U, TIM_CHANNEL_1, 0U) ||
        !event_equals(1U, EVENT_GPIO, 1U, UINT16_C(0x0008),
                      (uint32_t)GPIO_PIN_SET) ||
        !event_equals(2U, EVENT_GPIO, 2U, UINT16_C(0x0040),
                      (uint32_t)GPIO_PIN_RESET) ||
        !event_equals(3U, EVENT_GPIO, 3U, UINT16_C(0x0002),
                      (uint32_t)GPIO_PIN_SET) ||
        !event_equals(4U, EVENT_COMPARE, 1U, TIM_CHANNEL_1, 320U)) {
        return 0;
    }

    memset(&output, 0, sizeof(output));
    reset_fake_hal();
    return (STM32_TB6612_HAL_Apply(&adapter, &output) == HAL_OK) &&
           (event_count == 4U) && safe_sequence_at(0U);
}

static int test_malformed_and_mutated_state_force_safe(void)
{
    Stm32Tb6612Hal adapter;
    Tb6612Output output;

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    memset(&output, 0, sizeof(output));
    output.ccr = 320U;
    output.direction = 1;
    output.ain1 = 1U;
    output.ain2 = 1U;
    output.stby = 1U;

    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U)) {
        return 0;
    }

    memset(&output, 0, sizeof(output));
    output.fault = (uint8_t)TB6612_DRIVER_FAULT_DUTY;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U)) {
        return 0;
    }

    adapter.config.stby_pin = adapter.config.ain1_pin;
    adapter.config.stby_port = adapter.config.ain1_port;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U)) {
        return 0;
    }

    timer_instance.ARR = 2999U;
    reset_fake_hal();
    return (STM32_TB6612_HAL_ForceSafe(&adapter) == HAL_OK) &&
           (event_count == 4U) && safe_sequence_at(0U);
}

int main(void)
{
    int pass = 1;

    pass &= test_init_and_timer_contract();
    pass &= test_active_and_safe_apply_order();
    pass &= test_malformed_and_mutated_state_force_safe();

    printf("STM32 TB6612 HAL ordering with fake HAL: %s\n",
           pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}
