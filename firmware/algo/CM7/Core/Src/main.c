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
#include <stdio.h>
#include <math.h>
#include "BNO055_STM32.h"
#include "tremor_gate.h"

/*  ? ?  ? ?   ? ? ?  以編 ? ?  ?  ?  ?? include ? ?  ??   ? ?  ?  ?  ?? */
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

/*
 * 線軸??  ?  ???  ??
 * IDLE       ? ?  ?  ?  ?  ??
 * PULLING   ?  定方?? ?   ?
 * HOLDING   ?? 止馬 ? 並維 ? ?  ??  ?  ?
 * RETURNING ?? ?  ?? ?   ? ? ?  ??  ??
 */
typedef enum
{
  ACTUATOR_IDLE = 0,
  ACTUATOR_PULLING,
  ACTUATOR_HOLDING,
  ACTUATOR_RETURNING
} ActuatorState;

/*
 * ?   ? ESP32-C3 ?? ?   ? 16-byte binary packet??
 * gyro_*_raw  ? ?? BNO055 ??  ? ?   ? ? raw / 16.0f = deg/s??
 */
#pragma pack(push, 1)
typedef struct
{
  uint32_t sequence;
  uint32_t sample_tick_ms;
  int16_t gyro_x_raw;
  int16_t gyro_y_raw;
  int16_t gyro_z_raw;
  uint8_t sensor_valid;
  uint8_t motor_enabled;
} TremorSample_t;
#pragma pack(pop)

typedef char TremorSample_t_must_be_16_bytes[
  (sizeof(TremorSample_t) == 16U) ? 1 : -1
];

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

#ifndef HSEM_ID_0
#define HSEM_ID_0 (0U) /* HW semaphore 0*/
#endif

/* ?? ?  ?   Live Expressions 顯示 ? ?  ?  ? ?  ?  ?  ?  ? ?  ?? ?  不拿 ? ? ?  ?  ?  ?  ?  ?  ?? */
#define MOTOR_GAIN                    1.0

/*
 * 線軸?  ??  ?  ?? ?   ? ? ?  線相??  ? ?  ?? ? ?  ?  ? ?  ?  ?  ???
 * MOTOR_PULL_DIRECTION：收 ? ?  ?  ? ?  ???
 * MOTOR_RELEASE_DIRECTION：放 ? ? ?  鬆方???
 */
#define MOTOR_PULL_DIRECTION          MOTOR_FORWARD
#define MOTOR_RELEASE_DIRECTION       MOTOR_REVERSE

/*
 * ??  ?  ?  ? 測試 ?  ?  ? ?   ? ?  ?  ? ?   ? 300 ms ? ?  ?  ? 失 ? 放 ? 300 ms??
 * ? ?  ?  ? ?  ?   bring-up  ? ?  ?  ?  ?  ?  ?  ?  ?  ?  ??   ? ?  ???  ?  ??? ?  ??  ???
 */
#define MOTOR_PULL_TIME_MS            2000U
#define MOTOR_RELEASE_TIME_MS         2000U

/*  ??? ?  ??  ?  ?  ?  ?  ?  ?  ? 100 ms ? ? ?   ? ?  ?  ??   HAL_Delay()?? */
#define MOTOR_REVERSE_DEADTIME_MS     100U

/* 100 Hz ?  ?  ?  ?? */
#define CONTROL_SAMPLE_RATE_HZ        100.0

/* USART1 -> ESP32-C3 binary stream ? ?  ?? TIM6 ?  ?  ?? 16 bytes?? */
#define TREMOR_UART_TIMEOUT_MS         5U

/*
 *  ? ?  ? ?  ?? ?  ?  ????  ? ?  ?  ?  定餵 ?? 軸 ?? ? ?  ??  ?  ? X/Y/Z??
 *  ? ?種方 ? ? 設維 ?? X  ? ? ?   ? ? 確 ? 主 ? ?  ? ?  ?? ?   Y ??? Z ?
 * ?  要改 TREMOR_INPUT_AXIS ? ?  ?要修?   ? ?  ?  ?  ?  ??
 */
#define TREMOR_AXIS_X                 0U
#define TREMOR_AXIS_Y                 1U
#define TREMOR_AXIS_Z                 2U
#define TREMOR_INPUT_AXIS             TREMOR_AXIS_X

/*
 * 測試??  ??? ?  標頻 ? ??3.0~7.0 Hz??
 * ??  ?  ?  ??   2.5~7.5 Hz ??  ? 寬 ?? ?  ?  ?  ? ?  ??  ?  ?  ?  ?  ???  ??
 */
#define TREMOR_FREQ_ON_MIN_HZ         3.0
#define TREMOR_FREQ_ON_MAX_HZ         8.0
#define TREMOR_FREQ_OFF_MIN_HZ        2.5
#define TREMOR_FREQ_OFF_MAX_HZ        8.5

/*
 * tremorEstimate ?  ??  ? ? ?  ? 波形 ?  ? ?  ?  ?   ? ?  ?? ? ? ?  ?? ? ??
 * ?? ?   ? ?  ?  ? ?  ??  ? ? 0 ? ? 此使?   RMS ??  ??  ?  ?? 顫強 ???
 */
#define TREMOR_RMS_ON_DPS             3.0
#define TREMOR_RMS_OFF_DPS            2.0
#define TREMOR_POWER_EMA_ALPHA        0.05

/*
 * 100 Hz  ? ??
 * 30  ?  = 條件?? ? ?  ?? 0.30  ? ?  ?  ? ?   ? ??
 * 150  ? = 條件?? ? ?  ? 1.50  ? ?  ?  ?  ?  ? ?   ? ??
 */
#define TREMOR_ON_CONFIRM_SAMPLES     30U
#define TREMOR_OFF_CONFIRM_SAMPLES    150U

/*  ? ?  ?  ?  ?  ?  ? ? 2  ? ?  ?  ? ?  ??  ?  ? ?  ?? ?  ??  ???  ?? */
#define ALGO_WARMUP_SAMPLES           200U

/* ?  上測 ? ?  ?  ??5 Hz?  ??? 20 degree/second */
#define TEST_TREMOR_FREQ_HZ           5.0
#define TEST_TREMOR_AMPLITUDE_DPS     20.0
#define PI_D                          3.14159265358979323846

/* BNO055  ? ?? ?  存器? 模 ?? ?  ? ?  ?   BNO055_STM32.h ??  ?? */

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

I2C_HandleTypeDef hi2c4;

TIM_HandleTypeDef htim6;

UART_HandleTypeDef huart1;
UART_HandleTypeDef huart3;

/* USER CODE BEGIN PV */

/* BNO055_STM32.c ??? ReadData() ??  ?  ?  ?  ??   ? ?  ?? */
BNO055_Sensors_t BNO055_Data = {0};


