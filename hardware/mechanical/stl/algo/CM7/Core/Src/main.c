/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
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

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include <stdint.h>

#include "C:/Users/banny/STM32CubeIDE/workspace_1.7.0/algo/CM7/Core/Algo/bmflc/BMFLC_step.h"
#include "C:/Users/banny/STM32CubeIDE/workspace_1.7.0/algo/CM7/Core/Algo/ehwflc/eHWFLC_KF_step.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

typedef enum
{
  MOTOR_STOP = 0,
  MOTOR_FORWARD,
  MOTOR_REVERSE
} MotorState;

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

#ifndef HSEM_ID_0
#define HSEM_ID_0 (0U) /* HW semaphore 0*/
#endif

#define MOTOR_THRESHOLD 5.0f
#define MOTOR_GAIN      1.0f

/* BNO055 raw gyro 設 ?  ? HAL 使用 8-bit I2C address， ? ? 0x28 要左 ? 1 bit */
#define BNO055_ADDR            (0x28 << 1)
#define BNO055_PAGE_ID         0x07
#define BNO055_OPR_MODE        0x3D
#define BNO055_GYR_DATA_X_LSB  0x14
#define BNO055_MODE_CONFIG     0x00
#define BNO055_MODE_GYROONLY   0x03

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

I2C_HandleTypeDef hi2c4;
TIM_HandleTypeDef htim6;

/* USER CODE BEGIN PV */

/*
 * ?  ?  ?  ? 數之 ? 可以改??? BNO055  ??  ??  ? 實?  ??
 * ?  ??  ? 用??  ?  ? 測試 ?  ?  ??
 */
float gyroX = 0;
float gyroY = 0;
float gyroZ = 0;

/*
 * 演 ?  ? 輸?  結 ??
 * tremorEstimate：估測 ? 顫???
 * freqEstimate：估測 ? 顫?  ???
 */
double tremorEstimate = 0.0;
double freqEstimate = 0.0;

/*
 *  ? 6 步 ? TIM6 100 Hz 中斷?  負責 ? flag
 *  ? 7 步 ? DWT  ???? eHWFLC_KF_step() ?  次 ?  ?  ?  ??
 */
volatile uint8_t tick_flag = 0;
uint32_t algo_cycles = 0;
float algo_time_us = 0.0f;

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_I2C4_Init(void);
static void MX_TIM6_Init(void);
/* USER CODE BEGIN PFP */

void Motor_Control(MotorState state);
void Algorithm_Init(void);
MotorState Tremor_Algorithm(float gyroX, float gyroY, float gyroZ);
void Read_IMU_TestData(float *gx, float *gy, float *gz);
void Read_IMU_RealData(float *gx, float *gy, float *gz);

void BNO055_GyroOnly_Init(I2C_HandleTypeDef *h);
double BNO055_Read_GyroX_DPS(I2C_HandleTypeDef *h);
void DWT_Init(void);

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/**
  * @brief ?? 用 DWT Cycle Counter，用來 ? 測演 ?  ? 單步 ?  ?  ??
  */
void DWT_Init(void)
{
  CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
  DWT->CYCCNT = 0;
  DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
}

/**
  * @brief  ? BNO055 ?? 到 GYROONLY 模 ?  ? 只 ? raw gyro??
  * @note  ? 是第 ? 步??要 ?  ?  ?  ?  ?  ?  ?  ?  ? 單軸 ?  ? 度 deg/s， ? 是 Euler/Quaternion??
  */
void BNO055_GyroOnly_Init(I2C_HandleTypeDef *h)
{
  uint8_t v;

  /* ??  ?? CONFIGMODE */
  v = BNO055_MODE_CONFIG;
  HAL_I2C_Mem_Write(h, BNO055_ADDR, BNO055_OPR_MODE, 1, &v, 1, 30);
  HAL_Delay(25);

  /* 確 ? 在 page 0 */
  v = 0x00;
  HAL_I2C_Mem_Write(h, BNO055_ADDR, BNO055_PAGE_ID, 1, &v, 1, 30);
  HAL_Delay(5);

  /* ?? 到 GYROONLY mode */
  v = BNO055_MODE_GYROONLY;
  HAL_I2C_Mem_Write(h, BNO055_ADDR, BNO055_OPR_MODE, 1, &v, 1, 30);
  HAL_Delay(30);
}

