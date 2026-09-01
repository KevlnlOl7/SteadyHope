#include "stm32_tb6612_hal.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef enum {
    EVENT_GPIO = 1,
    EVENT_COMPARE = 2,
    EVENT_PWM_START = 3
} EventKind;

typedef enum {
    IRQ_EVENT_GET_PRIMASK = 1,
    IRQ_EVENT_DISABLE = 2,
    IRQ_EVENT_BARRIER = 3,
    IRQ_EVENT_RESTORE_PRIMASK = 4,
    IRQ_EVENT_REQUEST = 5,
    IRQ_EVENT_HANDLER_ENTER = 6,
    IRQ_EVENT_HANDLER_EXIT = 7
} IrqEventKind;

typedef enum {
    PENDING_OPERATION_NONE = 0,
    PENDING_OPERATION_FORCE_SAFE = 1,
    PENDING_OPERATION_APPLY = 2
} PendingOperationKind;

typedef struct {
    EventKind kind;
    uint32_t object;
    uint32_t argument;
    uint32_t value;
} TestEvent;

#define MAX_EVENTS 64U
#define MAX_IRQ_EVENTS 128U

static TestEvent events[MAX_EVENTS];
static uint32_t event_count;
static IrqEventKind irq_events[MAX_IRQ_EVENTS];
static uint32_t irq_event_values[MAX_IRQ_EVENTS];
static uint32_t irq_event_count;
static uint32_t fake_primask;
static PendingOperationKind pending_operation;
static Stm32Tb6612Hal *pending_adapter;
static Tb6612Output pending_output;
static HAL_StatusTypeDef pending_status;
static uint32_t pending_service_count;
static uint32_t trigger_event_count;
static PendingOperationKind trigger_operation;
static Stm32Tb6612Hal *trigger_adapter;
static Tb6612Output trigger_output;
static HAL_StatusTypeDef pwm_start_result = HAL_OK;

static TIM_TypeDef timer_instance;
static TIM_HandleTypeDef timer_handle;
static GPIO_TypeDef ain1_port;
static GPIO_TypeDef ain2_port;
static GPIO_TypeDef stby_port;

static void service_pending_operation(void);

static void append_irq_event(IrqEventKind kind, uint32_t value)
{
    if (irq_event_count < MAX_IRQ_EVENTS) {
        irq_events[irq_event_count] = kind;
        irq_event_values[irq_event_count] = value;
        irq_event_count++;
    }
}

static void reset_fake_hal(void)
{
    memset(events, 0, sizeof(events));
    memset(irq_events, 0, sizeof(irq_events));
    memset(irq_event_values, 0, sizeof(irq_event_values));
    event_count = 0U;
    irq_event_count = 0U;
    fake_primask = 0U;
    pending_operation = PENDING_OPERATION_NONE;
    pending_adapter = NULL;
    memset(&pending_output, 0, sizeof(pending_output));
    pending_status = HAL_BUSY;
    pending_service_count = 0U;
    trigger_event_count = 0U;
    trigger_operation = PENDING_OPERATION_NONE;
    trigger_adapter = NULL;
    memset(&trigger_output, 0, sizeof(trigger_output));
    pwm_start_result = HAL_OK;
}

static void request_triggered_operation(void)
{
    if ((trigger_operation == PENDING_OPERATION_NONE) ||
        (event_count != trigger_event_count)) {
        return;
    }
    pending_operation = trigger_operation;
    pending_adapter = trigger_adapter;
    pending_output = trigger_output;
    trigger_operation = PENDING_OPERATION_NONE;
    append_irq_event(IRQ_EVENT_REQUEST,
                     (uint32_t)pending_operation);
    service_pending_operation();
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
    request_triggered_operation();
}

uint32_t __get_PRIMASK(void)
{
    append_irq_event(IRQ_EVENT_GET_PRIMASK, fake_primask);
    return fake_primask;
}

void __disable_irq(void)
{
    fake_primask = 1U;
    append_irq_event(IRQ_EVENT_DISABLE, fake_primask);
}