/* BNO055 三軸???  ?? ? ?  ? ?  位為 degree/second */
float gyroX = 0.0f;
float gyroY = 0.0f;
float gyroZ = 0.0f;

/* ??  ? ? BNO055 Gyro ??  ?  ?? int16_t ? ?? ESP32 binary packet 使用?? */
int16_t gyroXRaw = 0;
int16_t gyroYRaw = 0;
int16_t gyroZRaw = 0;

/* UART/?  輸除?  ????  ?? */
volatile HAL_StatusTypeDef imuUartStatus = HAL_OK;
volatile uint32_t imuSampleCount = 0U;
volatile uint32_t imuUartErrorCount = 0U;
volatile uint8_t motorEnabledForApp = 0U;

static uint32_t tremorSequence = 0U;
static uint32_t lastDebugTickMs = 0U;
static TremorSample_t lastTremorSample = {0};


/* eHWFLC  ? ?  ?  ??   */
double tremorEstimate = 0.0;
double freqEstimate = 0.0;

/* ??  ?  ?  ? ?  ?  ????  ? ?  ?  ?   Live Expressions  ? ? */
double selectedGyroInputDps = 0.0;
double tremorPowerEma = 0.0;
double tremorRmsDps = 0.0;
double controlValueDebug = 0.0;
volatile uint8_t tremor_active = 0;
volatile uint8_t frequency_gate_ok = 0;
volatile uint8_t amplitude_gate_ok = 0;
volatile uint16_t tremor_on_count = 0;
volatile uint16_t tremor_off_count = 0;
volatile uint32_t algo_warmup_count = 0;

/*
 * tremor_gate.c ?? ?  立頻帶判?  ??
 *  ? ?  ?上面??? eHWFLC/RMS ?  ?   ? ? ?  作為 ? ?  ?  ?  ?  ?  ???
 */
static TremorGate bandpass_tremor_gate;
static TremorGateConfig bandpass_tremor_gate_config;
volatile uint8_t bandpass_gate_enabled = 0;
volatile uint8_t suppression_start_allowed = 0;
volatile float bandpass_tremor_envelope = 0.0f;
volatile float bandpass_voluntary_envelope = 0.0f;
volatile float bandpass_tremor_ratio = 0.0f;
volatile uint16_t bandpass_on_count = 0;
volatile uint16_t bandpass_off_count = 0;

/*  ?次收 ? ?  ?  ?  ? ?   ? ?  ???  ?  ? ?  ?? ?   Live Expressions  ? ? ?? */
volatile ActuatorState actuator_state = ACTUATOR_IDLE;
volatile uint32_t actuator_state_started_ms = 0;
volatile uint32_t actuator_state_elapsed_ms = 0;
volatile uint32_t actuator_pull_count = 0;
volatile uint32_t actuator_return_count = 0;

/*
 *  ? ?  ?  ?  ?  ?????  ? ?  ?? ?   Live Expressions  ? ? ??
 * motor_last_drive_direction ??  ?  ?  ? ? ? ? ?  ?輸出??  ?  ? ?  ??  ??
 */
volatile MotorState motor_applied_state = MOTOR_STOP;
volatile MotorState motor_last_drive_direction = MOTOR_STOP;
volatile MotorState motor_pending_direction = MOTOR_STOP;
volatile uint8_t motor_reverse_wait_active = 0;
volatile uint32_t motor_stop_started_ms = 0;
volatile uint32_t motor_reverse_wait_elapsed_ms = 0;
volatile uint32_t motor_reverse_event_count = 0;


/* TIM6  ? 10 ms  ? ?  ? ? ?  ?  ? ISR ?  不執 ? I2C */
volatile uint8_t tick_flag = 0;
uint32_t algo_cycles = 0;
float algo_time_us = 0.0f;

/* ?  ?  ????  ? ?  ?? ?   Live Expressions / Expressions  ? ? */
volatile uint32_t tim6_irq_count = 0;
/* 已確 ? TIM6 IRQ  ? ? ?  ? 此 ?? ?  ??   ? ?? 10 ms ?? ?  ??
 * software_tick_count  ? ?  ? Live Expressions  ? ? ?  ? ? ?  ??  ?   0??
 */
volatile uint32_t software_tick_count = 0;
volatile uint32_t control_tick_count = 0;
volatile uint32_t imu_read_ok_count = 0;
volatile uint32_t imu_read_error_count = 0;
volatile uint32_t imu_consecutive_error_count = 0;
volatile uint32_t algo_call_count = 0;

volatile HAL_StatusTypeDef bno_init_status = HAL_ERROR;
volatile HAL_StatusTypeDef bno_read_status = HAL_ERROR;

/* BNO055 I2C address probe results:
 * HAL_OK    = 該 ?  ???  ? 置??  ??
 * HAL_ERROR = 該 ?  ?沒 ?  ? 置??  ??
 */
volatile HAL_StatusTypeDef bno_ready_28 = HAL_ERROR;
volatile HAL_StatusTypeDef bno_ready_29 = HAL_ERROR;
volatile uint8_t bno_detected_address = 0;

/* I2C4 bring-up diagnostics for Live Expressions */
volatile uint32_t i2c4_state_after_28 = 0U;
volatile uint32_t i2c4_error_after_28 = 0U;
volatile uint32_t i2c4_state_after_29 = 0U;
volatile uint32_t i2c4_error_after_29 = 0U;
volatile uint8_t i2c4_scl_level = 0U;
volatile uint8_t i2c4_sda_level = 0U;
volatile uint8_t bno_probe_chip_id = 0U;

volatile uint8_t bno_chip_id = 0;
volatile uint8_t bno_operation_mode = 0;
volatile uint8_t imu_ready = 0;
volatile uint8_t using_test_data = 0;

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_TIM6_Init(void);
static void MX_USART1_UART_Init(void);
static void MX_I2C4_Init(void);
static void MX_USART3_UART_Init(void);
/* USER CODE BEGIN PFP */

void Motor_Control(MotorState state);
void Motor_Deadtime_Reset(void);
void Motor_UpdateWithDeadtime(MotorState requestedState);
void Actuator_StateMachine_Reset(void);
void Actuator_StateMachine_Update(void);
void Algorithm_Init(void);
void Tremor_Gate_Reset(void);
void Tremor_Detector_Update(float gyroX, float gyroY, float gyroZ);
void Bandpass_TremorGate_Init(void);
void Bandpass_TremorGate_Reset(void);
void Bandpass_TremorGate_Update(double gyroDps);
void Read_IMU_TestData(float *gx, float *gy, float *gz);
HAL_StatusTypeDef Read_IMU_RealData(float *gx, float *gy, float *gz);

HAL_StatusTypeDef Sensor_GyroOnly_Init(void);
void I2C4_RecoverAndReInit(void);
void DWT_Init(void);
static void Tremor_TransmitCurrentSample(uint8_t sensorValid);
static void Tremor_PrintStatistics(void);

