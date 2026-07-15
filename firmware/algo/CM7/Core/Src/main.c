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
#include "BNO055_STM32.h"

/* 保留原本已經可以編譯的演算法 include，不修改演算法檔案 */
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

/* BNO055 位址、暫存器、模式與型別由 BNO055_STM32.h 提供 */

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

I2C_HandleTypeDef hi2c4;
TIM_HandleTypeDef htim6;

/* USER CODE BEGIN PV */

/* BNO055_STM32.c 的 ReadData() 會將資料寫入此結構 */
BNO055_Sensors_t BNO055_Data = {0};


/* BNO055 三軸陀螺儀資料，單位為 degree/second */
float gyroX = 0.0f;
float gyroY = 0.0f;
float gyroZ = 0.0f;


/* eHWFLC 演算法輸出 */
double tremorEstimate = 0.0;
double freqEstimate = 0.0;


/* TIM6 每 10 ms 設定一次旗標；ISR 內不執行 I2C */
volatile uint8_t tick_flag = 0;
uint32_t algo_cycles = 0;
float algo_time_us = 0.0f;

/* 除錯狀態：可加入 Live Expressions / Expressions 觀察 */
volatile uint32_t tim6_irq_count = 0;
/* 已確認 TIM6 IRQ 正常，因此不再使用軟體 10 ms 備援。
 * software_tick_count 保留給 Live Expressions 觀察，正常應一直是 0。
 */
volatile uint32_t software_tick_count = 0;
volatile uint32_t control_tick_count = 0;
volatile uint32_t imu_read_ok_count = 0;
volatile uint32_t imu_read_error_count = 0;
volatile uint32_t imu_consecutive_error_count = 0;
volatile uint32_t algo_call_count = 0;

volatile HAL_StatusTypeDef bno_init_status = HAL_ERROR;
volatile HAL_StatusTypeDef bno_read_status = HAL_ERROR;
volatile uint8_t bno_chip_id = 0;
volatile uint8_t bno_operation_mode = 0;
volatile uint8_t imu_ready = 0;
volatile uint8_t using_test_data = 0;

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
HAL_StatusTypeDef Read_IMU_RealData(float *gx, float *gy, float *gz);

HAL_StatusTypeDef Sensor_GyroOnly_Init(void);
void DWT_Init(void);

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/**
  * @brief 啟用 Cortex-M7 DWT cycle counter。
  */
void DWT_Init(void)
{
  CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
  DWT->CYCCNT = 0;
  DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
}

/**
  * @brief 呼叫原本 BNO055_STM32.c 的函式初始化 BNO055。
  * @note 演算法需要單軸 Gyro，單位為 degree/second，因此設定成
  *       GYRO_ONLY 與 UNIT_GYRO_DPS。這裡不呼叫 Calibrate_BNO055()，
  *       因為該函式會把感測器切換到 NDOF。
  */
HAL_StatusTypeDef Sensor_GyroOnly_Init(void)
{
  BNO055_Init_t init = {0};
  HAL_StatusTypeDef status;

  /*
   * 使用修正版 BNO055_STM32.c：ResetBNO055() 有逾時，
   * 不會因感測器未回應而永遠卡住。
   */
  status = ResetBNO055();
  if (status != HAL_OK)
  {
    return status;
  }

  init.ACC_Range    = Range_16G;
  init.Axis         = DEFAULT_AXIS_REMAP;
  init.Axis_sign    = DEFAULT_AXIS_SIGN;
  init.Clock_Source = CLOCK_EXTERNAL;
  init.Mode         = BNO055_NORMAL_MODE;
  init.OP_Modes     = GYRO_ONLY;
  init.Unit_Sel     = (UNIT_ORI_ANDROID |
                       UNIT_TEMP_CELCIUS |
                       UNIT_EUL_DEG |
                       UNIT_GYRO_DPS |
                       UNIT_ACC_MS2);

  /* 呼叫原本驅動檔內的初始化函式，不修改演算法。 */
  BNO055_Init(init);

  /* 讀回 Chip ID 與模式，確認初始化真的成功。 */
  status = HAL_I2C_Mem_Read(&hi2c4, P_BNO055, CHIP_ID_ADDR,
                            I2C_MEMADD_SIZE_8BIT,
                            (uint8_t *)&bno_chip_id, 1, 20);
  if ((status != HAL_OK) || (bno_chip_id != BNO055_ID))
  {
    return HAL_ERROR;
  }

  status = HAL_I2C_Mem_Read(&hi2c4, P_BNO055, OPR_MODE_ADDR,
                            I2C_MEMADD_SIZE_8BIT,
                            (uint8_t *)&bno_operation_mode, 1, 20);
  if ((status != HAL_OK) || (bno_operation_mode != GYRO_ONLY))
  {
    return HAL_ERROR;
  }

  return HAL_OK;
}


