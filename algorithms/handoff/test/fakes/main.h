#ifndef TEST_FAKE_MAIN_H
#define TEST_FAKE_MAIN_H

#include "stm32h7xx_hal.h"

extern GPIO_TypeDef test_motor_ain1_port;
extern GPIO_TypeDef test_motor_ain2_port;
extern GPIO_TypeDef test_motor_stby_port;
extern GPIO_TypeDef test_encoder_a_port;
extern GPIO_TypeDef test_encoder_b_port;

#define MOTOR_AIN1_GPIO_Port (&test_motor_ain1_port)
#define MOTOR_AIN1_Pin UINT16_C(0x0008)
#define MOTOR_AIN2_GPIO_Port (&test_motor_ain2_port)
#define MOTOR_AIN2_Pin UINT16_C(0x0040)
#define MOTOR_STBY_GPIO_Port (&test_motor_stby_port)
#define MOTOR_STBY_Pin UINT16_C(0x0002)
#define ENCODER_A_GPIO_Port (&test_encoder_a_port)
#define ENCODER_A_Pin UINT16_C(0x0040)
#define ENCODER_B_GPIO_Port (&test_encoder_b_port)
#define ENCODER_B_Pin UINT16_C(0x0100)

#endif