void __DMB(void)
{
    append_irq_event(IRQ_EVENT_BARRIER, fake_primask);
}

void __set_PRIMASK(uint32_t primask)
{
    fake_primask = primask & 1U;
    append_irq_event(IRQ_EVENT_RESTORE_PRIMASK, fake_primask);
    service_pending_operation();
}

static void service_pending_operation(void)
{
    PendingOperationKind operation;
    Stm32Tb6612Hal *adapter;
    Tb6612Output output;

    if ((fake_primask != 0U) ||
        (pending_operation == PENDING_OPERATION_NONE)) {
        return;
    }
    operation = pending_operation;
    adapter = pending_adapter;
    output = pending_output;
    pending_operation = PENDING_OPERATION_NONE;
    pending_adapter = NULL;
    pending_service_count++;
    append_irq_event(IRQ_EVENT_HANDLER_ENTER, (uint32_t)operation);
    if (operation == PENDING_OPERATION_FORCE_SAFE) {
        pending_status = STM32_TB6612_HAL_ForceSafe(adapter);
    } else {
        pending_status = STM32_TB6612_HAL_Apply(adapter, &output);
    }
    append_irq_event(IRQ_EVENT_HANDLER_EXIT, (uint32_t)operation);
}

static void arm_operation_after_hardware_event(
    uint32_t hardware_event_count,
    PendingOperationKind operation,
    Stm32Tb6612Hal *adapter,
    const Tb6612Output *output)
{
    trigger_event_count = hardware_event_count;
    trigger_operation = operation;
    trigger_adapter = adapter;
    memset(&trigger_output, 0, sizeof(trigger_output));
    if (output != NULL) {
        trigger_output = *output;
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
    config.max_active_ccr = 800U;
    config.release_ain1_level = 1U;
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

static int gpio_only_safe_sequence_at(uint32_t offset)
{
    return event_equals(offset, EVENT_GPIO, 3U, UINT16_C(0x0002),
                        (uint32_t)GPIO_PIN_RESET) &&
           event_equals(offset + 1U, EVENT_GPIO, 1U,
                        UINT16_C(0x0008),
                        (uint32_t)GPIO_PIN_RESET) &&
           event_equals(offset + 2U, EVENT_GPIO, 2U,
                        UINT16_C(0x0040),
                        (uint32_t)GPIO_PIN_RESET);
}

static int active_sequence_at(uint32_t offset, uint32_t ccr)
{
    return event_equals(offset, EVENT_COMPARE, 1U, TIM_CHANNEL_1, 0U) &&
           event_equals(offset + 1U, EVENT_GPIO, 1U,
                        UINT16_C(0x0008),
                        (uint32_t)GPIO_PIN_SET) &&
           event_equals(offset + 2U, EVENT_GPIO, 2U,
                        UINT16_C(0x0040),
                        (uint32_t)GPIO_PIN_RESET) &&
           event_equals(offset + 3U, EVENT_GPIO, 3U,
                        UINT16_C(0x0002),
                        (uint32_t)GPIO_PIN_SET) &&
           event_equals(offset + 4U, EVENT_COMPARE, 1U,
                        TIM_CHANNEL_1, ccr);
}

static uint32_t find_irq_event(IrqEventKind kind, uint32_t start)
{
    uint32_t index;

    for (index = start; index < irq_event_count; ++index) {
        if (irq_events[index] == kind) {
            return index;
        }
    }
    return UINT32_MAX;
}

static int initialize_adapter(Stm32Tb6612Hal *adapter)
{
    Stm32Tb6612HalConfig config = valid_hal_config();

    memset(adapter, 0, sizeof(*adapter));
    reset_fake_hal();
    return (STM32_TB6612_HAL_Init(adapter, &config) == HAL_OK) &&
           (event_count == 9U) && safe_sequence_at(0U) &&
           event_equals(4U, EVENT_PWM_START, 1U, TIM_CHANNEL_1, 0U) &&
           safe_sequence_at(5U) && (adapter->initialized == 1U) &&
           (adapter->last_active_direction == 0) &&
           (adapter->config_guard[0] != adapter->config_guard[1]) &&
           (adapter->initialized_config_guard[0] !=
            adapter->initialized_config_guard[1]) &&
           (adapter->expected_pwm_instance_guard[0] !=
            adapter->expected_pwm_instance_guard[1]) &&
           ((adapter->config_guard[0] !=
             adapter->initialized_config_guard[0]) ||
            (adapter->config_guard[1] !=
             adapter->initialized_config_guard[1]));
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
    config.max_active_ccr = 0U;
    if (STM32_TB6612_HAL_ConfigIsValid(&config) == 0U) {
        return 0;
    }
    config = valid_hal_config();
    config.max_active_ccr = 3201U;
    if (STM32_TB6612_HAL_ConfigIsValid(&config) != 0U) {
        return 0;
    }
    config = valid_hal_config();
    config.release_ain1_level = 2U;
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
    memset(&adapter, 0, sizeof(adapter));
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
    return (STM32_TB6612_HAL_ForceSafe(&adapter) == HAL_ERROR) &&
           (event_count == 4U) && safe_sequence_at(0U);
}

static int test_direction_polarity_and_transition_guard(void)
{
    Stm32Tb6612Hal adapter;
    Tb6612Output output;

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    memset(&output, 0, sizeof(output));
    output.ccr = 320U;
    output.direction = 1;
    output.ain1 = 0U;
    output.ain2 = 1U;
    output.stby = 1U;

    /* The pins encode take-up while the authority field says release. */
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.last_active_direction != 0)) {
        return 0;
    }

    output.ain1 = 1U;
    output.ain2 = 0U;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) ||
        (adapter.last_active_direction != 1)) {
        return 0;
    }

    output.direction = -1;
    output.ain1 = 0U;
    output.ain2 = 1U;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.last_active_direction != 1)) {
        return 0;
    }

    /* A rejected reversal cannot itself authorize the next reversal. */
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.last_active_direction != 1)) {
        return 0;
    }

    memset(&output, 0, sizeof(output));
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.last_active_direction != 0)) {
        return 0;
    }

    output.ccr = 320U;
    output.direction = -1;
    output.ain1 = 0U;
    output.ain2 = 1U;
    output.stby = 1U;
    reset_fake_hal();
    return (STM32_TB6612_HAL_Apply(&adapter, &output) == HAL_OK) &&
           (event_count == 5U) &&
           (adapter.last_active_direction == -1);
}