/**
  * @brief  ???? BNO055 X  ? gyro，單位為 deg/s??
  * @note  BNO055 gyro ?? 設比 ? 是 16 LSB = 1 deg/s， ? ? raw  ?定 ? 除 ? 16??
  */
double BNO055_Read_GyroX_DPS(I2C_HandleTypeDef *h)
{
  uint8_t b[6];
  int16_t raw;

  HAL_I2C_Mem_Read(h, BNO055_ADDR, BNO055_GYR_DATA_X_LSB, 1, b, 6, 20);

  raw = (int16_t)((b[1] << 8) | b[0]);

  return raw / 16.0;
}


/**
  * @brief 馬 ? 控?  ?   ?
  * @param state MOTOR_FORWARD / MOTOR_REVERSE / MOTOR_STOP
  * @retval None
  */
void Motor_Control(MotorState state)
{
  if (state == MOTOR_FORWARD)
  {
    /*
     *  ? ?
     * AIN1 = 1
     * AIN2 = 0
     */
    HAL_GPIO_WritePin(GPIOG, GPIO_PIN_3, GPIO_PIN_SET);
    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_6, GPIO_PIN_RESET);
  }
  else if (state == MOTOR_REVERSE)
  {
    /*
     * ??  ??
     * AIN1 = 0
     * AIN2 = 1
     */
    HAL_GPIO_WritePin(GPIOG, GPIO_PIN_3, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_6, GPIO_PIN_SET);
  }
  else
  {
    /*
     * ?? 止
     * AIN1 = 0
     * AIN2 = 0
     */
    HAL_GPIO_WritePin(GPIOG, GPIO_PIN_3, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_6, GPIO_PIN_RESET);
  }
}
void Algorithm_Init(void)
{
  /*
   * ??  ?  ?? eHWFLC 演 ?  ??
   * 你 ?  ?  ?  ?  ? 頭檔內實 ? 函式 ? 稱?   eHWFLC_KF_step_init()
   */
  eHWFLC_KF_step_init();

  /*
   * 如 ?  ?  ?  ? 改?   BMFLC，可以改??  ??
   * BMFLC_step_initialize();
   */
}

MotorState Tremor_Algorithm(float gyroX, float gyroY, float gyroZ)
{
  double inputGyro;
  double controlValue;
  uint32_t t0;

  /*
   * ?  ??  ? 使?   X  ? gyro ?  作 ?  ?  ? 輸?
   * ?  位 ? 該?   deg/s， ? 就?   BNO055 raw value ?   ? 16 後 ?  ?  ??
   */
  inputGyro = (double)gyroX;

  /*
   *  ? 7 步 ? 用 DWT ?? 測 eHWFLC_KF_step() ?  次 ?  ?  ?  ??
   */
  t0 = DWT->CYCCNT;

  eHWFLC_KF_step(inputGyro, &tremorEstimate, &freqEstimate);

  algo_cycles = DWT->CYCCNT - t0;
  algo_time_us = (float)algo_cycles / ((float)SystemCoreClock / 1000000.0f);

  /*
   * ?? 相補 ??
   * tremorEstimate ?  演 ?  ? 估測出??  ? 顫???
   * 馬 ?  ?  ??? 方??  ?  ?  ?  ?以 ?  ?  ?  ??
   */
  controlValue = -(MOTOR_GAIN * tremorEstimate);

  if (controlValue > MOTOR_THRESHOLD)
  {
    /*
     * ?  ?  ?? 為 ?，馬?? 正 ?
     */
    return MOTOR_FORWARD;
  }
  else if (controlValue < -MOTOR_THRESHOLD)
  {
    /*
     * ?  ?  ?? 為負 ? 馬??  ?  ??
     */
    return MOTOR_REVERSE;
  }
  else
  {
    /*
     * ?  ?  ?? 太小 ? 馬??  ? 止
     */
    return MOTOR_STOP;
  }
}
/**
  * @brief 測試?   IMU ??  ?  ??
  * @param gx gyroX
  * @param gy gyroY
  * @param gz gyroZ
  * @retval None
  */
