#ifndef TEST_FAKE_STM32H7XX_HAL_H
#define TEST_FAKE_STM32H7XX_HAL_H

#include <stdint.h>

typedef enum {
    HAL_OK = 0,
    HAL_ERROR = 1,
    HAL_BUSY = 2,
    HAL_TIMEOUT = 3
} HAL_StatusTypeDef;

typedef enum {
    GPIO_PIN_RESET = 0,
    GPIO_PIN_SET = 1
} GPIO_PinState;

typedef struct {
    uint32_t ARR;
} TIM_TypeDef;

typedef struct {
    TIM_TypeDef *Instance;
} TIM_HandleTypeDef;

typedef struct {
    uint32_t test_id;
} GPIO_TypeDef;

typedef int32_t IRQn_Type;

#define TIM_CHANNEL_1 UINT32_C(0x00000000)
#define TIM_CHANNEL_2 UINT32_C(0x00000004)
#define TIM_CHANNEL_3 UINT32_C(0x00000008)
#define TIM_CHANNEL_4 UINT32_C(0x0000000C)
#define EXTI9_5_IRQn ((IRQn_Type)23)

HAL_StatusTypeDef HAL_TIM_PWM_Start(TIM_HandleTypeDef *timer,
                                    uint32_t channel);
void HAL_GPIO_WritePin(GPIO_TypeDef *port,
                       uint16_t pin,
                       GPIO_PinState state);
GPIO_PinState HAL_GPIO_ReadPin(GPIO_TypeDef *port, uint16_t pin);
void HAL_NVIC_DisableIRQ(IRQn_Type interrupt_number);
void HAL_NVIC_EnableIRQ(IRQn_Type interrupt_number);
void FakeHal_SetCompare(TIM_HandleTypeDef *timer,
                        uint32_t channel,
                        uint32_t compare);
uint32_t FakeHal_GetCompare(TIM_HandleTypeDef *timer,
                           uint32_t channel);
void FakeHal_ClearExti(uint16_t pin);

#define __HAL_TIM_GET_AUTORELOAD(timer) ((timer)->Instance->ARR)
#define __HAL_TIM_SET_COMPARE(timer, channel, compare) \
    FakeHal_SetCompare((timer), (channel), (compare))
#define __HAL_TIM_GET_COMPARE(timer, channel) \
    FakeHal_GetCompare((timer), (channel))
#define __HAL_GPIO_EXTI_CLEAR_IT(pin) FakeHal_ClearExti((pin))

#endif