static int test_runtime_state_corruption_latches_safe(void)
{
    Stm32Tb6612Hal adapter;
    Tb6612Output output;

    memset(&output, 0, sizeof(output));
    output.ccr = 320U;
    output.direction = 1;
    output.ain1 = 1U;
    output.ain2 = 0U;
    output.stby = 1U;

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.last_active_direction = 2;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 0U)) {
        return 0;
    }

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.runtime_guard[0] ^= UINT64_C(1);
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 0U)) {
        return 0;
    }

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.config.release_ain1_level = 0U;
    reset_fake_hal();
    return (STM32_TB6612_HAL_Apply(&adapter, &output) == HAL_ERROR) &&
           (event_count == 4U) && safe_sequence_at(0U) &&
           (adapter.initialized == 0U);
}

static int test_force_safe_does_not_reauthorize_corruption(void)
{
    Stm32Tb6612Hal adapter;

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.last_active_direction = 2;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_ForceSafe(&adapter) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 0U) ||
        (adapter.last_active_direction != 0)) {
        return 0;
    }

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.runtime_guard[1] ^= UINT64_C(1);
    reset_fake_hal();
    if ((STM32_TB6612_HAL_ForceSafe(&adapter) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 0U) ||
        (adapter.last_active_direction != 0)) {
        return 0;
    }

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.config.release_ain1_level = 0U;
    reset_fake_hal();
    return (STM32_TB6612_HAL_ForceSafe(&adapter) == HAL_ERROR) &&
           (event_count == 4U) && safe_sequence_at(0U) &&
           (adapter.initialized == 0U) &&
           (adapter.last_active_direction == 0);
}

