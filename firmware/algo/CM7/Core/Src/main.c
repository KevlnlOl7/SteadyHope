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
#include <math.h>
#include "BNO055_STM32.h"
#include "tremor_gate.h"

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

/*
 * 線軸動作狀態：
 * IDLE      等待手抖成立
 * PULLING   固定方向收線
 * HOLDING   停止馬達並維持目前位置
 * RETURNING 反方向放線回到原位
 */
typedef enum
{
  ACTUATOR_IDLE = 0,
  ACTUATOR_PULLING,
  ACTUATOR_HOLDING,
  ACTUATOR_RETURNING
} ActuatorState;

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

#ifndef HSEM_ID_0
#define HSEM_ID_0 (0U) /* HW semaphore 0*/
#endif

/* 僅用於 Live Expressions 顯示演算法反相控制值；本版本不拿正負號逐週期換向。 */
#define MOTOR_GAIN                    1.0

/*
 * 線軸方向定義。若實際接線相反，只需要互換這兩個定義。
 * MOTOR_PULL_DIRECTION：收線、拉緊方向
 * MOTOR_RELEASE_DIRECTION：放線、放鬆方向
 */
#define MOTOR_PULL_DIRECTION          MOTOR_FORWARD
#define MOTOR_RELEASE_DIRECTION       MOTOR_REVERSE

/*
 * 初始桌上測試時間：偵測成立後收線 300 ms；手抖消失後放線 300 ms。
 * 這兩個值只是 bring-up 起始值，之後必須依線軸直徑與實際位移重新量測。
 */
#define MOTOR_PULL_TIME_MS            2000U
#define MOTOR_RELEASE_TIME_MS         2000U

/* 正反方向切換前，先停止 100 ms；非阻塞，不使用 HAL_Delay()。 */
#define MOTOR_REVERSE_DEADTIME_MS     100U

/* 100 Hz 控制週期 */
#define CONTROL_SAMPLE_RATE_HZ        100.0

/*
 * 演算法具有內部狀態，只能固定餵一個軸，不能同時餵 X/Y/Z。
 * 第一種方式預設維持 X 軸；若之後確認主要抖動方向是 Y 或 Z，
 * 只要改 TREMOR_INPUT_AXIS，不需要修改演算法檔案。
 */
#define TREMOR_AXIS_X                 0U
#define TREMOR_AXIS_Y                 1U
#define TREMOR_AXIS_Z                 2U
#define TREMOR_INPUT_AXIS             TREMOR_AXIS_X

/*
 * 測試階段的目標頻帶：3.0~7.0 Hz。
 * 啟動後使用 2.5~7.5 Hz 的較寬保持範圍，避免邊界小幅波動。
 */
#define TREMOR_FREQ_ON_MIN_HZ         3.0
#define TREMOR_FREQ_ON_MAX_HZ         8.0
#define TREMOR_FREQ_OFF_MIN_HZ        2.5
#define TREMOR_FREQ_OFF_MAX_HZ        8.5

/*
 * tremorEstimate 是有正負號的波形，不能直接要求連續高於門檻，
 * 因為每個週期都會穿越 0；因此使用 RMS 包絡判斷震顫強度。
 */
#define TREMOR_RMS_ON_DPS             3.0
#define TREMOR_RMS_OFF_DPS            2.0
#define TREMOR_POWER_EMA_ALPHA        0.05

/*
 * 100 Hz 下：
 * 30 點  = 條件連續成立 0.30 秒後開始收線。
 * 150 點 = 條件連續消失 1.50 秒後開始反轉放線。
 */
#define TREMOR_ON_CONFIRM_SAMPLES     30U
#define TREMOR_OFF_CONFIRM_SAMPLES    150U

/* 演算法開機先累積 2 秒資料，避免初始頻率暫態誤啟動 */
#define ALGO_WARMUP_SAMPLES           200U

/* 板上測試資料：5 Hz、峰值 20 degree/second */
#define TEST_TREMOR_FREQ_HZ           5.0
#define TEST_TREMOR_AMPLITUDE_DPS     20.0
#define PI_D                          3.14159265358979323846

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

/* 手抖啟動判斷狀態，可放入 Live Expressions 觀察 */
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
 * tremor_gate.c 的獨立頻帶判斷。
 * 不取代上面的 eHWFLC/RMS 判斷，而是作為第二道啟動條件。
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

/* 一次收線、保持、放線的狀態機，可加入 Live Expressions 觀察。 */
volatile ActuatorState actuator_state = ACTUATOR_IDLE;
volatile uint32_t actuator_state_started_ms = 0;
volatile uint32_t actuator_state_elapsed_ms = 0;
volatile uint32_t actuator_pull_count = 0;
volatile uint32_t actuator_return_count = 0;