#ifdef __GNUC__
#define PUTCHAR_PROTOTYPE int __io_putchar(int ch)
#else
#define PUTCHAR_PROTOTYPE int fputc(int ch, FILE *f)
#endif

PUTCHAR_PROTOTYPE
{
  HAL_UART_Transmit(&huart3, (uint8_t *)&ch, 1, HAL_MAX_DELAY);
  return ch;
}

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/**
  * @brief  ? ?  ??? 100 Hz sample  ? 16-byte binary packet ?   ? ESP32-C3??
  * @note  USART1 ?? ?   binary ? ? ?  混入 printf/CSV，避?? ?  ?   ? ?  ? ?   ? ??
  */
static void Tremor_TransmitCurrentSample(uint8_t sensorValid)
{
  TremorSample_t sample = {0};

  sample.sequence = tremorSequence++;
  sample.sample_tick_ms = HAL_GetTick();

  if (sensorValid)
  {
    sample.gyro_x_raw = gyroXRaw;
    sample.gyro_y_raw = gyroYRaw;
    sample.gyro_z_raw = gyroZRaw;
    sample.sensor_valid = 1U;
  }
  else
  {
    sample.gyro_x_raw = 0;
    sample.gyro_y_raw = 0;
    sample.gyro_z_raw = 0;
    sample.sensor_valid = 0U;
  }

  /*
   * ?  ??? ?  ? ?  ??? H-bridge ?  ?  ??  ?  ??   ? ?  ???  ?  ??
   * ?   App ?  顯示?  ?  ??? ?  條件??  ?  ?  ?  ? ?   ? ?  ???  ??   ?
   * ?  ?  ??  ? motorEnabledForApp = suppression_start_allowed;
   */
  motorEnabledForApp =
      (motor_applied_state != MOTOR_STOP) ? 1U : 0U;

  sample.motor_enabled =
      (motorEnabledForApp != 0U) ? 1U : 0U;

  imuUartStatus = HAL_UART_Transmit(
      &huart1,
      (uint8_t *)&sample,
      (uint16_t)sizeof(sample),
      TREMOR_UART_TIMEOUT_MS
  );

  if (imuUartStatus != HAL_OK)
  {
    imuUartErrorCount++;
  }

  lastTremorSample = sample;
  imuSampleCount++;
}

/**
  * @brief  ? ?  ? ?   ?次整??  ??? ?   USART3/ST-LINK??
  * @note  ?? 設主 ???  ? ?  ?   ? ?要除?  ??  ?  ?  ?  ??
  */
static void Tremor_PrintStatistics(void)
{
  uint32_t nowMs = HAL_GetTick();

  if ((uint32_t)(nowMs - lastDebugTickMs) < 1000U)
  {
    return;
  }

  lastDebugTickMs = nowMs;

  printf(
      "Tremor: samples=%lu seq=%lu tick=%lu "
      "raw=(%d,%d,%d) valid=%u motor=%u "
      "uartErr=%lu size=%u\r\n",
      (unsigned long)imuSampleCount,
      (unsigned long)lastTremorSample.sequence,
      (unsigned long)lastTremorSample.sample_tick_ms,
      (int)lastTremorSample.gyro_x_raw,
      (int)lastTremorSample.gyro_y_raw,
      (int)lastTremorSample.gyro_z_raw,
      (unsigned int)lastTremorSample.sensor_valid,
      (unsigned int)lastTremorSample.motor_enabled,
      (unsigned long)imuUartErrorCount,
      (unsigned int)sizeof(TremorSample_t)
  );
}

/**
  * @brief ?? ?   Cortex-M7 DWT cycle counter??
  */
void DWT_Init(void)
{
  CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
  DWT->CYCCNT = 0;
  DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
}

/**
  * @brief ?  ?  ?? ?   BNO055_STM32.c ?? ?   ? ?  ?  ?? BNO055??
  * @note  ? ?  ?  ?要單 ? Gyro，單位為 degree/second ? ? 此設 ?  ??
  *       GYRO_ONLY ??? UNIT_GYRO_DPS?  ? 裡 ? 呼?   Calibrate_BNO055() ?
  *       ?? ?  該函 ? ?  ?  ?  ??  ??  ? ?   NDOF??
  */
/**
  * @brief Reset and re-initialize I2C4 between address probes.
  * @note  This is only used during startup bring-up diagnostics.
  */
void I2C4_RecoverAndReInit(void)
{
  (void)HAL_I2C_DeInit(&hi2c4);

  __HAL_RCC_I2C4_FORCE_RESET();
  __NOP();
  __NOP();
  __NOP();
  __HAL_RCC_I2C4_RELEASE_RESET();

  /* Re-apply the CubeMX/main.c I2C4 configuration. */
  MX_I2C4_Init();

  HAL_Delay(2U);
}