static int test_integer_active_cap_is_independent_fail_closed_limit(void)
{
    Stm32Tb6612Hal adapter;
    Stm32Tb6612HalConfig config = valid_hal_config();
    Tb6612Output output;

    memset(&output, 0, sizeof(output));
    output.ccr = 1U;
    output.direction = 1;
    output.ain1 = 1U;
    output.ain2 = 0U;
    output.stby = 1U;

    /* Zero is a supported motor-locked HAL configuration. */
    config.max_active_ccr = 0U;
    memset(&adapter, 0, sizeof(adapter));
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Init(&adapter, &config) != HAL_OK) ||
        (STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_ERROR) ||
        (event_count != 13U) || !safe_sequence_at(9U) ||
        (adapter.initialized != 1U) ||
        (adapter.last_active_direction != 0)) {
        return 0;
    }

    memset(&output, 0, sizeof(output));
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) ||
        (event_count != 4U) || !safe_sequence_at(0U)) {
        return 0;
    }

    config = valid_hal_config();
    config.max_active_ccr = 400U;
    reset_fake_hal();
    if (STM32_TB6612_HAL_Init(&adapter, &config) != HAL_OK) {
        return 0;
    }
    memset(&output, 0, sizeof(output));
    output.ccr = 400U;
    output.direction = 1;
    output.ain1 = 1U;
    output.ain2 = 0U;
    output.stby = 1U;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) ||
        (event_count != 5U)) {
        return 0;
    }

    output.ccr = 401U;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 1U)) {
        return 0;
    }

    adapter.config.max_active_ccr = 399U;
    reset_fake_hal();
    return (STM32_TB6612_HAL_Apply(&adapter, &output) == HAL_ERROR) &&
           (event_count == 4U) && safe_sequence_at(0U) &&
           (adapter.initialized == 0U);
}

static int test_config_snapshot_integrity_precedes_pointer_use(void)
{
    Stm32Tb6612Hal adapter;
    Tb6612Output safe_output;

    memset(&safe_output, 0, sizeof(safe_output));

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.initialized_config.pwm_timer =
        (TIM_HandleTypeDef *)(uintptr_t)1U;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &safe_output) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 0U)) {
        return 0;
    }

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.initialized_config.ain1_pin = 0U;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_ForceSafe(&adapter) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 0U)) {
        return 0;
    }

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.config.pwm_timer = (TIM_HandleTypeDef *)(uintptr_t)1U;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_ForceSafe(&adapter) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 0U)) {
        return 0;
    }

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.config.stby_pin = 0U;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &safe_output) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 0U)) {
        return 0;
    }

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.initialized_config_guard[0] ^= UINT64_C(1);
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &safe_output) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 0U)) {
        return 0;
    }

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.config_guard[1] ^= UINT64_C(1);
    reset_fake_hal();
    if ((STM32_TB6612_HAL_ForceSafe(&adapter) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 0U)) {
        return 0;
    }

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.initialized_config_guard[0] ^= UINT64_C(1);
    adapter.config_guard[0] ^= UINT64_C(1);
    reset_fake_hal();
    return (STM32_TB6612_HAL_ForceSafe(&adapter) == HAL_ERROR) &&
           (event_count == 0U) && (adapter.initialized == 0U) &&
           (adapter.last_active_direction == 0);
}