/*
 * 馬達換向保護狀態，可加入 Live Expressions 觀察。
 * motor_last_drive_direction 會記住最後一次真正輸出的轉動方向。
 */
volatile MotorState motor_applied_state = MOTOR_STOP;
volatile MotorState motor_last_drive_direction = MOTOR_STOP;
volatile MotorState motor_pending_direction = MOTOR_STOP;
volatile uint8_t motor_reverse_wait_active = 0;
volatile uint32_t motor_stop_started_ms = 0;
volatile uint32_t motor_reverse_wait_elapsed_ms = 0;
volatile uint32_t motor_reverse_event_count = 0;


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
  /* 此函式只負責直接輸出 GPIO；換向等待由 Motor_UpdateWithDeadtime() 處理。 */
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
  * @brief 強制停止馬達並清除換向等待狀態。
  * @note  開機、IMU 錯誤或需要完全重新開始時使用。
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
  * @brief 依照要求方向控制馬達；若要反向，先停止 100 ms 再切換。
  * @note  本函式為非阻塞設計，必須在 100 Hz 主控制迴圈中持續呼叫。
  *
  * 行為：
  * 1. MOTOR_FORWARD -> MOTOR_REVERSE：先 STOP 100 ms，再 REVERSE。
  * 2. MOTOR_REVERSE -> MOTOR_FORWARD：先 STOP 100 ms，再 FORWARD。
  * 3. 同方向持續輸出：不等待。
  * 4. MOTOR_STOP -> 任一方向：若已停止滿 100 ms，直接啟動。
  */
void Motor_UpdateWithDeadtime(MotorState requestedState)
{
  uint32_t nowMs = HAL_GetTick();

  /* 防止異常 enum 值造成兩個 H-bridge 輸入狀態不可預期。 */
  if ((requestedState != MOTOR_STOP) &&
      (requestedState != MOTOR_FORWARD) &&
      (requestedState != MOTOR_REVERSE))
  {
    requestedState = MOTOR_STOP;
  }

  if (requestedState == MOTOR_STOP)
  {
    /* 第一次從轉動切到停止時，記錄停止起始時間。 */
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
       * 已經連續停止滿 100 ms，代表馬達已有足夠靜置時間。
       * 下次要求任一方向時，可視為從停止狀態重新啟動。
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
      /* 沒有換向等待時保持為 0，避免 Live Expressions 顯示很大的累積值。 */
      motor_reverse_wait_elapsed_ms = 0;
    }

    return;
  }

  /*
   * 尚未有轉動方向，或要求方向與最後方向相同：不屬於換向，直接輸出。
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
   * 走到這裡表示要求方向與最後轉動方向相反，必須先停止。
   * 若目前仍在轉動，從現在開始計算 100 ms。
   */
  if (motor_applied_state != MOTOR_STOP)
  {
    Motor_Control(MOTOR_STOP);
    motor_applied_state = MOTOR_STOP;
    motor_stop_started_ms = nowMs;
  }

  /* 第一次偵測到這次換向要求時，記錄等待方向與換向次數。 */
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
    /* 已靜置滿 100 ms，才真正輸出新方向。 */
    Motor_Control(requestedState);
    motor_applied_state = requestedState;
    motor_last_drive_direction = requestedState;
    motor_pending_direction = MOTOR_STOP;
    motor_reverse_wait_active = 0;
    motor_reverse_wait_elapsed_ms = 0;
  }
  else
  {
    /* 等待期間保持 H-bridge 兩個方向腳皆為 Low。 */
    Motor_Control(MOTOR_STOP);
    motor_applied_state = MOTOR_STOP;
  }
}

/**
  * @brief 重置線軸狀態機並立即停止馬達。
  */
void Actuator_StateMachine_Reset(void)
{
  Motor_Deadtime_Reset();
  actuator_state = ACTUATOR_IDLE;
  actuator_state_started_ms = HAL_GetTick();
  actuator_state_elapsed_ms = 0;
}

/**
  * @brief 一次收線 -> 保持 -> 手抖消失後放線的非阻塞狀態機。
  *
  * 流程：
  * 1. suppression_start_allowed 由 0 變 1：固定收線方向轉 MOTOR_PULL_TIME_MS。
  * 2. 收線完成：馬達停止，進入 HOLDING，不跟著 tremorEstimate 正負換向。
  * 3. tremor_active 變 0：維持原本連續不符合 1.5 秒後才開始放線。
  * 4. 放線 MOTOR_RELEASE_TIME_MS 後停止，回到 IDLE。
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
      /* 馬達停止；線是否能保持位置取決於減速箱/線軸是否會回滑。 */
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
  /* 保留原本已相容的 eHWFLC 初始化，不修改演算法內容 */
  eHWFLC_KF_step_init();
  Tremor_Gate_Reset();
}