void Read_IMU_TestData(float *gx, float *gy, float *gz)
{
  /*
   * ? 裡?  測試資 ??
   * 每次?  ?  ??  ?  ? 產??  ??
   * 80   ??? 模擬 ??  ??  ?  ??
   * 10   ??? 模擬??  ?  ?  ? 顯
   * -80  ??? 模擬?? 方??  ?  ??
   * 0    ??? 模擬?? 止
   */
  static int testStep = 0;

  if (testStep == 0)
  {
    *gx = 80;
    *gy = 0;
    *gz = 0;
  }
  else if (testStep == 1)
  {
    *gx = 10;
    *gy = 0;
    *gz = 0;
  }
  else if (testStep == 2)
  {
    *gx = -80;
    *gy = 0;
    *gz = 0;
  }
  else
  {
    *gx = 0;
    *gy = 0;
    *gz = 0;
  }

  testStep++;

  if (testStep >= 4)
  {
    testStep = 0;
  }
}

/**
  * @brief ?? 實 IMU  ???  ? 架
  * @param gx gyroX
  * @param gy gyroY
  * @param gz gyroZ
  * @retval None
  */
void Read_IMU_RealData(float *gx, float *gy, float *gz)
{
  /*
   * 第 ? 步：餵 ? BNO055 raw gyro??
   * ?  ??  ? 使?   X 軸 ? 單位是 deg/s??
   * 如 ?  ?  ?  ? 改 Y/Z 軸 ? 可?   BNO055_Read_GyroX_DPS() ?  ?   ?對 ?  ?  ?  ?  ??
   */
  *gx = (float)BNO055_Read_GyroX_DPS(&hi2c4);
  *gy = 0.0f;
  *gz = 0.0f;
}