static int test_mutated_timer_instance_uses_gpio_only_safe_path(void)
{
    Stm32Tb6612Hal adapter;
    Tb6612Output output;

    memset(&output, 0, sizeof(output));
    output.ccr = 320U;
    output.direction = 1;
    output.ain1 = 1U;
    output.ain2 = 0U;
    output.stby = 1U;

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    reset_fake_hal();
    if (STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) {
        return 0;
    }
    timer_handle.Instance = (TIM_TypeDef *)(uintptr_t)1U;
    memset(&output, 0, sizeof(output));
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_ERROR) ||
        (event_count != 3U) || !gpio_only_safe_sequence_at(0U) ||
        (adapter.initialized != 0U)) {
        return 0;
    }

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    memset(&output, 0, sizeof(output));
    output.ccr = 320U;
    output.direction = 1;
    output.ain1 = 1U;
    output.ain2 = 0U;
    output.stby = 1U;
    reset_fake_hal();
    if (STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) {
        return 0;
    }
    timer_handle.Instance = NULL;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_ForceSafe(&adapter) != HAL_ERROR) ||
        (event_count != 3U) || !gpio_only_safe_sequence_at(0U) ||
        (adapter.initialized != 0U)) {
        return 0;
    }

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.expected_pwm_instance_guard[0] ^= UINT64_C(1);
    reset_fake_hal();
    return (STM32_TB6612_HAL_ForceSafe(&adapter) == HAL_ERROR) &&
           (event_count == 3U) && gpio_only_safe_sequence_at(0U) &&
           (adapter.initialized == 0U);
}

static void corrupt_lifecycle_marker(Stm32Tb6612Hal *adapter,
                                     uint32_t marker)
{
    if (marker == 0U) {
        adapter->lifecycle_magic ^= UINT64_C(1);
    } else if (marker == 1U) {
        adapter->lifecycle_guard[0] ^= UINT64_C(1);
    } else if (marker == 2U) {
        adapter->lifecycle_guard[1] ^= UINT64_C(1);
    } else {
        adapter->lifecycle_magic = 0U;
        adapter->lifecycle_guard[0] = 0U;
        adapter->lifecycle_guard[1] = 0U;
    }
}

static int exercise_corrupt_lifecycle_safe_attempt(uint32_t marker,
                                                   uint8_t use_apply)
{
    Stm32Tb6612Hal adapter;
    Tb6612Output output;
    HAL_StatusTypeDef status;

    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    memset(&output, 0, sizeof(output));
    output.ccr = 320U;
    output.direction = 1;
    output.ain1 = 1U;
    output.ain2 = 0U;
    output.stby = 1U;
    reset_fake_hal();
    if (STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) {
        return 0;
    }

    corrupt_lifecycle_marker(&adapter, marker);
    reset_fake_hal();
    status = (use_apply != 0U) ?
             STM32_TB6612_HAL_Apply(&adapter, &output) :
             STM32_TB6612_HAL_ForceSafe(&adapter);
    return (status == HAL_ERROR) && (event_count == 4U) &&
           safe_sequence_at(0U) && (adapter.initialized == 0U) &&
           (adapter.last_active_direction == 0) &&
           (adapter.config.max_active_ccr == 800U);
}

static int test_corrupt_lifecycle_never_blocks_safe_attempt(void)
{
    uint32_t marker;

    for (marker = 0U; marker < 4U; ++marker) {
        if (!exercise_corrupt_lifecycle_safe_attempt(marker, 0U) ||
            !exercise_corrupt_lifecycle_safe_attempt(marker, 1U)) {
            return 0;
        }
    }
    return 1;
}