void Motor_Control(MotorState state)
{
  if (state == MOTOR_FORWARD)
  {

    HAL_GPIO_WritePin(GPIOG, GPIO_PIN_3, GPIO_PIN_SET);
    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_6, GPIO_PIN_RESET);
  }
  else if (state == MOTOR_REVERSE)
  {

    HAL_GPIO_WritePin(GPIOG, GPIO_PIN_3, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_6, GPIO_PIN_SET);
  }
  else
  {

    HAL_GPIO_WritePin(GPIOG, GPIO_PIN_3, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(GPIOA, GPIO_PIN_6, GPIO_PIN_RESET);
  }
}
void Algorithm_Init(void)
{
  /* 保留原本已相容的 eHWFLC 初始化，不修改演算法內容 */
  eHWFLC_KF_step_init();
}

MotorState Tremor_Algorithm(float gyroX, float gyroY, float gyroZ)
{
  double inputGyro;
  double controlValue;
  uint32_t t0;

  /* 演算法具有內部狀態，只餵單一 X 軸，輸入單位為 degree/second */
  inputGyro = (double)gyroX;


  t0 = DWT->CYCCNT;

  eHWFLC_KF_step(inputGyro, &tremorEstimate, &freqEstimate);

  algo_cycles = DWT->CYCCNT - t0;
  algo_time_us = (float)algo_cycles / ((float)SystemCoreClock / 1000000.0f);


  controlValue = -(MOTOR_GAIN * tremorEstimate);

  if (controlValue > MOTOR_THRESHOLD)
  {

    return MOTOR_FORWARD;
  }
  else if (controlValue < -MOTOR_THRESHOLD)
  {

    return MOTOR_REVERSE;
  }
  else
  {

    return MOTOR_STOP;
  }
}

void Read_IMU_TestData(float *gx, float *gy, float *gz)
{

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
  * @brief 呼叫 BNO055_STM32.c 的 ReadData() 讀取 Gyro。
  * @note ReadData() 已經將 raw Gyro 除以 16.0，X/Y/Z 已是 degree/second，
  *       此處不可再次除以 16。
  */
HAL_StatusTypeDef Read_IMU_RealData(float *gx, float *gy, float *gz)
{
  HAL_StatusTypeDef status;

  /* 呼叫修正版 BNO055_STM32.c 的 ReadData()，逾時為 20 ms。 */
  status = ReadData(&BNO055_Data, SENSOR_GYRO);

  if (status == HAL_OK)
  {
    /* ReadData() 已經做 raw / 16.0，單位是 degree/second。 */
    *gx = BNO055_Data.Gyro.X;
    *gy = BNO055_Data.Gyro.Y;
    *gz = BNO055_Data.Gyro.Z;
  }

  return status;
}

/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{
  /* USER CODE BEGIN 1 */

  MotorState motorState = MOTOR_STOP;

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

  Motor_Control(MOTOR_STOP);

  /* DWT 要在第一次演算法 step 前啟用。 */
  DWT_Init();

  /* 保留原本已相容的演算法初始化。 */
  Algorithm_Init();

  /*
   * 初始化原本的 BNO055 驅動。若失敗，不讓程式卡住，
   * 會自動切換到測試資料，方便先確認演算法與 100 Hz 流程。
   */
  bno_init_status = Sensor_GyroOnly_Init();
  if (bno_init_status == HAL_OK)
  {
    imu_ready = 1;
    using_test_data = 0;
  }
  else
  {
    imu_ready = 0;
    using_test_data = 1;
  }

  /* 啟動 TIM6。100 Hz 控制迴圈只由 TIM6 觸發，避免重複取樣。 */
  if (HAL_TIM_Base_Start_IT(&htim6) != HAL_OK)
  {
    Error_Handler();
  }


  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    /*
     * TIM6 每 10 ms 在中斷中把 tick_flag 設為 1。
     * I2C、演算法與馬達控制都放在主迴圈，不在 ISR 裡阻塞。
     */
    if (tick_flag)
    {
      tick_flag = 0;
      control_tick_count++;

      if (imu_ready)
      {
        bno_read_status = Read_IMU_RealData(&gyroX, &gyroY, &gyroZ);

        if (bno_read_status == HAL_OK)
        {
          imu_read_ok_count++;
          imu_consecutive_error_count = 0;
        }
        else
        {
          imu_read_error_count++;
          imu_consecutive_error_count++;

          /* 連續五次讀取失敗才切到測試資料。 */
          if (imu_consecutive_error_count >= 5U)
          {
            imu_ready = 0;
            using_test_data = 1;
          }
        }
      }

      /*
       * BNO055 初始化失敗或連續讀取失敗時，使用測試資料確認
       * TIM6 與演算法仍然正常；測試資料模式不允許馬達轉動。
       */
      if (!imu_ready)
      {
        Read_IMU_TestData(&gyroX, &gyroY, &gyroZ);
      }

      /* 演算法邏輯不變：只餵 X 軸，單位為 degree/second。 */
      motorState = Tremor_Algorithm(gyroX, gyroY, gyroZ);
      algo_call_count++;

      if (imu_ready && (bno_read_status == HAL_OK))
      {
        Motor_Control(motorState);
      }
      else
      {
        Motor_Control(MOTOR_STOP);
      }
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


void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
  if (htim->Instance == TIM6)
  {
    tim6_irq_count++;
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
