/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file    stm32h7xx_it.c
  * @brief   Interrupt Service Routines.
  ******************************************************************************
  * @attention
  *
  * <h2><center>&copy; Copyright (c) 2026 STMicroelectronics.
  * All rights reserved.</center></h2>
  *
  * This software component is licensed by ST under BSD 3-Clause license,
  * the "License"; You may not use this file except in compliance with the
  * License. You may obtain a copy of the License at:
  *                        opensource.org/licenses/BSD-3-Clause
  *
  ******************************************************************************
  */
/* USER CODE END Header */

/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "stm32h7xx_it.h"
/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN TD */

/* USER CODE END TD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

/*
 * 08/23 motor hardware mapping
 *
 * AIN1 -> PG3
 * AIN2 -> PA6
 * PWMA -> PA8 / TIM1_CH1
 * STBY -> PK1
 *
 * Critical-fault safe state:
 *
 * PWM  = 0
 * AIN1 = LOW
 * AIN2 = LOW
 * STBY = LOW
 */

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
/* USER CODE BEGIN PV */

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
/* USER CODE BEGIN PFP */

static void Motor_EmergencyForceSafe(void);

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/**
  * @brief Immediately force TB6612 and motor output into safe state.
  *
  * 08/23 fail-safe:
  *
  *   PK1 / STBY      = LOW
  *   PG3 / AIN1      = LOW
  *   PA6 / AIN2      = LOW
  *   TIM1_CH1 / PWMA = CCR1 = 0
  *
  * This routine intentionally avoids HAL calls where possible because
  * it can be executed from CPU fault handlers.
  */
static void Motor_EmergencyForceSafe(void)
{
  /*
   * Make sure GPIO peripheral clocks are available.
   */
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOG_CLK_ENABLE();
  __HAL_RCC_GPIOK_CLK_ENABLE();

  /*
   * Disable TB6612 first.
   *
   * PK1 -> STBY = LOW
   */
  GPIOK->BSRR =
      ((uint32_t)GPIO_PIN_1 << 16U);

  /*
   * PG3 -> AIN1 = LOW
   */
  GPIOG->BSRR =
      ((uint32_t)GPIO_PIN_3 << 16U);

  /*
   * PA6 -> AIN2 = LOW
   */
  GPIOA->BSRR =
      ((uint32_t)GPIO_PIN_6 << 16U);

  /*
   * TIM1_CH1 -> PWMA
   *
   * Only access TIM1 registers when its peripheral clock
   * is already enabled.
   *
   * We deliberately do not depend on htim1 here.
   */
  if (__HAL_RCC_TIM1_IS_CLK_ENABLED())
  {
    /*
     * PWM duty = 0.
     */
    TIM1->CCR1 = 0U;

    /*
     * Disable TIM1 CH1 output.
     */
    TIM1->CCER &= ~TIM_CCER_CC1E;

    /*
     * TIM1 is an advanced-control timer.
     * Disable Main Output Enable as an additional
     * hardware PWM shutdown.
     */
    TIM1->BDTR &= ~TIM_BDTR_MOE;
  }

  /*
   * Ensure all register writes complete before the
   * processor remains inside the fault handler.
   */
  __DSB();
  __ISB();
}

/* USER CODE END 0 */

/* External variables --------------------------------------------------------*/
extern TIM_HandleTypeDef htim6;
extern UART_HandleTypeDef huart1;
/* USER CODE BEGIN EV */

/* USER CODE END EV */

/******************************************************************************/
/*           Cortex Processor Interruption and Exception Handlers          */
/******************************************************************************/
/**
  * @brief This function handles Non maskable interrupt.
  */
void NMI_Handler(void)
{
  /* USER CODE BEGIN NonMaskableInt_IRQn 0 */

  /*
   * Critical fault -> motor OFF immediately.
   */
  __disable_irq();

  Motor_EmergencyForceSafe();

  /* USER CODE END NonMaskableInt_IRQn 0 */
  /* USER CODE BEGIN NonMaskableInt_IRQn 1 */

  while (1)
  {
    /*
     * Motor remains forced safe.
     */
  }

  /* USER CODE END NonMaskableInt_IRQn 1 */
}

/**
  * @brief This function handles Hard fault interrupt.
  */
void HardFault_Handler(void)
{
  /* USER CODE BEGIN HardFault_IRQn 0 */

  /*
   * Critical fault -> motor OFF immediately.
   */
  __disable_irq();

  Motor_EmergencyForceSafe();

  /* USER CODE END HardFault_IRQn 0 */
  while (1)
  {
    /* USER CODE BEGIN W1_HardFault_IRQn 0 */

    /*
     * Motor remains forced safe.
     */

    /* USER CODE END W1_HardFault_IRQn 0 */
  }
}

/**
  * @brief This function handles Memory management fault.
  */