/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{
  /* USER CODE BEGIN 1 */

  MotorState motorState;

  /* USER CODE END 1 */
/* USER CODE BEGIN Boot_Mode_Sequence_0 */
  int32_t timeout;
/* USER CODE END Boot_Mode_Sequence_0 */

/* USER CODE BEGIN Boot_Mode_Sequence_1 */
  /* Wait until CPU2 boots and enters in stop mode or timeout*/
  timeout = 0xFFFF;
  while((__HAL_RCC_GET_FLAG(RCC_FLAG_D2CKRDY) != RESET) && (timeout-- > 0));
  if (timeout < 0)
  {
    Error_Handler();
  }
/* USER CODE END Boot_Mode_Sequence_1 */
  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();
/* USER CODE BEGIN Boot_Mode_Sequence_2 */

  /*
   * When system initialization is finished,
   * Cortex-M7 will release Cortex-M4 by means of HSEM notification
   */

  /* HW semaphore Clock enable */
  __HAL_RCC_HSEM_CLK_ENABLE();

  /* Take HSEM */
  HAL_HSEM_FastTake(HSEM_ID_0);

  /* Release HSEM in order to notify the CPU2(CM4) */
  HAL_HSEM_Release(HSEM_ID_0, 0);

  /* wait until CPU2 wakes up from stop mode */
  timeout = 0xFFFF;
  while((__HAL_RCC_GET_FLAG(RCC_FLAG_D2CKRDY) == RESET) && (timeout-- > 0));

  if (timeout < 0)
  {
    Error_Handler();
  }

/* USER CODE END Boot_Mode_Sequence_2 */

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_I2C4_Init();
  MX_TIM6_Init();
  /* USER CODE BEGIN 2 */
  /*
   * ??  ?  ?  ?  ? 止馬 ??
   * ?  ??  ?上電馬 ? 誤??  ??
   */
  Motor_Control(MOTOR_STOP);

  /*
   * ??  ?  ?  ?  ?  ??
   */
  Algorithm_Init();

  /*
   * ??  ?  ?? BNO055， ? 到 GYROONLY， ?  ? 輸?   raw gyro deg/s
   */
  BNO055_GyroOnly_Init(&hi2c4);

  /*
   *  ? 7 步 ?  ? 用 DWT 計 ??
   */
  DWT_Init();

  /*
   *  ? 6 步 ?  ?  ?? TIM6 100 Hz 中斷
   */
  HAL_TIM_Base_Start_IT(&htim6);

  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    /*
     *  ? 6 步 ??
     * TIM6  ? 10 ms ?  ?次中?  ， ? 中?  ?  ?  設 ?? tick_flag??
     * ?? 正??? I2C  ???  ?  ?  ?  ?  ? 馬?? 控?  ?  ?  ?  主迴??  ? 避??? ISR ?  塞 ??
     */
    if (tick_flag)
    {
      tick_flag = 0;

      /*
       * 100 Hz： ???? BNO055 ?? 實 gyro 資 ??
       */
      Read_IMU_RealData(&gyroX, &gyroY, &gyroZ);

      /*
       * ?  ?  演 ?  ?  ??
       * Tremor_Algorithm() ?  ?  ?? 用 DWT ?? 測 eHWFLC_KF_step() ?  ?  ??
       */
      motorState = Tremor_Algorithm(gyroX, gyroY, gyroZ);

      /*
       * ?  ??  ?  ?  ?  ?  ? 控?  馬 ??
       */
      Motor_Control(motorState);
    }

    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
  }
  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  /** Supply configuration update enable
  */
  HAL_PWREx_ConfigSupply(PWR_DIRECT_SMPS_SUPPLY);
  /** Configure the main internal regulator output voltage
  */
  __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE2);

  while(!__HAL_PWR_GET_FLAG(PWR_FLAG_VOSRDY)) {}
  /** Macro to configure the PLL clock source
  */
  __HAL_RCC_PLL_PLLSOURCE_CONFIG(RCC_PLLSOURCE_HSE);
  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSI|RCC_OSCILLATORTYPE_HSE;
  RCC_OscInitStruct.HSEState = RCC_HSE_BYPASS;
  RCC_OscInitStruct.HSIState = RCC_HSI_DIV1;
  RCC_OscInitStruct.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSE;
  RCC_OscInitStruct.PLL.PLLM = 23;
  RCC_OscInitStruct.PLL.PLLN = 177;
  RCC_OscInitStruct.PLL.PLLP = 2;
  RCC_OscInitStruct.PLL.PLLQ = 4;
  RCC_OscInitStruct.PLL.PLLR = 4;
  RCC_OscInitStruct.PLL.PLLRGE = RCC_PLL1VCIRANGE_0;
  RCC_OscInitStruct.PLL.PLLVCOSEL = RCC_PLL1VCOWIDE;
  RCC_OscInitStruct.PLL.PLLFRACN = 0;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }
  /** Initializes the CPU, AHB and APB buses clocks
  */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2
                              |RCC_CLOCKTYPE_D3PCLK1|RCC_CLOCKTYPE_D1PCLK1;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_HSI;
  RCC_ClkInitStruct.SYSCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_HCLK_DIV1;
  RCC_ClkInitStruct.APB3CLKDivider = RCC_APB3_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_APB1_DIV1;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_APB2_DIV1;
  RCC_ClkInitStruct.APB4CLKDivider = RCC_APB4_DIV1;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_1) != HAL_OK)
  {
    Error_Handler();
  }
}


/**
  * @brief I2C4 Initialization Function
  * @param None
  * @retval None
  */