static int test_reinit_safes_live_adapter_before_validation(void)
{
    Stm32Tb6612Hal adapter;
    Stm32Tb6612HalConfig invalid_config = valid_hal_config();
    Stm32Tb6612HalConfig valid_config = valid_hal_config();
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
    reset_fake_hal();
    if (STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) {
        return 0;
    }

    invalid_config.max_active_ccr =
        invalid_config.pwm_full_scale_ccr + 1U;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Init(&adapter, &invalid_config) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 0U) ||
        (adapter.config.max_active_ccr != 800U)) {
        return 0;
    }

    if (STM32_TB6612_HAL_Init(&adapter, &valid_config) != HAL_OK) {
        return 0;
    }
    memset(&output, 0, sizeof(output));
    output.ccr = 320U;
    output.direction = 1;
    output.ain1 = 1U;
    output.ain2 = 0U;
    output.stby = 1U;
    reset_fake_hal();
    if (STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) {
        return 0;
    }
    adapter.lifecycle_magic = 0U;
    adapter.lifecycle_guard[0] = 0U;
    adapter.lifecycle_guard[1] = 0U;
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Init(&adapter, &invalid_config) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 0U) ||
        (adapter.config.max_active_ccr != 800U)) {
        return 0;
    }

    /* A recognizable corrupt live identity is never erased in-place. */
    if (!initialize_adapter(&adapter)) {
        return 0;
    }
    adapter.lifecycle_guard[0] ^= UINT64_C(1);
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Init(&adapter, &valid_config) != HAL_ERROR) ||
        (event_count != 4U) || !safe_sequence_at(0U) ||
        (adapter.initialized != 0U) ||
        (adapter.lifecycle_magic == 0U)) {
        return 0;
    }

    /* Truly fresh objects never cause speculative GPIO or timer writes. */
    memset(&adapter, 0, sizeof(adapter));
    reset_fake_hal();
    if ((STM32_TB6612_HAL_ForceSafe(&adapter) != HAL_ERROR) ||
        (event_count != 0U)) {
        return 0;
    }
    memset(&adapter, 0xA5, sizeof(adapter));
    memset(&output, 0, sizeof(output));
    reset_fake_hal();
    if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_ERROR) ||
        (event_count != 0U)) {
        return 0;
    }

    /* Non-matching stack bytes remain a valid first-Init input. */
    memset(&adapter, 0xA5, sizeof(adapter));
    reset_fake_hal();
    return (STM32_TB6612_HAL_Init(&adapter, &valid_config) == HAL_OK) &&
           (event_count == 9U) && safe_sequence_at(0U) &&
           safe_sequence_at(5U) && (adapter.initialized == 1U);
}

static int single_critical_section_restored(uint32_t original_primask)
{
    return (irq_event_count >= 5U) &&
           (irq_events[0] == IRQ_EVENT_GET_PRIMASK) &&
           (irq_event_values[0] == original_primask) &&
           (irq_events[1] == IRQ_EVENT_DISABLE) &&
           (irq_events[2] == IRQ_EVENT_BARRIER) &&
           (irq_events[irq_event_count - 2U] == IRQ_EVENT_BARRIER) &&
           (irq_events[irq_event_count - 1U] ==
            IRQ_EVENT_RESTORE_PRIMASK) &&
           (irq_event_values[irq_event_count - 1U] ==
            original_primask) &&
           (fake_primask == original_primask);
}

static int test_primask_restore_on_apply_and_force_safe_paths(void)
{
    uint32_t original_primask;

    for (original_primask = 0U;
         original_primask <= 1U;
         ++original_primask) {
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
        reset_fake_hal();
        fake_primask = original_primask;
        if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) ||
            (event_count != 5U) || !active_sequence_at(0U, 320U) ||
            !single_critical_section_restored(original_primask)) {
            return 0;
        }

        memset(&output, 0, sizeof(output));
        reset_fake_hal();
        fake_primask = original_primask;
        if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) ||
            (event_count != 4U) || !safe_sequence_at(0U) ||
            !single_critical_section_restored(original_primask)) {
            return 0;
        }

        output.ccr = 801U;
        output.direction = 1;
        output.ain1 = 1U;
        output.stby = 1U;
        reset_fake_hal();
        fake_primask = original_primask;
        if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_ERROR) ||
            (event_count != 4U) || !safe_sequence_at(0U) ||
            !single_critical_section_restored(original_primask)) {
            return 0;
        }

        reset_fake_hal();
        fake_primask = original_primask;
        if ((STM32_TB6612_HAL_ForceSafe(&adapter) != HAL_OK) ||
            (event_count != 4U) || !safe_sequence_at(0U) ||
            !single_critical_section_restored(original_primask)) {
            return 0;
        }

        if (!initialize_adapter(&adapter)) {
            return 0;
        }
        reset_fake_hal();
        fake_primask = original_primask;
        if ((STM32_TB6612_HAL_Apply(&adapter, NULL) != HAL_ERROR) ||
            (event_count != 4U) || !safe_sequence_at(0U) ||
            !single_critical_section_restored(original_primask)) {
            return 0;
        }

        reset_fake_hal();
        fake_primask = original_primask;
        if ((STM32_TB6612_HAL_Apply(NULL, &output) != HAL_ERROR) ||
            (event_count != 0U) ||
            !single_critical_section_restored(original_primask)) {
            return 0;
        }

        reset_fake_hal();
        fake_primask = original_primask;
        if ((STM32_TB6612_HAL_ForceSafe(NULL) != HAL_ERROR) ||
            (event_count != 0U) ||
            !single_critical_section_restored(original_primask)) {
            return 0;
        }
    }
    return 1;
}