void MemManage_Handler(void)
{
  /* USER CODE BEGIN MemoryManagement_IRQn 0 */

  /*
   * Critical fault -> motor OFF immediately.
   */
  __disable_irq();

  Motor_EmergencyForceSafe();

  /* USER CODE END MemoryManagement_IRQn 0 */
  while (1)
  {
    /* USER CODE BEGIN W1_MemoryManagement_IRQn 0 */

    /*
     * Motor remains forced safe.
     */

    /* USER CODE END W1_MemoryManagement_IRQn 0 */
  }
}

/**
  * @brief This function handles Pre-fetch fault, memory access fault.
  */
void BusFault_Handler(void)
{
  /* USER CODE BEGIN BusFault_IRQn 0 */

  /*
   * Critical fault -> motor OFF immediately.
   */
  __disable_irq();

  Motor_EmergencyForceSafe();

  /* USER CODE END BusFault_IRQn 0 */
  while (1)
  {
    /* USER CODE BEGIN W1_BusFault_IRQn 0 */

    /*
     * Motor remains forced safe.
     */

    /* USER CODE END W1_BusFault_IRQn 0 */
  }
}

/**
  * @brief This function handles Undefined instruction or illegal state.
  */
void UsageFault_Handler(void)
{
  /* USER CODE BEGIN UsageFault_IRQn 0 */

  /*
   * Critical fault -> motor OFF immediately.
   */
  __disable_irq();

  Motor_EmergencyForceSafe();

  /* USER CODE END UsageFault_IRQn 0 */
  while (1)
  {
    /* USER CODE BEGIN W1_UsageFault_IRQn 0 */

    /*
     * Motor remains forced safe.
     */

    /* USER CODE END W1_UsageFault_IRQn 0 */
  }
}

/**
  * @brief This function handles System service call via SWI instruction.
  */
void SVC_Handler(void)
{
  /* USER CODE BEGIN SVCall_IRQn 0 */

  /* USER CODE END SVCall_IRQn 0 */
  /* USER CODE BEGIN SVCall_IRQn 1 */

  /* USER CODE END SVCall_IRQn 1 */
}

/**
  * @brief This function handles Debug monitor.
  */
void DebugMon_Handler(void)
{
  /* USER CODE BEGIN DebugMonitor_IRQn 0 */

  /* USER CODE END DebugMonitor_IRQn 0 */
  /* USER CODE BEGIN DebugMonitor_IRQn 1 */

  /* USER CODE END DebugMonitor_IRQn 1 */
}

/**
  * @brief This function handles Pendable request for system service.
  */
void PendSV_Handler(void)
{
  /* USER CODE BEGIN PendSV_IRQn 0 */

  /* USER CODE END PendSV_IRQn 0 */
  /* USER CODE BEGIN PendSV_IRQn 1 */

  /* USER CODE END PendSV_IRQn 1 */
}

/**
  * @brief This function handles System tick timer.
  */
void SysTick_Handler(void)
{
  /* USER CODE BEGIN SysTick_IRQn 0 */

  /* USER CODE END SysTick_IRQn 0 */
  HAL_IncTick();
  /* USER CODE BEGIN SysTick_IRQn 1 */

  /* USER CODE END SysTick_IRQn 1 */
}

/******************************************************************************/
/* STM32H7xx Peripheral Interrupt Handlers                                    */
/* Add here the Interrupt Handlers for the used peripherals.                  */
/* For the available peripheral interrupt handler names,                      */
/* please refer to the startup file (startup_stm32h7xx.s).                    */
/******************************************************************************/

/**
  * @brief This function handles EXTI line[9:5] interrupts.
  */
void EXTI9_5_IRQHandler(void)
{
  /* USER CODE BEGIN EXTI9_5_IRQn 0 */

  /* USER CODE END EXTI9_5_IRQn 0 */
  HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_6);
  HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_8);
  /* USER CODE BEGIN EXTI9_5_IRQn 1 */

  /* USER CODE END EXTI9_5_IRQn 1 */
}

/**
  * @brief This function handles USART1 global interrupt.
  */
void USART1_IRQHandler(void)
{
  /* USER CODE BEGIN USART1_IRQn 0 */

  /* USER CODE END USART1_IRQn 0 */
  HAL_UART_IRQHandler(&huart1);
  /* USER CODE BEGIN USART1_IRQn 1 */

  /* USER CODE END USART1_IRQn 1 */
}

/**
  * @brief This function handles TIM6 global interrupt, DAC1_CH1 and DAC1_CH2 underrun error interrupts.
  */
void TIM6_DAC_IRQHandler(void)
{
  /* USER CODE BEGIN TIM6_DAC_IRQn 0 */

  /* USER CODE END TIM6_DAC_IRQn 0 */
  HAL_TIM_IRQHandler(&htim6);
  /* USER CODE BEGIN TIM6_DAC_IRQn 1 */

  /* USER CODE END TIM6_DAC_IRQn 1 */
}

/* USER CODE BEGIN 1 */

/* USER CODE END 1 */
/************************ (C) COPYRIGHT STMicroelectronics *****END OF FILE****/