static void MX_I2C4_Init(void)
{

  /* USER CODE BEGIN I2C4_Init 0 */

  /* USER CODE END I2C4_Init 0 */

  /* USER CODE BEGIN I2C4_Init 1 */

  /* USER CODE END I2C4_Init 1 */
  hi2c4.Instance = I2C4;
  hi2c4.Init.Timing = 0x10707DBC;
  hi2c4.Init.OwnAddress1 = 0;
  hi2c4.Init.AddressingMode = I2C_ADDRESSINGMODE_7BIT;
  hi2c4.Init.DualAddressMode = I2C_DUALADDRESS_DISABLE;
  hi2c4.Init.OwnAddress2 = 0;
  hi2c4.Init.OwnAddress2Masks = I2C_OA2_NOMASK;
  hi2c4.Init.GeneralCallMode = I2C_GENERALCALL_DISABLE;
  hi2c4.Init.NoStretchMode = I2C_NOSTRETCH_DISABLE;

  if (HAL_I2C_Init(&hi2c4) != HAL_OK)
  {
    Error_Handler();
  }

  if (HAL_I2CEx_ConfigAnalogFilter(&hi2c4, I2C_ANALOGFILTER_ENABLE) != HAL_OK)
  {
    Error_Handler();
  }

  if (HAL_I2CEx_ConfigDigitalFilter(&hi2c4, 0) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN I2C4_Init 2 */

  /* USER CODE END I2C4_Init 2 */

}

/**
  * @brief TIM6 Initialization Function
  * @param None
  * @retval None
  */
static void MX_TIM6_Init(void)
{

  /* USER CODE BEGIN TIM6_Init 0 */

  /* USER CODE END TIM6_Init 0 */

  TIM_MasterConfigTypeDef sMasterConfig = {0};

  /* USER CODE BEGIN TIM6_Init 1 */

  /* USER CODE END TIM6_Init 1 */
  htim6.Instance = TIM6;
  htim6.Init.Prescaler = 6399;
  htim6.Init.CounterMode = TIM_COUNTERMODE_UP;
  htim6.Init.Period = 99;
  htim6.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_DISABLE;
  if (HAL_TIM_Base_Init(&htim6) != HAL_OK)
  {
    Error_Handler();
  }
  sMasterConfig.MasterOutputTrigger = TIM_TRGO_RESET;
  sMasterConfig.MasterSlaveMode = TIM_MASTERSLAVEMODE_DISABLE;
  if (HAL_TIMEx_MasterConfigSynchronization(&htim6, &sMasterConfig) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN TIM6_Init 2 */

  /* USER CODE END TIM6_Init 2 */

}

/**
  * @brief GPIO Initialization Function
  * @param None
  * @retval None
  */
static void MX_GPIO_Init(void)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};

  /* GPIO Ports Clock Enable */
  __HAL_RCC_GPIOC_CLK_ENABLE();
  __HAL_RCC_GPIOH_CLK_ENABLE();
  __HAL_RCC_GPIOG_CLK_ENABLE();
  __HAL_RCC_GPIOA_CLK_ENABLE();

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOG, GPIO_PIN_3, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(GPIOA, GPIO_PIN_6, GPIO_PIN_RESET);

  /*Configure GPIO pin : PG3 */
  GPIO_InitStruct.Pin = GPIO_PIN_3;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOG, &GPIO_InitStruct);

  /*Configure GPIO pin : PA6 */
  GPIO_InitStruct.Pin = GPIO_PIN_6;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

}

/* USER CODE BEGIN 4 */

/**
  * @brief TIM6 100 Hz 中斷 callback??
  * @note  ISR 裡只 ? flag， ?  ? I2C?  ?  ?  ?  ?  ?  ? 避?? 阻塞 ??
  */
void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
  if (htim->Instance == TIM6)
  {
    tick_flag = 1;
  }
}

/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */

  __disable_irq();

  while (1)
  {
  }

  /* USER CODE END Error_Handler_Debug */
}

#ifdef  USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */

  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */

/************************ (C) COPYRIGHT STMicroelectronics *****END OF FILE****/