static int test_init_restores_original_primask_on_all_outcomes(void)
{
    uint32_t original_primask;

    for (original_primask = 0U;
         original_primask <= 1U;
         ++original_primask) {
        Stm32Tb6612Hal adapter;
        Stm32Tb6612HalConfig config = valid_hal_config();

        memset(&adapter, 0, sizeof(adapter));
        reset_fake_hal();
        fake_primask = original_primask;
        if ((STM32_TB6612_HAL_Init(&adapter, &config) != HAL_OK) ||
            (event_count != 9U) || !safe_sequence_at(0U) ||
            !safe_sequence_at(5U) ||
            !single_critical_section_restored(original_primask)) {
            return 0;
        }

        memset(&adapter, 0, sizeof(adapter));
        config.max_active_ccr = config.pwm_full_scale_ccr + 1U;
        reset_fake_hal();
        fake_primask = original_primask;
        if ((STM32_TB6612_HAL_Init(&adapter, &config) != HAL_ERROR) ||
            (event_count != 4U) || !safe_sequence_at(0U) ||
            !single_critical_section_restored(original_primask)) {
            return 0;
        }

        config = valid_hal_config();
        memset(&adapter, 0, sizeof(adapter));
        reset_fake_hal();
        pwm_start_result = HAL_ERROR;
        fake_primask = original_primask;
        if ((STM32_TB6612_HAL_Init(&adapter, &config) != HAL_ERROR) ||
            (event_count != 9U) || !safe_sequence_at(0U) ||
            !safe_sequence_at(5U) ||
            !single_critical_section_restored(original_primask)) {
            return 0;
        }

        reset_fake_hal();
        fake_primask = original_primask;
        if ((STM32_TB6612_HAL_Init(NULL, &config) != HAL_ERROR) ||
            (event_count != 0U) ||
            !single_critical_section_restored(original_primask)) {
            return 0;
        }
    }
    return 1;
}

static int test_pending_force_safe_runs_only_after_active_apply_commit(void)
{
    uint32_t trigger;

    for (trigger = 1U; trigger <= 5U; ++trigger) {
        Stm32Tb6612Hal adapter;
        Tb6612Output output;
        uint32_t request_index;
        uint32_t restore_index;
        uint32_t handler_index;

        if (!initialize_adapter(&adapter)) {
            return 0;
        }
        memset(&output, 0, sizeof(output));
        output.ccr = 320U;
        output.direction = 1;
        output.ain1 = 1U;
        output.ain2 = 0U;
        output.stby = 1U;
        reset_fake_hal();
        arm_operation_after_hardware_event(
            trigger, PENDING_OPERATION_FORCE_SAFE, &adapter, NULL);
        if ((STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) ||
            (event_count != 9U) || !active_sequence_at(0U, 320U) ||
            !safe_sequence_at(5U) ||
            (pending_service_count != 1U) ||
            (pending_status != HAL_OK) ||
            (fake_primask != 0U) ||
            (adapter.initialized != 1U) ||
            (adapter.last_active_direction != 0)) {
            return 0;
        }

        request_index = find_irq_event(IRQ_EVENT_REQUEST, 0U);
        restore_index = find_irq_event(IRQ_EVENT_RESTORE_PRIMASK,
                                       request_index + 1U);
        handler_index = find_irq_event(IRQ_EVENT_HANDLER_ENTER,
                                       request_index + 1U);
        if ((request_index == UINT32_MAX) ||
            (restore_index == UINT32_MAX) ||
            (handler_index == UINT32_MAX) ||
            (request_index >= restore_index) ||
            (restore_index >= handler_index)) {
            return 0;
        }
    }
    return 1;
}