HAL_StatusTypeDef Sensor_GyroOnly_Init(void)
{
  BNO055_Init_t init = {0};
  HAL_StatusTypeDef status;

  /*
   * 使用修正??? BNO055_STM32.c：ResetBNO055() ??  ?  ?  ??
   *  ? ?  ?  ?  ??  ?  ??  ?  ?  ??? ?   ? ??
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

  /* ?  ?  ?? ?   ? ?  ? ?  ??  ?  ?  ? ?   ? ?  ?  ??   ? ?  ?  ?? */
  BNO055_Init(init);

  /*  ???? Chip ID ?? 模 ?? ? 確 ?? ?  ?  ?  ?  ?  ?  ?  ?? */
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
  /* 此函式只負責?  ?  輸出 GPIO ? ?  ?  ?  ? ?   Motor_UpdateWithDeadtime() ??  ?  ?? */
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

/**
  * @brief 強制?? 止馬 ? 並 ? 除??  ?  ?  ?  ???  ??
  * @note  ??  ?  ? IMU ?   ? ?  ? ? ? ?  ?? ?  ??  ?  ?  ??  ??
  */
void Motor_Deadtime_Reset(void)
{
  Motor_Control(MOTOR_STOP);

  motor_applied_state = MOTOR_STOP;
  motor_last_drive_direction = MOTOR_STOP;
  motor_pending_direction = MOTOR_STOP;
  motor_reverse_wait_active = 0;
  motor_stop_started_ms = HAL_GetTick();
  motor_reverse_wait_elapsed_ms = 0;
}

/**
  * @brief 依照 ? ? ?  ?? ?  ?   ? ?  ? ?   ? ?  ?  ?  ?  ?  ? 100 ms ??  ?  ?  ??
  * @note  ?  ?  式為?? ?  塞設 ? ?  ?  ? ?   100 Hz 主控?   ? ?  ???  ? ?  ?  ??
  *
  * 行為 ?
  * 1. MOTOR_FORWARD -> MOTOR_REVERSE ? ?? STOP 100 ms ? ?? REVERSE??
  * 2. MOTOR_REVERSE -> MOTOR_FORWARD ? ?? STOP 100 ms ? ?? FORWARD??
  * 3. ?? ?  ??  ?  ?  ??   ? ?  ?  ?  ??
  * 4. MOTOR_STOP ->  ? ??  ??  ? ?   ? ?  ? ? 100 ms，直?  ??  ?  ??
  */
void Motor_UpdateWithDeadtime(MotorState requestedState)
{
  uint32_t nowMs = HAL_GetTick();

  /* ?  止異 ? enum ?  ?  ? ?  ?? H-bridge 輸入????  ? ?  ??  ?  ?? */
  if ((requestedState != MOTOR_STOP) &&
      (requestedState != MOTOR_FORWARD) &&
      (requestedState != MOTOR_REVERSE))
  {
    requestedState = MOTOR_STOP;
  }

  if (requestedState == MOTOR_STOP)
  {
    /*  ? ? ? ?  ?  ?  ? ?  ??  ???  ?  ?  ?  ? 止起 ?  ?  ?  ?? */
    if (motor_applied_state != MOTOR_STOP)
    {
      motor_stop_started_ms = nowMs;
    }

    Motor_Control(MOTOR_STOP);
    motor_applied_state = MOTOR_STOP;

    if ((motor_last_drive_direction != MOTOR_STOP) ||
        motor_reverse_wait_active)
    {
      motor_reverse_wait_elapsed_ms = nowMs - motor_stop_started_ms;

      /*
       *  ? ?  ?? ? ?  ? ? 100 ms，代表馬??  ??? 足 ?? ?  ???  ?  ??
       * 下次 ? ?  ? ??  ??  ?  ? ?  視為 ? ?  ?????  ? ?  ??  ?  ??
       */
      if (motor_reverse_wait_elapsed_ms >= MOTOR_REVERSE_DEADTIME_MS)
      {
        motor_last_drive_direction = MOTOR_STOP;
        motor_pending_direction = MOTOR_STOP;
        motor_reverse_wait_active = 0;
        motor_reverse_wait_elapsed_ms = 0;
      }
    }
    else
    {
      /*  ? ?  ?  ?  ?  ?  ?  ?  ? ?   0，避??? Live Expressions 顯示很大?? 累 ?? ?  ?? */
      motor_reverse_wait_elapsed_ms = 0;
    }

    return;
  }

  /*
   * 尚未??  ?  ? ?  ??  ?  ?  ?  ? ?  ??  ?  ?後方?? ?  ??  ?  ?  ??  ??  ?  ? ?  ?  輸出??
   */
  if ((motor_last_drive_direction == MOTOR_STOP) ||
      (requestedState == motor_last_drive_direction))
  {
    Motor_Control(requestedState);
    motor_applied_state = requestedState;
    motor_last_drive_direction = requestedState;
    motor_pending_direction = MOTOR_STOP;
    motor_reverse_wait_active = 0;
    motor_reverse_wait_elapsed_ms = 0;
    return;
  }

  /*
   * 走到? 裡表示 ?? ? ?  ??  ?  ? ? ?  ? ?  ?? ?  ??  ?  ?  ?  ?  ?  ???
   * ?  ?  ??  ? ?   ? ?  ?  ? ?  ?  ??  ?  ?  ?? 100 ms??
   */
  if (motor_applied_state != MOTOR_STOP)
  {
    Motor_Control(MOTOR_STOP);
    motor_applied_state = MOTOR_STOP;
    motor_stop_started_ms = nowMs;
  }

  /*  ? ?次偵測到?  ???  ?  ?  ?  ?  ?  ?  ?  ?  ? ?  ??  ?  ?  ?  ??  ?? */
  if ((!motor_reverse_wait_active) ||
      (motor_pending_direction != requestedState))
  {
    motor_pending_direction = requestedState;
    motor_reverse_wait_active = 1;
    motor_reverse_event_count++;
  }

  motor_reverse_wait_elapsed_ms = nowMs - motor_stop_started_ms;

  if (motor_reverse_wait_elapsed_ms >= MOTOR_REVERSE_DEADTIME_MS)
  {
    /*  ? ?  ? ? 100 ms ? ?  ?  ?輸出?  ?  ??  ?? */
    Motor_Control(requestedState);
    motor_applied_state = requestedState;
    motor_last_drive_direction = requestedState;
    motor_pending_direction = MOTOR_STOP;
    motor_reverse_wait_active = 0;
    motor_reverse_wait_elapsed_ms = 0;
  }
  else
  {
    /*  ? ?  ?  ?  ?  ?? H-bridge ?  ? ?  ?? ?  ?? ?   Low?? */
    Motor_Control(MOTOR_STOP);
    motor_applied_state = MOTOR_STOP;
  }
}

/**
  * @brief ?? 置 ? 軸????  ? 並 ? 即?? 止馬 ?  ??
  */
void Actuator_StateMachine_Reset(void)
{
  Motor_Deadtime_Reset();
  actuator_state = ACTUATOR_IDLE;
  actuator_state_started_ms = HAL_GetTick();
  actuator_state_elapsed_ms = 0;
}

/**
  * @brief  ?次收 ? ->  ? ?? -> ??  ?  ? 失 ? 放 ? ?  ? ?   ? ???  ?  ??
  *
  *  ? ?  ??
  * 1. suppression_start_allowed ?   0  ? 1：固定收線方??  ?? MOTOR_PULL_TIME_MS??
  * 2. ?   ? ?  ?  ?  ???  ? 止 ?? ? ?   HOLDING ? ?  ?  ?? tremorEstimate  ? ? ?  ?  ??
  * 3. tremor_active  ? 0：維??  ? ?  ?? ? ?  ???? 1.5  ? ?  ?  ?  ? ?   ? ??
  * 4. ?   ? MOTOR_RELEASE_TIME_MS  ? ? 止 ?? ? ?   IDLE??
  */
void Actuator_StateMachine_Update(void)
{
  uint32_t nowMs = HAL_GetTick();
  actuator_state_elapsed_ms = nowMs - actuator_state_started_ms;

  switch (actuator_state)
  {
    case ACTUATOR_IDLE:
      Motor_UpdateWithDeadtime(MOTOR_STOP);
      actuator_state_elapsed_ms = 0;

      if (suppression_start_allowed)
      {
        actuator_state = ACTUATOR_PULLING;
        actuator_state_started_ms = nowMs;
        actuator_state_elapsed_ms = 0;
        actuator_pull_count++;
        Motor_UpdateWithDeadtime(MOTOR_PULL_DIRECTION);
      }
      break;

    case ACTUATOR_PULLING:
      if (actuator_state_elapsed_ms >= MOTOR_PULL_TIME_MS)
      {
        Motor_UpdateWithDeadtime(MOTOR_STOP);
        actuator_state = ACTUATOR_HOLDING;
        actuator_state_started_ms = nowMs;
        actuator_state_elapsed_ms = 0;
      }
      else
      {
        Motor_UpdateWithDeadtime(MOTOR_PULL_DIRECTION);
      }
      break;

    case ACTUATOR_HOLDING:
      /*  ? ?  ? 止 ?? ? ?  ?  ?   ? ?  ?  ???  ??   ? ?  ?/線軸?  ?  ??  ?  ?  ?? */
      Motor_UpdateWithDeadtime(MOTOR_STOP);

      if (!tremor_active)
      {
        actuator_state = ACTUATOR_RETURNING;
        actuator_state_started_ms = nowMs;
        actuator_state_elapsed_ms = 0;
        actuator_return_count++;
        Motor_UpdateWithDeadtime(MOTOR_RELEASE_DIRECTION);
      }
      break;

    case ACTUATOR_RETURNING:
      if (actuator_state_elapsed_ms >= MOTOR_RELEASE_TIME_MS)
      {
        Motor_UpdateWithDeadtime(MOTOR_STOP);
        actuator_state = ACTUATOR_IDLE;
        actuator_state_started_ms = nowMs;
        actuator_state_elapsed_ms = 0;
      }
      else
      {
        Motor_UpdateWithDeadtime(MOTOR_RELEASE_DIRECTION);
      }
      break;

    default:
      Actuator_StateMachine_Reset();
      break;
  }
}

void Tremor_Gate_Reset(void)
{
  selectedGyroInputDps = 0.0;
  tremorPowerEma = 0.0;
  tremorRmsDps = 0.0;
  controlValueDebug = 0.0;
  tremor_active = 0;
  frequency_gate_ok = 0;
  amplitude_gate_ok = 0;
  tremor_on_count = 0;
  tremor_off_count = 0;
  algo_warmup_count = 0;
}

void Algorithm_Init(void)
{
  /*  ? ?  ? ?  已相 ? ?? eHWFLC ??  ?  ?  ?  ?  ??   ? ?  ? ?   ? */
  eHWFLC_KF_step_init();
  Tremor_Gate_Reset();
}

/**
  * @brief ??  ?  ?? tremor_gate.c ??? 100 Hz ?  帶判?  ??
  * @note  ??  ??? ?  ?? ?   TremorGate_DefaultConfig() ? ?  ??  ??  ?  ?  ?  ? ? ??
  */
void Bandpass_TremorGate_Init(void)
{
  bandpass_tremor_gate_config = TremorGate_DefaultConfig();
  TremorGate_Init(&bandpass_tremor_gate, &bandpass_tremor_gate_config);
  Bandpass_TremorGate_Reset();
}

/**
  * @brief 清除 tremor_gate.c ?? 濾波 ???  ?  ?  ?  ? 設 ?? ? ?  ??
  */
void Bandpass_TremorGate_Reset(void)
{
  TremorGate_Reset(&bandpass_tremor_gate);

  bandpass_gate_enabled = 0U;
  suppression_start_allowed = 0U;
  bandpass_tremor_envelope = 0.0f;
  bandpass_voluntary_envelope = 0.0f;
  bandpass_tremor_ratio = 0.0f;
  bandpass_on_count = 0U;
  bandpass_off_count = 0U;
}

/**
  * @brief  ? ? ?  ?   ? ? ?   ? Gyro 餵入 tremor_gate.c??
  * @note  suppression_start_allowed ?  負責? ?  ?  ??  ???  ? ?   ? ?  ?  ?  ?  ?  ? 滿足 ??
  *        1. ?? ?   eHWFLC/RMS ?  ?   tremor_active == 1
  *        2. tremor_gate.c ?  ?   bandpass_gate_enabled == 1
  */
void Bandpass_TremorGate_Update(double gyroDps)
{
  bandpass_gate_enabled = TremorGate_Update(&bandpass_tremor_gate, gyroDps);

  /* 複製??  ??  變數，方 ? STM32CubeIDE Live Expressions  ? ? ?? */
  bandpass_tremor_envelope = bandpass_tremor_gate.tremor_envelope;
  bandpass_voluntary_envelope = bandpass_tremor_gate.voluntary_envelope;
  bandpass_tremor_ratio = bandpass_tremor_gate.tremor_ratio;
  bandpass_on_count = bandpass_tremor_gate.on_count;
  bandpass_off_count = bandpass_tremor_gate.off_count;

  suppression_start_allowed =
      ((tremor_active != 0U) && (bandpass_gate_enabled != 0U)) ? 1U : 0U;
}

void Tremor_Detector_Update(float gyroX, float gyroY, float gyroZ)
{
  double inputGyro;
  double instantaneousPower;
  uint8_t keepActive;
  uint32_t t0;

  /*
   * eHWFLC ?  ?? ?  ?  ????  ?  ?  ??  ?  ?  定餵 ??  ???
   * ?? 設使?   X  ? ?  ? ? 3~7 Hz 作為測試??  ???  ?  ? ?   ? ??
   */
#if (TREMOR_INPUT_AXIS == TREMOR_AXIS_X)
  selectedGyroInputDps = (double)gyroX;
#elif (TREMOR_INPUT_AXIS == TREMOR_AXIS_Y)
  selectedGyroInputDps = (double)gyroY;
#elif (TREMOR_INPUT_AXIS == TREMOR_AXIS_Z)
  selectedGyroInputDps = (double)gyroZ;
#else
#error "TREMOR_INPUT_AXIS must be TREMOR_AXIS_X, TREMOR_AXIS_Y, or TREMOR_AXIS_Z"
#endif

  inputGyro = selectedGyroInputDps;

  t0 = DWT->CYCCNT;
  eHWFLC_KF_step(inputGyro, &tremorEstimate, &freqEstimate);
  algo_cycles = DWT->CYCCNT - t0;
  algo_time_us = (float)algo_cycles / ((float)SystemCoreClock / 1000000.0f);

  /* ??  ?  ? ?  ?  ?表估測器???? ?   ? ?  ? ?  ?? 止並 ?  ???  ? ?  ?  ?? */
  if ((!isfinite(tremorEstimate)) || (!isfinite(freqEstimate)))
  {
    Tremor_Gate_Reset();
    return;
  }

  /*
   *  ? tremorEstimate^2 ??  ? ?   ? ?  ???  ?  ?  ? ?  ??  ? ?   RMS ??  ???
   * ?  ? ? ?  ?  ? 顫波形 ?? ?  ?  ? ? 0 ?  ??  ??  ?  ?  ?  ? ?  ??
   */
  instantaneousPower = tremorEstimate * tremorEstimate;
  tremorPowerEma += TREMOR_POWER_EMA_ALPHA *
                    (instantaneousPower - tremorPowerEma);

  if (tremorPowerEma < 0.0)
  {
    tremorPowerEma = 0.0;
  }
  tremorRmsDps = sqrt(tremorPowerEma);

  /* ??  ?  ?  ?  ?  ?  ?  ?  ? 估測 ?  ?  ?  ? 許馬 ?  ?  ?  ?? */
  if (algo_warmup_count < ALGO_WARMUP_SAMPLES)
  {
    algo_warmup_count++;
    controlValueDebug = 0.0;
    return;
  }

  if (!tremor_active)
  {
    /* 尚未??  ?  ??3.0~7.0 Hz? RMS >= 3.0 ? ?? ? 0.30  ? ?? */
    frequency_gate_ok =
        ((freqEstimate >= TREMOR_FREQ_ON_MIN_HZ) &&
         (freqEstimate <= TREMOR_FREQ_ON_MAX_HZ)) ? 1U : 0U;

    amplitude_gate_ok =
        (tremorRmsDps >= TREMOR_RMS_ON_DPS) ? 1U : 0U;

    if (frequency_gate_ok && amplitude_gate_ok)
    {
      if (tremor_on_count < TREMOR_ON_CONFIRM_SAMPLES)
      {
        tremor_on_count++;
      }
    }
    else
    {
      tremor_on_count = 0;
    }

    if (tremor_on_count >= TREMOR_ON_CONFIRM_SAMPLES)
    {
      tremor_active = 1;
      tremor_on_count = 0;
      tremor_off_count = 0;
    }
  }
  else
  {
    /*
     *  ? ?  ?  ?  ??  較寬??? 2.5~7.5 Hz ??  ?  ?? RMS ?? ? ??
     * ?? ? ?  ???? 1.50  ? ?  ? tremor_active ??  ? ?   0，觸?  ?   ? ??
     */
    frequency_gate_ok =
        ((freqEstimate >= TREMOR_FREQ_OFF_MIN_HZ) &&
         (freqEstimate <= TREMOR_FREQ_OFF_MAX_HZ)) ? 1U : 0U;

    amplitude_gate_ok =
        (tremorRmsDps >= TREMOR_RMS_OFF_DPS) ? 1U : 0U;

    keepActive = (frequency_gate_ok && amplitude_gate_ok) ? 1U : 0U;

    if (!keepActive)
    {
      if (tremor_off_count < TREMOR_OFF_CONFIRM_SAMPLES)
      {
        tremor_off_count++;
      }
    }
    else
    {
      tremor_off_count = 0;
    }

    if (tremor_off_count >= TREMOR_OFF_CONFIRM_SAMPLES)
    {
      tremor_active = 0;
      tremor_on_count = 0;
      tremor_off_count = 0;
      controlValueDebug = 0.0;
      return;
    }
  }

  if (!tremor_active)
  {
    controlValueDebug = 0.0;
    return;
  }

  /*
   * ??  ? ?  ?   ? ? ?  ??? ?   ? ?  ?? tremorEstimate  ? ? ?  ?  ?  ?  ?  ??
   * ??  ???  ??? ?  ?? ?   Actuator_StateMachine_Update() ?  定決 ? ??
   */
  controlValueDebug = -(MOTOR_GAIN * tremorEstimate);
}

void Read_IMU_TestData(float *gx, float *gy, float *gz)
{
  static uint32_t sampleIndex = 0;
  double phase;
  float testValue;

  /*
   * ?  ??  ?  ???? 5 Hz  ?弦測 ? ?  ?  ??
   * 測試 ? ?  ? ?  ?? ?  ?   TREMOR_INPUT_AXIS ???  ??  ???
   */
  phase = 2.0 * PI_D * TEST_TREMOR_FREQ_HZ *
          ((double)sampleIndex / CONTROL_SAMPLE_RATE_HZ);
  testValue = (float)(TEST_TREMOR_AMPLITUDE_DPS * sin(phase));

  *gx = 0.0f;
  *gy = 0.0f;
  *gz = 0.0f;

#if (TREMOR_INPUT_AXIS == TREMOR_AXIS_X)
  *gx = testValue;
#elif (TREMOR_INPUT_AXIS == TREMOR_AXIS_Y)
  *gy = testValue;
#elif (TREMOR_INPUT_AXIS == TREMOR_AXIS_Z)
  *gz = testValue;
#endif

  sampleIndex++;
  if (sampleIndex >= (uint32_t)CONTROL_SAMPLE_RATE_HZ)
  {
    sampleIndex = 0;
  }
}

/**
  * @brief ?  ?   BNO055_STM32.c ??? ReadData()  ???? Gyro??
  * @note ReadData()  ? ?  ?? raw Gyro ?   ? 16.0，X/Y/Z 已是 degree/second ?
  *        ? ?  ? ?  ??  ??   ? 16??
  */
HAL_StatusTypeDef Read_IMU_RealData(float *gx, float *gy, float *gz)
{
  HAL_StatusTypeDef status;

  /*
   * ?  ??  ? ? I2C  ???  ??
   * ReadData() ??  ? BNO055 Gyro ??? 6 ?? raw bytes ?
   * ?? ?   ? 16.0f  ? ?? deg/s??
   */
  status = ReadData(&BNO055_Data, SENSOR_GYRO);

  if (status == HAL_OK)
  {
    *gx = BNO055_Data.Gyro.X;
    *gy = BNO055_Data.Gyro.Y;
    *gz = BNO055_Data.Gyro.Z;

    /*
     * ReadData() ??  ?  ? ?   raw / 16.0f ? ?  ?? 16 ?  ?   ? ?? int16_t??
     * ?  ???  ? ? ?  ?  ?  ?  ?  ?  ?  ?  ?? ESP32 使用 ? ?  ? ? ?  ? ? ?  ? I2C??
     */
    gyroXRaw = (int16_t)(BNO055_Data.Gyro.X * 16.0f);
    gyroYRaw = (int16_t)(BNO055_Data.Gyro.Y * 16.0f);
    gyroZRaw = (int16_t)(BNO055_Data.Gyro.Z * 16.0f);
  }
  else
  {
    gyroXRaw = 0;
    gyroYRaw = 0;
    gyroZRaw = 0;
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

  /*  ? ?  ?  ? ?  ?   Actuator_StateMachine_Update()  ? ?  ?? */

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
  MX_TIM6_Init();
  MX_USART1_UART_Init();
  MX_I2C4_Init();
  MX_USART3_UART_Init();
  /* USER CODE BEGIN 2 */

  Actuator_StateMachine_Reset();

  /* DWT 要在 ? ? ? ?  ?  ?? step ??  ? ?  ?? */
  DWT_Init();

  /*  ? ?  ? ?  已相 ? ?  ?  ?  ?  ?  ?  ?  ?? */
  Algorithm_Init();

  /* ??  ?  ? ?   ? ?? tremor_gate.c ?  帶判?  ?? */
  Bandpass_TremorGate_Init();

  /*
   * BNO055 I2C bring-up diagnostic.
   *
   * 1) Probe 0x28.
   * 2) If 0x28 does not ACK, reset/re-init I2C4 before probing 0x29.
   * 3) Record HAL state/error and the physical SCL/SDA input levels.
   *
   * Existing BNO055_STM32.h is still fixed to address 0x28.
   * Therefore, if 0x29 is found we confirm its CHIP_ID directly here,
   * but do not call the existing driver initialization until its address
   * macro is changed.
   */

  i2c4_scl_level =
      (HAL_GPIO_ReadPin(GPIOD, GPIO_PIN_12) == GPIO_PIN_SET) ? 1U : 0U;
  i2c4_sda_level =
      (HAL_GPIO_ReadPin(GPIOD, GPIO_PIN_13) == GPIO_PIN_SET) ? 1U : 0U;

  /* ---- First try 0x28 ---- */
  bno_ready_28 = HAL_I2C_IsDeviceReady(
      &hi2c4,
      (0x28U << 1),
      3U,
      100U
  );

  i2c4_state_after_28 = (uint32_t)hi2c4.State;
  i2c4_error_after_28 = (uint32_t)hi2c4.ErrorCode;

  if (bno_ready_28 == HAL_OK)
  {
    bno_ready_29 = HAL_ERROR;       /* 0x29 not needed in this case */
    bno_detected_address = 0x28U;

    /* Read CHIP_ID directly before invoking the full driver init. */
    bno_probe_chip_id = 0U;
    bno_read_status = HAL_I2C_Mem_Read(
        &hi2c4,
        (0x28U << 1),
        CHIP_ID_ADDR,
        I2C_MEMADD_SIZE_8BIT,
        (uint8_t *)&bno_probe_chip_id,
        1U,
        100U
    );

    if ((bno_read_status == HAL_OK) &&
        (bno_probe_chip_id == BNO055_ID))
    {
      bno_init_status = Sensor_GyroOnly_Init();

      if (bno_init_status == HAL_OK)
      {
        imu_ready = 1U;
        using_test_data = 0U;
      }
      else
      {
        imu_ready = 0U;
        using_test_data = 1U;
      }
    }
    else
    {
      bno_init_status = HAL_ERROR;
      imu_ready = 0U;
      using_test_data = 1U;
    }
  }
  else
  {
    /*
     * Old STM32H7 HAL versions may leave an error/busy condition after a NACK.
     * Fully de-init/reset/re-init I2C4 before trying the second address.
     */
    I2C4_RecoverAndReInit();

    i2c4_scl_level =
        (HAL_GPIO_ReadPin(GPIOD, GPIO_PIN_12) == GPIO_PIN_SET) ? 1U : 0U;
    i2c4_sda_level =
        (HAL_GPIO_ReadPin(GPIOD, GPIO_PIN_13) == GPIO_PIN_SET) ? 1U : 0U;

    /* ---- Then try 0x29 ---- */
    bno_ready_29 = HAL_I2C_IsDeviceReady(
        &hi2c4,
        (0x29U << 1),
        3U,
        100U
    );

    i2c4_state_after_29 = (uint32_t)hi2c4.State;
    i2c4_error_after_29 = (uint32_t)hi2c4.ErrorCode;

    if (bno_ready_29 == HAL_OK)
    {
      bno_detected_address = 0x29U;

      /* Confirm that the responding device really reports BNO055 CHIP_ID. */
      bno_probe_chip_id = 0U;
      bno_read_status = HAL_I2C_Mem_Read(
          &hi2c4,
          (0x29U << 1),
          CHIP_ID_ADDR,
          I2C_MEMADD_SIZE_8BIT,
          (uint8_t *)&bno_probe_chip_id,
          1U,
          100U
      );

      /*
       * The existing BNO055 driver is compiled for P_BNO055=(0x28<<1),
       * so do not call Sensor_GyroOnly_Init() at 0x29 yet.
       * Live Expressions will clearly show address=41 (0x29)
       * and CHIP_ID=160 (0xA0) if this is the actual module address.
       */
      bno_init_status = HAL_ERROR;
      imu_ready = 0U;
      using_test_data = 1U;
    }
    else
    {
      bno_detected_address = 0U;
      bno_probe_chip_id = 0U;
      bno_init_status = HAL_ERROR;
      bno_chip_id = 0U;
      bno_operation_mode = 0U;
      bno_read_status = HAL_ERROR;
      imu_ready = 0U;
      using_test_data = 1U;
    }
  }

  /* Capture final idle levels as another hardware diagnostic. */
  i2c4_scl_level =
      (HAL_GPIO_ReadPin(GPIOD, GPIO_PIN_12) == GPIO_PIN_SET) ? 1U : 0U;
  i2c4_sda_level =
      (HAL_GPIO_ReadPin(GPIOD, GPIO_PIN_13) == GPIO_PIN_SET) ? 1U : 0U;

  lastDebugTickMs = HAL_GetTick();

  printf(
      "Integrated tremor stream ready: %u bytes/sample, 100 Hz\r\n",
      (unsigned int)sizeof(TremorSample_t)
  );

  /* ??  ?? TIM6??100 Hz ?  ?   ? ? ?  ?   TIM6 觸發，避??  ?  ?  ?  ??? */
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
     * TIM6  ? 10 ms ?  中斷 ? ?? tick_flag 設為 1??
     * I2C?  ?  ?  ?  ?  ??? ?  ?  ?  ?  ?  主迴??  ?  ? ?   ISR 裡阻 ? ??
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

          /* ?? ? ?  ? ???  ???  ?  ? ?  測試 ? ?  ?? */
          if (imu_consecutive_error_count >= 5U)
          {
            imu_ready = 0;
            using_test_data = 1;
            Tremor_Gate_Reset();
            Bandpass_TremorGate_Reset();
          }
        }
      }

      /*
       * BNO055 ??  ?  ?  ???  ?  ?? ? ???  ???  ?  ?  ??  測試 ? ?  ? ?
       * TIM6 ??  ?  ?  ?  ? ?   ? ? ? 測試 ?  ? 模 ?? ?  ? 許馬 ?  ?  ?  ??
       */
      if (!imu_ready)
      {
        Read_IMU_TestData(&gyroX, &gyroY, &gyroZ);
      }

      /* ?  ?  ?   ? eHWFLC ??  ? ?  ?? ?  ???/RMS ??  ? ?  ?  ?? */
      Tremor_Detector_Update(gyroX, gyroY, gyroZ);

      /*
       *  ? ?  ??? selectedGyroInputDps 餵入 tremor_gate.c??
       * ?  套判?   ? ?  ?  ?  ???? suppression_start_allowed??
       */
      Bandpass_TremorGate_Update(selectedGyroInputDps);
      algo_call_count++;

      if (imu_ready && (bno_read_status == HAL_OK))
      {
        /*
         * ????  ? ?  ?   ?
         * ?? ?  ?  ?  ??? tremor_gate.c ??  ?  ?  ?? -> ??  ???  ? ?   ? ??
         * ?   ? ?  ?  ?  ?  ?? 1.5 秒放線判?  仍維??  ? ?   tremor_active  ? ?  ??
         */
        Actuator_StateMachine_Update();
      }
      else
      {
        /* ??  ??  ?   ? ?  ? ?  ?? 止並 ? ?   ? ?  ?? */
        Actuator_StateMachine_Reset();
      }

      /*
       *  ? ?? TIM6 ?  ?  ?  ???  ? ?  ?  ? IMU  ???  ???  ??
       * sensor_valid=0  ? raw=0；sequence  ? ?  ?  ?  ?  ??
       */
      Tremor_TransmitCurrentSample(
          (imu_ready && (bno_read_status == HAL_OK)) ? 1U : 0U
      );

      /* ?? ? UART3/ST-LINK ?  ?  ?? ?  ??  ?  ?  ?行註 ??? */
      /* Tremor_PrintStatistics(); */
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
  hi2c4.Init.Timing = 0x00602173;
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
  /** Configure Analogue filter
  */
  if (HAL_I2CEx_ConfigAnalogFilter(&hi2c4, I2C_ANALOGFILTER_ENABLE) != HAL_OK)
  {
    Error_Handler();
  }
  /** Configure Digital filter
  */
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
  * @brief USART1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_USART1_UART_Init(void)
{

  /* USER CODE BEGIN USART1_Init 0 */

  /* USER CODE END USART1_Init 0 */

  /* USER CODE BEGIN USART1_Init 1 */

  /* USER CODE END USART1_Init 1 */
  huart1.Instance = USART1;
  huart1.Init.BaudRate = 115200;
  huart1.Init.WordLength = UART_WORDLENGTH_8B;
  huart1.Init.StopBits = UART_STOPBITS_1;
  huart1.Init.Parity = UART_PARITY_NONE;
  huart1.Init.Mode = UART_MODE_TX_RX;
  huart1.Init.HwFlowCtl = UART_HWCONTROL_NONE;
  huart1.Init.OverSampling = UART_OVERSAMPLING_16;
  huart1.Init.OneBitSampling = UART_ONE_BIT_SAMPLE_DISABLE;
  huart1.Init.ClockPrescaler = UART_PRESCALER_DIV1;
  huart1.AdvancedInit.AdvFeatureInit = UART_ADVFEATURE_NO_INIT;
  if (HAL_UART_Init(&huart1) != HAL_OK)
  {
    Error_Handler();
  }
  if (HAL_UARTEx_SetTxFifoThreshold(&huart1, UART_TXFIFO_THRESHOLD_1_8) != HAL_OK)
  {
    Error_Handler();
  }
  if (HAL_UARTEx_SetRxFifoThreshold(&huart1, UART_RXFIFO_THRESHOLD_1_8) != HAL_OK)
  {
    Error_Handler();
  }
  if (HAL_UARTEx_DisableFifoMode(&huart1) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN USART1_Init 2 */

  /* USER CODE END USART1_Init 2 */

}

/**
  * @brief USART3 Initialization Function
  * @param None
  * @retval None
  */
static void MX_USART3_UART_Init(void)
{

  /* USER CODE BEGIN USART3_Init 0 */

  /* USER CODE END USART3_Init 0 */

  /* USER CODE BEGIN USART3_Init 1 */

  /* USER CODE END USART3_Init 1 */
  huart3.Instance = USART3;
  huart3.Init.BaudRate = 115200;
  huart3.Init.WordLength = UART_WORDLENGTH_8B;
  huart3.Init.StopBits = UART_STOPBITS_1;
  huart3.Init.Parity = UART_PARITY_NONE;
  huart3.Init.Mode = UART_MODE_TX_RX;
  huart3.Init.HwFlowCtl = UART_HWCONTROL_NONE;
  huart3.Init.OverSampling = UART_OVERSAMPLING_16;
  huart3.Init.OneBitSampling = UART_ONE_BIT_SAMPLE_DISABLE;
  huart3.Init.ClockPrescaler = UART_PRESCALER_DIV1;
  huart3.AdvancedInit.AdvFeatureInit = UART_ADVFEATURE_NO_INIT;
  if (HAL_UART_Init(&huart3) != HAL_OK)
  {
    Error_Handler();
  }
  if (HAL_UARTEx_SetTxFifoThreshold(&huart3, UART_TXFIFO_THRESHOLD_1_8) != HAL_OK)
  {
    Error_Handler();
  }
  if (HAL_UARTEx_SetRxFifoThreshold(&huart3, UART_RXFIFO_THRESHOLD_1_8) != HAL_OK)
  {
    Error_Handler();
  }
  if (HAL_UARTEx_DisableFifoMode(&huart3) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN USART3_Init 2 */

  /* USER CODE END USART3_Init 2 */

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
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();
  __HAL_RCC_GPIOC_CLK_ENABLE();
  __HAL_RCC_GPIOD_CLK_ENABLE();
  __HAL_RCC_GPIOG_CLK_ENABLE();
  __HAL_RCC_GPIOH_CLK_ENABLE();

  /*
   * Motor / TB6612FNG wiring used by this main.c:
   *   D2 = PG3 -> AIN1
   *   D3 = PA6 -> AIN2
   *   D5 = PA8 -> PWMA
   *
   * PWM is NOT used in this version.
   * PWMA is held HIGH continuously, so the motor is enabled at full duty
   * whenever AIN1/AIN2 request FORWARD or REVERSE.
   */

  /* Set safe initial output levels before configuring the pins as outputs. */
  HAL_GPIO_WritePin(GPIOG, GPIO_PIN_3, GPIO_PIN_RESET);  /* AIN1 LOW */
  HAL_GPIO_WritePin(GPIOA, GPIO_PIN_6, GPIO_PIN_RESET);  /* AIN2 LOW */
  HAL_GPIO_WritePin(GPIOA, GPIO_PIN_8, GPIO_PIN_SET);    /* PWMA HIGH */

  /* D2 / PG3 -> TB6612 AIN1 */
  GPIO_InitStruct.Pin = GPIO_PIN_3;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOG, &GPIO_InitStruct);

  /* D3 / PA6 -> TB6612 AIN2
     D5 / PA8 -> TB6612 PWMA */
  GPIO_InitStruct.Pin = GPIO_PIN_6 | GPIO_PIN_8;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

  /* Make sure the final startup state is STOP with PWMA enabled. */
  HAL_GPIO_WritePin(GPIOG, GPIO_PIN_3, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(GPIOA, GPIO_PIN_6, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(GPIOA, GPIO_PIN_8, GPIO_PIN_SET);
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