/**
  * @brief 初始化 tremor_gate.c 的 100 Hz 頻帶判斷。
  * @note  預設參數取自 TremorGate_DefaultConfig()，不修改原演算法門檻。
  */
void Bandpass_TremorGate_Init(void)
{
  bandpass_tremor_gate_config = TremorGate_DefaultConfig();
  TremorGate_Init(&bandpass_tremor_gate, &bandpass_tremor_gate_config);
  Bandpass_TremorGate_Reset();
}

/**
  * @brief 清除 tremor_gate.c 的濾波狀態，但保留設定參數。
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
  * @brief 將原本選定的單軸 Gyro 餵入 tremor_gate.c。
  * @note  suppression_start_allowed 只負責「是否允許開始收線」，必須同時滿足：
  *        1. 原本 eHWFLC/RMS 判斷 tremor_active == 1
  *        2. tremor_gate.c 判斷 bandpass_gate_enabled == 1
  */
void Bandpass_TremorGate_Update(double gyroDps)
{
  bandpass_gate_enabled = TremorGate_Update(&bandpass_tremor_gate, gyroDps);

  /* 複製成簡單變數，方便 STM32CubeIDE Live Expressions 觀察。 */
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
   * eHWFLC 具有內部狀態，每次只能固定餵一個軸。
   * 預設使用 X 軸，並以 3~7 Hz 作為測試階段的啟動頻帶。
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

  /* 非有限數值代表估測器狀態異常，立即停止並重置啟動判斷。 */
  if ((!isfinite(tremorEstimate)) || (!isfinite(freqEstimate)))
  {
    Tremor_Gate_Reset();
    return;
  }

  /*
   * 對 tremorEstimate^2 做指數移動平均，再開根號得到 RMS 包絡。
   * 這樣不會因震顫波形每半週穿越 0 而一直取消啟動計數。
   */
  instantaneousPower = tremorEstimate * tremorEstimate;
  tremorPowerEma += TREMOR_POWER_EMA_ALPHA *
                    (instantaneousPower - tremorPowerEma);

  if (tremorPowerEma < 0.0)
  {
    tremorPowerEma = 0.0;
  }
  tremorRmsDps = sqrt(tremorPowerEma);

  /* 開機暖機期間仍持續估測，但不允許馬達動作。 */
  if (algo_warmup_count < ALGO_WARMUP_SAMPLES)
  {
    algo_warmup_count++;
    controlValueDebug = 0.0;
    return;
  }

  if (!tremor_active)
  {
    /* 尚未啟動：3.0~7.0 Hz、RMS >= 3.0，連續 0.30 秒。 */
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
     * 已啟動：使用較寬的 2.5~7.5 Hz 與較低 RMS 門檻。
     * 連續不符合 1.50 秒後，tremor_active 才清為 0，觸發放線。
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
   * 僅供除錯觀察。此版本不再依 tremorEstimate 正負逐週期換向，
   * 真正的馬達方向由 Actuator_StateMachine_Update() 固定決定。
   */
  controlValueDebug = -(MOTOR_GAIN * tremorEstimate);
}

void Read_IMU_TestData(float *gx, float *gy, float *gz)
{
  static uint32_t sampleIndex = 0;
  double phase;
  float testValue;

  /*
   * 產生真正的 5 Hz 正弦測試資料。
   * 測試訊號會自動放到 TREMOR_INPUT_AXIS 所選的軸。
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

  /* 馬達動作改由 Actuator_StateMachine_Update() 管理。 */

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

  Actuator_StateMachine_Reset();

  /* DWT 要在第一次演算法 step 前啟用。 */
  DWT_Init();

  /* 保留原本已相容的演算法初始化。 */
  Algorithm_Init();

  /* 初始化新增的 tremor_gate.c 頻帶判斷。 */
  Bandpass_TremorGate_Init();

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
            Tremor_Gate_Reset();
            Bandpass_TremorGate_Reset();
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

      /* 更新單軸 eHWFLC 與原本的頻率/RMS 手抖判斷。 */
      Tremor_Detector_Update(gyroX, gyroY, gyroZ);

      /*
       * 將同一個 selectedGyroInputDps 餵入 tremor_gate.c。
       * 兩套判斷結果會合併成 suppression_start_allowed。
       */
      Bandpass_TremorGate_Update(selectedGyroInputDps);
      algo_call_count++;

      if (imu_ready && (bno_read_status == HAL_OK))
      {
        /*
         * 狀態機控制：
         * 原本判斷與 tremor_gate.c 同時成立 -> 允許開始收線；
         * 收線後的保持與 1.5 秒放線判斷仍維持原本 tremor_active 流程。
         */
        Actuator_StateMachine_Update();
      }
      else
      {
        /* 感測器異常時立即停止並回到待機。 */
        Actuator_StateMachine_Reset();
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