static int test_reverse_pending_apply_is_linearized_after_safe_operation(void)
{
    Stm32Tb6612Hal adapter;
    Stm32Tb6612HalConfig invalid_config;
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
    reset_fake_hal();
    if (STM32_TB6612_HAL_Apply(&adapter, &output) != HAL_OK) {
        return 0;
    }

    reset_fake_hal();
    arm_operation_after_hardware_event(
        4U, PENDING_OPERATION_APPLY, &adapter, &output);
    if ((STM32_TB6612_HAL_ForceSafe(&adapter) != HAL_OK) ||
        (event_count != 9U) || !safe_sequence_at(0U) ||
        !active_sequence_at(4U, 320U) ||
        (pending_service_count != 1U) ||
        (pending_status != HAL_OK) ||
        (adapter.last_active_direction != 1) ||
        (fake_primask != 0U)) {
        return 0;
    }

    /*
     * Invalid re-Init is a latching operation.  A pending ACTIVE Apply is
     * delayed until Init restores PRIMASK, then rejected and forced safe.
     */
    invalid_config = valid_hal_config();
    invalid_config.max_active_ccr =
        invalid_config.pwm_full_scale_ccr + 1U;
    reset_fake_hal();
    arm_operation_after_hardware_event(
        4U, PENDING_OPERATION_APPLY, &adapter, &output);
    if ((STM32_TB6612_HAL_Init(&adapter, &invalid_config) != HAL_ERROR) ||
        (event_count != 8U) || !safe_sequence_at(0U) ||
        !safe_sequence_at(4U) ||
        (pending_service_count != 1U) ||
        (pending_status != HAL_ERROR) ||
        (adapter.initialized != 0U) ||
        (adapter.last_active_direction != 0) ||
        (fake_primask != 0U)) {
        return 0;
    }
    return 1;
}

int main(void)
{
    int pass = 1;

#define RUN_TEST(test_function) do {                                      \
        int test_passed = (test_function)();                              \
        if (!test_passed) {                                               \
            printf("FAIL: %s\n", #test_function);                        \
        }                                                                 \
        pass &= test_passed;                                              \
    } while (0)

    RUN_TEST(test_init_and_timer_contract);
    RUN_TEST(test_active_and_safe_apply_order);
    RUN_TEST(test_malformed_and_mutated_state_force_safe);
    RUN_TEST(test_direction_polarity_and_transition_guard);
    RUN_TEST(test_runtime_state_corruption_latches_safe);
    RUN_TEST(test_force_safe_does_not_reauthorize_corruption);
    RUN_TEST(test_integer_active_cap_is_independent_fail_closed_limit);
    RUN_TEST(test_config_snapshot_integrity_precedes_pointer_use);
    RUN_TEST(test_mutated_timer_instance_uses_gpio_only_safe_path);
    RUN_TEST(test_corrupt_lifecycle_never_blocks_safe_attempt);
    RUN_TEST(test_reinit_safes_live_adapter_before_validation);
    RUN_TEST(test_primask_restore_on_apply_and_force_safe_paths);
    RUN_TEST(test_init_restores_original_primask_on_all_outcomes);
    RUN_TEST(test_pending_force_safe_runs_only_after_active_apply_commit);
    RUN_TEST(test_reverse_pending_apply_is_linearized_after_safe_operation);

#undef RUN_TEST

    printf("STM32 TB6612 HAL ordering with fake HAL: %s\n",
           pass ? "PASS" : "FAIL");
    return pass ? 0 : 1;
}
