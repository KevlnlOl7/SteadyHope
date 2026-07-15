/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file         stm32h7xx_hal_msp.c
  * @brief        This file provides code for the MSP Initialization
  *               and De-Initialization codes.
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2026 STMicroelectronics.
  * All rights reserved.
  *
  ******************************************************************************
  */
/* USER CODE END Header */

/* Includes ------------------------------------------------------------------*/
#include "main.h"

/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN TD */

/* USER CODE END TD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN Define */

/* USER CODE END Define */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN Macro */

/* USER CODE END Macro */

/* Private variables ---------------------------------------------------------*/
/* USER CODE BEGIN PV */

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* External functions --------------------------------------------------------*/
/* USER CODE BEGIN ExternalFunctions */

/* USER CODE END ExternalFunctions */

/* USER CODE BEGIN 0 */

/* USER CODE END 0 */

/**
  * Initializes the Global MSP.
  */
void HAL_MspInit(void)
{
  /* USER CODE BEGIN MspInit 0 */

  /* USER CODE END MspInit 0 */

  __HAL_RCC_SYSCFG_CLK_ENABLE();

  /* System interrupt init */

  /* USER CODE BEGIN MspInit 1 */

  /* USER CODE END MspInit 1 */
}

/**
  * @brief I2C MSP Initialization
  * @param hi2c I2C handle pointer
  * @retval None
  */
void HAL_I2C_MspInit(I2C_HandleTypeDef *hi2c)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};
  RCC_PeriphCLKInitTypeDef PeriphClkInitStruct = {0};

  if (hi2c->Instance == I2C4)
  {
    /* USER CODE BEGIN I2C4_MspInit 0 */

    /* USER CODE END I2C4_MspInit 0 */

    /*
     * 設定 I2C4 時脈來源
     */
    PeriphClkInitStruct.PeriphClockSelection = RCC_PERIPHCLK_I2C4;
    PeriphClkInitStruct.I2c4ClockSelection =
        RCC_I2C4CLKSOURCE_D3PCLK1;

    if (HAL_RCCEx_PeriphCLKConfig(&PeriphClkInitStruct) != HAL_OK)
    {
      Error_Handler();
    }

    /*
     * 啟用 GPIOD 時脈
     */
    __HAL_RCC_GPIOD_CLK_ENABLE();

    /*
     * STM32H745I-DISCO Arduino 接腳：
     *
     * D15 = PD12 = I2C4_SCL
     * D14 = PD13 = I2C4_SDA
     */
    GPIO_InitStruct.Pin =
        GPIO_PIN_12 |
        GPIO_PIN_13;

    GPIO_InitStruct.Mode = GPIO_MODE_AF_OD;

    /*
     * 如果 BNO055 模組已有上拉電阻，使用 GPIO_NOPULL。
     * 多數 BNO055 breakout board 已內建上拉。
     */
    GPIO_InitStruct.Pull = GPIO_NOPULL;

    GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_VERY_HIGH;
    GPIO_InitStruct.Alternate = GPIO_AF4_I2C4;

    HAL_GPIO_Init(GPIOD, &GPIO_InitStruct);

    /*
     * 啟用 I2C4 周邊時脈
     */
    __HAL_RCC_I2C4_CLK_ENABLE();

    /* USER CODE BEGIN I2C4_MspInit 1 */

    /* USER CODE END I2C4_MspInit 1 */
  }
}

/**
  * @brief I2C MSP De-Initialization
  * @param hi2c I2C handle pointer
  * @retval None
  */
void HAL_I2C_MspDeInit(I2C_HandleTypeDef *hi2c)
{
  if (hi2c->Instance == I2C4)
  {
    /* USER CODE BEGIN I2C4_MspDeInit 0 */

    /* USER CODE END I2C4_MspDeInit 0 */

    /*
     * 關閉 I2C4 周邊時脈
     */
    __HAL_RCC_I2C4_CLK_DISABLE();

    /*
     * 解除 PD12、PD13 設定
     */
    HAL_GPIO_DeInit(
        GPIOD,
        GPIO_PIN_12 |
        GPIO_PIN_13
    );

    /* USER CODE BEGIN I2C4_MspDeInit 1 */

    /* USER CODE END I2C4_MspDeInit 1 */
  }
}

/**
  * @brief TIM Base MSP Initialization
  * @param htim_base TIM Base handle pointer
  * @retval None
  */
void HAL_TIM_Base_MspInit(TIM_HandleTypeDef *htim_base)
{
  if (htim_base->Instance == TIM6)
  {
    /* USER CODE BEGIN TIM6_MspInit 0 */

    /* USER CODE END TIM6_MspInit 0 */

    /*
     * 啟用 TIM6 時脈
     */
    __HAL_RCC_TIM6_CLK_ENABLE();

    /*
     * 啟用 TIM6 中斷
     */
    HAL_NVIC_SetPriority(TIM6_DAC_IRQn, 0, 0);
    HAL_NVIC_EnableIRQ(TIM6_DAC_IRQn);

    /* USER CODE BEGIN TIM6_MspInit 1 */

    /* USER CODE END TIM6_MspInit 1 */
  }
}

/**
  * @brief TIM Base MSP De-Initialization
  * @param htim_base TIM Base handle pointer
  * @retval None
  */
void HAL_TIM_Base_MspDeInit(TIM_HandleTypeDef *htim_base)
{
  if (htim_base->Instance == TIM6)
  {
    /* USER CODE BEGIN TIM6_MspDeInit 0 */

    /* USER CODE END TIM6_MspDeInit 0 */

    /*
     * 關閉 TIM6 時脈
     */
    __HAL_RCC_TIM6_CLK_DISABLE();

    /*
     * 關閉 TIM6 中斷
     */
    HAL_NVIC_DisableIRQ(TIM6_DAC_IRQn);

    /* USER CODE BEGIN TIM6_MspDeInit 1 */

    /* USER CODE END TIM6_MspDeInit 1 */
  }
}

/* USER CODE BEGIN 1 */

/* USER CODE END 1 */

/************************ (C) COPYRIGHT STMicroelectronics *****END OF FILE****/
