/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : 0822/0823 hardened tremor gate + Encoder + UART + safe motor integration
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

typedef enum
{
  ACTUATOR_IDLE = 0,
  ACTUATOR_PULLING,
  ACTUATOR_HOLDING,
  ACTUATOR_RETURNING
} ActuatorState;

#pragma pack(push, 1)
typedef struct
{
  uint32_t sequence;
  uint32_t sample_tick_ms;
  int16_t gyro_x_raw;
  int16_t gyro_y_raw;
  int16_t gyro_z_raw;
  uint8_t sensor_valid;
  /*
   * Motor drive status sent to ESP32 / App:
   *   0 = motor is NOT being driven
   *   1 = motor IS being driven
   *
   * App-side normal-use rule:
   *   0 -> length controls may be adjusted
   *   1 -> motor is busy; temporarily disable length controls
   */
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
#define HSEM_ID_0                       (0U)
#endif

/* Motor */
#define MOTOR_GAIN                      1.0
#define MOTOR_RATED_RPM                 201U
#define MOTOR_GEAR_RATIO                21.3f
#define ENCODER_MOTOR_SIGNALS_PER_REV   11U

/*
 * Legacy logical mapping only. 0823 requires a low-energy bench confirmation
 * of which AIN1/AIN2 polarity is RELEASE vs TAKE-UP before this may authorize
 * real motion. Physical output is locked below until that path is integrated.
 */
#define MOTOR_PULL_DIRECTION            MOTOR_FORWARD
#define MOTOR_RELEASE_DIRECTION         MOTOR_REVERSE

/*
 * Legacy actuator timing is retained only so the old state-machine code still
 * builds for diagnostics. 0823 motor permission does NOT come from these timers.
 */
#define MOTOR_PULL_TIME_MS              5000U
#define MOTOR_RELEASE_TIME_MS           5000U
#define MOTOR_REVERSE_DEADTIME_MS       100U

/* 0823 TB6612 hardware mapping */
#define MOTOR_AIN1_GPIO_PORT            GPIOG
#define MOTOR_AIN1_PIN                  GPIO_PIN_3   /* D2 / PG3 */
#define MOTOR_AIN2_GPIO_PORT            GPIOA
#define MOTOR_AIN2_PIN                  GPIO_PIN_6   /* D3 / PA6 */
#define MOTOR_STBY_GPIO_PORT            GPIOK
#define MOTOR_STBY_PIN                  GPIO_PIN_1   /* D4 / PK1 */
#define MOTOR_PWM_CHANNEL               TIM_CHANNEL_1
#define MOTOR_PWM_FULL_SCALE_CCR        3200U        /* TIM1 ARR=3199 */

/*
 * 0823 requires an authoritative SuppressionControl AND MotorPositionGuard
 * before physical motion is permitted. Those authoritative modules are not in
 * the supplied main.c/tremor_gate files, therefore this integration remains
 * fail-safe locked until they are integrated.
 */
#define SUPPRESSION_CONTROL_INTEGRATED  0U
#define MOTOR_POSITION_GUARD_INTEGRATED 0U

/*
 * Communication integration test mode.
 *
 * 1U:
 *   UART packet field motor_enabled reports the hardened 0822 TremorGate
 *   decision after the gate health checks pass.
 *
 *   This is ONLY a communication/status test. It does NOT bypass the 0823
 *   SuppressionControl / MotorPositionGuard safety locks, so the physical
 *   TB6612 motor output remains disabled by the existing motor path.
 *
 * 0U:
 *   UART packet field motor_enabled reports the real commanded motor output
 *   state (motor_output_active_debug).
 *
 * Packet size and UART protocol remain unchanged in both modes.
 */
#define COMM_TEST_GATE_AS_MOTOR_STATUS   1U

/* 100 Hz */
#define CONTROL_SAMPLE_RATE_HZ          100.0

/* USART1 -> ESP32 tremor packet */
#define TREMOR_UART_TIMEOUT_MS          5U

/*
 * ESP32 -> STM32 control packet:
 *
 * Byte0 = command
 * Byte1 = value / magnitude
 *
 * 0x01: intensity 0~100 (%)
 *
 * 0x02: NEGATIVE relative cable adjustment
 *       Byte1 is the positive magnitude in mm.
 *       Example:
 *         [0x02][0x06] = -6 mm
 *         [0x02][0x01] = -1 mm
 *
 * 0x03: POSITIVE relative cable adjustment
 *       Byte1 is the positive magnitude in mm.
 *       Example:
 *         [0x03][0x06] = +6 mm
 *         [0x03][0x01] = +1 mm
 *
 * 0x04: absolute target cable length in mm
 *       Example:
 *         [0x04][60] = target 60 mm
 *
 * This protocol intentionally avoids two's-complement values on the App side.
 * Negative direction is selected by command 0x02, positive by command 0x03.
 */
#define CONTROL_PACKET_SIZE                 2U
#define CMD_SET_INTENSITY                   0x01U
#define CMD_ADJUST_LENGTH_NEGATIVE_MM       0x02U
#define CMD_ADJUST_LENGTH_POSITIVE_MM       0x03U
#define CMD_SET_BASE_LENGTH_MM              0x04U

/* Cable length */
#define LENGTH_MIN_MM                   30.0f
#define LENGTH_MAX_MM                   100.0f
#define INITIAL_CABLE_LENGTH_MM         60.0f
#define LENGTH_TOLERANCE_MM             0.5f

/*
 * 0823 calibration safety:
 * Raw encoder rotation has been bench-verified. The final spool/mechanism mm
 * calibration has NOT been completed, so mm-based motion must remain locked.
 *
 * Bench diagnostic only:
 *   output shaft ~= 893 counts / revolution (manual 1-rev trials)
 *
 * Change ENCODER_COUNTS_PER_MM only after the final spool/mechanism is measured.
 */
#define ENCODER_COUNTS_PER_OUTPUT_REV   893.0f
#define ENCODER_COUNTS_PER_MM           0.0f

/*
 * Encoder electrical direction already bench-verified:
 *   right turn -> count increases
 *   left turn  -> count decreases
 *
 * RELEASE/TAKE-UP physical meaning is intentionally NOT frozen here until the
 * final spool/mechanism direction is confirmed. ENCODER_LENGTH_SIGN is retained
 * only for the later mm conversion; mm motion is currently locked at 0 counts/mm.
 */
#define ENCODER_LENGTH_SIGN             1.0f

/* Encoder:
 * C1 / yellow -> PE6
 * C2 / green  -> PI8
 */
#define ENCODER_A_GPIO_PORT             GPIOE
#define ENCODER_A_PIN                   GPIO_PIN_6
#define ENCODER_B_GPIO_PORT             GPIOI
#define ENCODER_B_PIN                   GPIO_PIN_8

/* Tremor axis */
#define TREMOR_AXIS_X                   0U
#define TREMOR_AXIS_Y                   1U
#define TREMOR_AXIS_Z                   2U
#define TREMOR_INPUT_AXIS               TREMOR_AXIS_X

/*
 * Legacy eHWFLC/RMS diagnostics only.
 * 0823 rule: freqEstimate / tremor_active MUST NOT authorize motor actuation.
 * The hardened TremorGate output below is the gate used by the motor path.
 */
#define TREMOR_FREQ_ON_MIN_HZ           3.0
#define TREMOR_FREQ_ON_MAX_HZ           8.0
#define TREMOR_FREQ_OFF_MIN_HZ          2.5
#define TREMOR_FREQ_OFF_MAX_HZ          8.5

#define TREMOR_RMS_ON_DPS               3.0
#define TREMOR_RMS_OFF_DPS              2.0
#define TREMOR_POWER_EMA_ALPHA          0.05

#define TREMOR_ON_CONFIRM_SAMPLES       30U
#define TREMOR_OFF_CONFIRM_SAMPLES      150U
#define ALGO_WARMUP_SAMPLES             200U

/* IMU fallback test signal */
#define TEST_TREMOR_FREQ_HZ             5.0
#define TEST_TREMOR_AMPLITUDE_DPS       20.0
#define PI_D                            3.14159265358979323846

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

I2C_HandleTypeDef hi2c4;

TIM_HandleTypeDef htim1;
TIM_HandleTypeDef htim6;

UART_HandleTypeDef huart1;
UART_HandleTypeDef huart3;

/* USER CODE BEGIN PV */

/* -------------------------------------------------------------------------- */
/* BNO055                                                                      */
/* -------------------------------------------------------------------------- */
BNO055_Sensors_t BNO055_Data = {0};

float gyroX = 0.0f;
float gyroY = 0.0f;
float gyroZ = 0.0f;

int16_t gyroXRaw = 0;
int16_t gyroYRaw = 0;
int16_t gyroZRaw = 0;

volatile HAL_StatusTypeDef imuUartStatus = HAL_OK;
volatile uint32_t imuSampleCount = 0U;
volatile uint32_t imuUartErrorCount = 0U;
/*
 * Debug / outgoing motor status byte:
 *   0 = motor is NOT being driven
 *   1 = motor IS being driven
 *
 * During normal operation the App may use:
 *   0 -> enable length controls
 *   1 -> disable length controls while motor is moving
 */
volatile uint8_t motorEnabledForApp = 0U;

static uint32_t tremorSequence = 0U;
static TremorSample_t lastTremorSample = {0};

/* -------------------------------------------------------------------------- */
/* REAL APP / ESP32 UART RX                                                    */
/* -------------------------------------------------------------------------- */
volatile uint8_t motorIntensityPercent = 50U;
static uint8_t controlRxBuffer[CONTROL_PACKET_SIZE] = {0U, 0U};

volatile uint32_t controlRxCount = 0U;
volatile uint32_t controlInvalidCount = 0U;
volatile uint32_t controlUartErrorCount = 0U;

volatile uint8_t lastControlCommand = 0U;
volatile uint8_t lastControlRawValue = 0U;
volatile int16_t lastControlDecodedValue = 0;
volatile uint8_t lastControlValid = 0U;

/* -------------------------------------------------------------------------- */
/* FAKE APP DEBUG VARIABLES                                                    */
/*
 * These are GLOBAL + VOLATILE on purpose so STM32CubeIDE Live Expressions
 * can always see them in the newly built ELF.
 *
 * Test examples:
 *
 * Positive +5 mm:
 *   fakeAppCommand = 3
 *   fakeAppValueMm = 5
 *   fakeAppTrigger = 1
 *   -> target 60 -> 65 mm
 *
 * Negative -5 mm:
 *   fakeAppCommand = 2
 *   fakeAppValueMm = 5
 *   fakeAppTrigger = 1
 *   -> target 65 -> 60 mm
 *
 * fakeAppValueMm is always entered as a positive magnitude.
 */
/* -------------------------------------------------------------------------- */
volatile uint8_t fakeAppCommand = CMD_ADJUST_LENGTH_POSITIVE_MM;
volatile int16_t fakeAppValueMm = 0;
volatile uint8_t fakeAppTrigger = 0U;

volatile uint32_t fakeAppCommandCount = 0U;
volatile uint32_t fakeAppInvalidCount = 0U;
volatile uint32_t fakeAppHeartbeat = 0U;
volatile uint8_t fakeAppLastValid = 0U;

/* -------------------------------------------------------------------------- */
/* Encoder / cable length                                                      */
/* -------------------------------------------------------------------------- */
volatile int32_t encoder_count = 0;
volatile uint32_t encoder_edge_count = 0U;
volatile uint32_t encoder_valid_transition_count = 0U;
volatile uint32_t encoder_invalid_transition_count = 0U;
volatile uint8_t encoder_invalid_latched = 0U;
volatile uint8_t encoder_overflow_latched = 0U;
volatile uint8_t encoder_valid = 0U;
volatile uint8_t encoder_prev_ab = 0U;

/* 0823: reset/brownout/fault requires an explicit neutral SetZero again. */
volatile uint8_t encoder_set_zero_request = 0U;
volatile int32_t encoder_set_zero_status = 0; /* 1=PASS, <0=fail */
volatile int32_t encoder_zero_count = 0;
volatile uint8_t encoder_position_zeroed = 0U;
volatile uint8_t calibration_required = 1U;

volatile float currentLengthMm = INITIAL_CABLE_LENGTH_MM;
volatile float targetLengthMm = INITIAL_CABLE_LENGTH_MM;
volatile float lengthErrorMm = 0.0f;

volatile uint8_t lengthAdjustPending = 0U;
volatile uint8_t lengthAdjustActive = 0U;
volatile uint8_t lengthAdjustBlocked = 0U;
volatile uint8_t encoderLengthCalibrated = 0U;

volatile int16_t lastLengthDeltaMm = 0;

volatile uint32_t lengthAdjustRequestCount = 0U;
volatile uint32_t lengthAdjustCompleteCount = 0U;
volatile uint32_t lengthAdjustRejectedCount = 0U;

/* -------------------------------------------------------------------------- */
/* Algorithm                                                                   */
/* -------------------------------------------------------------------------- */
double tremorEstimate = 0.0;
double freqEstimate = 0.0;

double selectedGyroInputDps = 0.0;
double tremorPowerEma = 0.0;
double tremorRmsDps = 0.0;
double controlValueDebug = 0.0;

volatile uint8_t tremor_active = 0U;
volatile uint8_t frequency_gate_ok = 0U;
volatile uint8_t amplitude_gate_ok = 0U;
volatile uint16_t tremor_on_count = 0U;
volatile uint16_t tremor_off_count = 0U;
volatile uint32_t algo_warmup_count = 0U;

/* tremor_gate.c */
static TremorGate bandpass_tremor_gate;
static TremorGateConfig bandpass_tremor_gate_config;

volatile uint8_t bandpass_gate_enabled = 0U;

/* 0823 motor-permission diagnostics; not added to the UART packet. */
volatile uint8_t gate_enabled_debug = 0U;
volatile uint8_t hardened_gate_ready = 0U;
volatile uint8_t hardened_gate_fault = (uint8_t)TREMOR_GATE_FAULT_NONE;

/*
 * 0823 keeps three concepts separate:
 *   gate_enabled_debug          = hardened 4-6 Hz gate decision
 *   actuation_permitted_debug   = authoritative suppression permission
 *   motor_output_active_debug   = actual commanded bridge/PWM state
 */
volatile uint8_t gate_precondition_ok_debug = 0U;
volatile uint8_t suppression_control_ready_debug = 0U;
volatile uint8_t actuation_permitted_debug = 0U;
volatile uint8_t suppression_start_allowed = 0U;

volatile float bandpass_tremor_envelope = 0.0f;
volatile float bandpass_voluntary_envelope = 0.0f;
volatile float bandpass_tremor_ratio = 0.0f;

volatile uint16_t bandpass_on_count = 0U;
volatile uint16_t bandpass_off_count = 0U;

/* -------------------------------------------------------------------------- */
/* Actuator                                                                    */
/* -------------------------------------------------------------------------- */
volatile ActuatorState actuator_state = ACTUATOR_IDLE;
volatile uint32_t actuator_state_started_ms = 0U;
volatile uint32_t actuator_state_elapsed_ms = 0U;
volatile uint32_t actuator_pull_count = 0U;
volatile uint32_t actuator_return_count = 0U;

volatile MotorState motor_applied_state = MOTOR_STOP;
volatile MotorState motor_last_drive_direction = MOTOR_STOP;
volatile MotorState motor_pending_direction = MOTOR_STOP;

volatile uint8_t motor_reverse_wait_active = 0U;
volatile uint32_t motor_stop_started_ms = 0U;
volatile uint32_t motor_reverse_wait_elapsed_ms = 0U;
volatile uint32_t motor_reverse_event_count = 0U;

/* 0823 actual output diagnostics */
volatile HAL_StatusTypeDef motor_pwm_start_status = HAL_ERROR;
volatile uint32_t motor_applied_ccr = 0U;
volatile uint8_t motor_applied_ain1 = 0U;
volatile uint8_t motor_applied_ain2 = 0U;
volatile uint8_t motor_applied_stby = 0U;
volatile uint8_t motor_output_active_debug = 0U;
volatile uint8_t motor_output_guard_ready_debug = 0U;

/* -------------------------------------------------------------------------- */
/* TIM6 / Debug                                                                */
/* -------------------------------------------------------------------------- */
volatile uint8_t tick_flag = 0U;

uint32_t algo_cycles = 0U;
float algo_time_us = 0.0f;

volatile uint32_t tim6_irq_count = 0U;
volatile uint32_t software_tick_count = 0U;
volatile uint32_t control_tick_count = 0U;

volatile uint32_t imu_read_ok_count = 0U;
volatile uint32_t imu_read_error_count = 0U;
volatile uint32_t imu_consecutive_error_count = 0U;

volatile uint32_t algo_call_count = 0U;

/* -------------------------------------------------------------------------- */
/* BNO055 diagnostics                                                          */
/* -------------------------------------------------------------------------- */
volatile HAL_StatusTypeDef bno_init_status = HAL_ERROR;
volatile HAL_StatusTypeDef bno_read_status = HAL_ERROR;

volatile HAL_StatusTypeDef bno_ready_28 = HAL_ERROR;
volatile HAL_StatusTypeDef bno_ready_29 = HAL_ERROR;

volatile uint8_t bno_detected_address = 0U;

volatile uint32_t i2c4_state_after_28 = 0U;
volatile uint32_t i2c4_error_after_28 = 0U;
volatile uint32_t i2c4_state_after_29 = 0U;
volatile uint32_t i2c4_error_after_29 = 0U;

volatile uint8_t i2c4_scl_level = 0U;
volatile uint8_t i2c4_sda_level = 0U;
volatile uint8_t bno_probe_chip_id = 0U;

volatile uint8_t bno_chip_id = 0U;
volatile uint8_t bno_operation_mode = 0U;

volatile uint8_t imu_ready = 0U;
volatile uint8_t using_test_data = 0U;

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_TIM6_Init(void);
static void MX_USART1_UART_Init(void);
static void MX_I2C4_Init(void);
static void MX_USART3_UART_Init(void);
static void MX_TIM1_Init(void);
/* USER CODE BEGIN PFP */

void Motor_Control(MotorState state);
void Motor_Deadtime_Reset(void);
void Motor_UpdateWithDeadtime(MotorState requestedState);
static void Motor_ForceSafe(void);
static void Motor_InitSafePwm(void);
static uint32_t Motor_DutyPercentToCcr(uint8_t dutyPercent);
static void Encoder_ProcessSetZeroRequest(void);

void Actuator_StateMachine_Reset(void);
void Actuator_StateMachine_Update(void);

void Algorithm_Init(void);
void Tremor_Gate_Reset(void);

void Tremor_Detector_Update(float gx, float gy, float gz);

void Bandpass_TremorGate_Init(void);
void Bandpass_TremorGate_Reset(void);
void Bandpass_TremorGate_Update(double gyroDps);

void Read_IMU_TestData(float *gx, float *gy, float *gz);
HAL_StatusTypeDef Read_IMU_RealData(float *gx, float *gy, float *gz);

HAL_StatusTypeDef Sensor_GyroOnly_Init(void);
void I2C4_RecoverAndReInit(void);
void DWT_Init(void);

static void Tremor_TransmitCurrentSample(uint8_t sensorValid);

static void Control_StartReceive(void);
static int16_t Control_DecodeValue(uint8_t command, uint8_t rawValue);
static uint8_t Control_ApplyCommand(uint8_t command, int16_t value);

static void FakeApp_Process(void);

static uint8_t Encoder_ReadAB(void);
static void Encoder_Init(void);
static void Encoder_UpdateLength(void);

static uint8_t Length_Adjustment_Update(void);

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* ========================================================================== */
/* STM32 -> ESP32 tremor packet                                                */
/* ========================================================================== */

static void Tremor_TransmitCurrentSample(uint8_t sensorValid)
{
  TremorSample_t sample = {0};

  sample.sequence = tremorSequence++;
  sample.sample_tick_ms = HAL_GetTick();

  if (sensorValid != 0U)
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
   * Keep TremorSample_t at 16 bytes so the ESP32 packet format remains
   * unchanged.
   *
   * COMM_TEST_GATE_AS_MOTOR_STATUS == 1U:
   *   Communication integration test only.
   *   0 = hardened TremorGate is not enabled / not healthy
   *   1 = hardened TremorGate is enabled and healthy
   *
   *   IMPORTANT:
   *   This value means "gate condition satisfied" for the software-team test.
   *   It does NOT mean the physical motor has actually been energized.
   *   The 0823 physical motor safety chain remains locked separately.
   *
   * COMM_TEST_GATE_AS_MOTOR_STATUS == 0U:
   *   Production-style status.
   *   Report the actual commanded hardware motor output state.
   */
#if (COMM_TEST_GATE_AS_MOTOR_STATUS == 1U)

  motorEnabledForApp =
      ((hardened_gate_ready != 0U) &&
       (hardened_gate_fault == (uint8_t)TREMOR_GATE_FAULT_NONE) &&
       (gate_enabled_debug != 0U) &&
       (sensorValid != 0U))
      ? 1U : 0U;

#else

  motorEnabledForApp =
      (motor_output_active_debug != 0U)
      ? 1U : 0U;

#endif

  sample.motor_enabled = motorEnabledForApp;

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

/* ========================================================================== */
/* DWT                                                                         */
/* ========================================================================== */

void DWT_Init(void)
{
  CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
  DWT->CYCCNT = 0U;
  DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
}

/* ========================================================================== */
/* I2C4 / BNO055                                                               */
/* ========================================================================== */

void I2C4_RecoverAndReInit(void)
{
  (void)HAL_I2C_DeInit(&hi2c4);

  __HAL_RCC_I2C4_FORCE_RESET();
  __NOP();
  __NOP();
  __NOP();
  __HAL_RCC_I2C4_RELEASE_RESET();

  MX_I2C4_Init();

  HAL_Delay(2U);
}

HAL_StatusTypeDef Sensor_GyroOnly_Init(void)
{
  BNO055_Init_t init = {0};
  HAL_StatusTypeDef status;

  status = ResetBNO055();

  if (status != HAL_OK)
  {
    return status;
  }

  init.ACC_Range = Range_16G;
  init.Axis = DEFAULT_AXIS_REMAP;
  init.Axis_sign = DEFAULT_AXIS_SIGN;
  init.Clock_Source = CLOCK_EXTERNAL;
  init.Mode = BNO055_NORMAL_MODE;
  init.OP_Modes = GYRO_ONLY;

  init.Unit_Sel =
      (UNIT_ORI_ANDROID |
       UNIT_TEMP_CELCIUS |
       UNIT_EUL_DEG |
       UNIT_GYRO_DPS |
       UNIT_ACC_MS2);

  BNO055_Init(init);

  status = HAL_I2C_Mem_Read(
      &hi2c4,
      P_BNO055,
      CHIP_ID_ADDR,
      I2C_MEMADD_SIZE_8BIT,
      (uint8_t *)&bno_chip_id,
      1U,
      20U
  );

  if ((status != HAL_OK) ||
      (bno_chip_id != BNO055_ID))
  {
    return HAL_ERROR;
  }

  status = HAL_I2C_Mem_Read(
      &hi2c4,
      P_BNO055,
      OPR_MODE_ADDR,
      I2C_MEMADD_SIZE_8BIT,
      (uint8_t *)&bno_operation_mode,
      1U,
      20U
  );

  if ((status != HAL_OK) ||
      (bno_operation_mode != GYRO_ONLY))
  {
    return HAL_ERROR;
  }

  return HAL_OK;
}

/* ========================================================================== */
/* APP command common handler                                                  */
/* ========================================================================== */

static int16_t Control_DecodeValue(uint8_t command, uint8_t rawValue)
{
  /*
   * New App protocol:
   *
   *   0x02 06 -> -6 mm
   *   0x03 06 -> +6 mm
   *
   * The second byte is always sent as a positive magnitude.
   */
  if (command == CMD_ADJUST_LENGTH_NEGATIVE_MM)
  {
    return -(int16_t)rawValue;
  }

  return (int16_t)rawValue;
}

static uint8_t Control_ApplyCommand(uint8_t command, int16_t value)
{
  float requestedLengthMm;
  float candidateTargetMm;

  switch (command)
  {
    case CMD_SET_INTENSITY:
      if ((value >= 0) && (value <= 100))
      {
        motorIntensityPercent = (uint8_t)value;
        return 1U;
      }

      return 0U;

    case CMD_SET_BASE_LENGTH_MM:
      requestedLengthMm = (float)value;

      if ((requestedLengthMm >= LENGTH_MIN_MM) &&
          (requestedLengthMm <= LENGTH_MAX_MM))
      {
        targetLengthMm = requestedLengthMm;
        lengthErrorMm = targetLengthMm - currentLengthMm;

        if (fabsf(lengthErrorMm) > LENGTH_TOLERANCE_MM)
        {
          lengthAdjustPending = 1U;
          lengthAdjustRequestCount++;
        }
        else
        {
          lengthAdjustPending = 0U;
        }

        lastLengthDeltaMm = 0;

        return 1U;
      }

      lengthAdjustRejectedCount++;
      return 0U;

    case CMD_ADJUST_LENGTH_NEGATIVE_MM:
    case CMD_ADJUST_LENGTH_POSITIVE_MM:
      /*
       * value has already been decoded:
       *   0x02 06 -> value = -6
       *   0x03 06 -> value = +6
       */
      candidateTargetMm =
          targetLengthMm + (float)value;

      if ((candidateTargetMm >= LENGTH_MIN_MM) &&
          (candidateTargetMm <= LENGTH_MAX_MM))
      {
        targetLengthMm = candidateTargetMm;
        lengthErrorMm = targetLengthMm - currentLengthMm;
        lastLengthDeltaMm = value;

        if (value != 0)
        {
          lengthAdjustPending = 1U;
          lengthAdjustRequestCount++;
        }

        return 1U;
      }

      /*
       * Do not modify targetLengthMm or lastLengthDeltaMm when rejected.
       */
      lengthAdjustRejectedCount++;
      return 0U;

    default:
      return 0U;
  }
}

/* ========================================================================== */
/* REAL ESP32 -> STM32 UART RX                                                 */
/* ========================================================================== */

static void Control_StartReceive(void)
{
  if (HAL_UART_Receive_IT(
          &huart1,
          controlRxBuffer,
          CONTROL_PACKET_SIZE
      ) != HAL_OK)
  {
    controlUartErrorCount++;
  }
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
  uint8_t command;
  uint8_t rawValue;
  int16_t decodedValue;
  uint8_t valid;

  if (huart->Instance != USART1)
  {
    return;
  }

  command = controlRxBuffer[0];
  rawValue = controlRxBuffer[1];

  decodedValue = Control_DecodeValue(command, rawValue);

  valid = Control_ApplyCommand(command, decodedValue);

  lastControlCommand = command;
  lastControlRawValue = rawValue;
  lastControlDecodedValue = decodedValue;
  lastControlValid = valid;

  if (valid != 0U)
  {
    controlRxCount++;
  }
  else
  {
    controlInvalidCount++;
  }

  if (HAL_UART_Receive_IT(
          &huart1,
          controlRxBuffer,
          CONTROL_PACKET_SIZE
      ) != HAL_OK)
  {
    controlUartErrorCount++;
  }
}

void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
  if (huart->Instance != USART1)
  {
    return;
  }

  controlUartErrorCount++;

  (void)HAL_UART_AbortReceive(&huart1);

  Control_StartReceive();
}

/* ========================================================================== */
/* FAKE APP                                                                    */
/*
 * Fake App uses the SAME Control_ApplyCommand() as real USART1 RX.
 * It can test command parsing, target length, encoder closed-loop movement,
 * and IDLE/HOLDING blocking logic without the ESP32/App.
 *
 * It does NOT test the physical USART1 RX wiring or interrupt path itself.
 */
/* ========================================================================== */

static void FakeApp_Process(void)
{
  uint8_t command;
  int16_t magnitude;
  int16_t decodedValue;
  uint8_t valid;

  if (fakeAppTrigger == 0U)
  {
    return;
  }

  /*
   * Fake App mirrors the real 2-byte protocol:
   *
   *   command 2, value 6 -> -6 mm
   *   command 3, value 6 -> +6 mm
   *
   * Therefore fakeAppValueMm should be entered as a POSITIVE magnitude.
   */
  command = fakeAppCommand;
  magnitude = fakeAppValueMm;

  fakeAppTrigger = 0U;

  if ((magnitude < 0) || (magnitude > 255))
  {
    fakeAppLastValid = 0U;
    fakeAppInvalidCount++;
    return;
  }

  decodedValue =
      Control_DecodeValue(
          command,
          (uint8_t)magnitude
      );

  valid =
      Control_ApplyCommand(
          command,
          decodedValue
      );

  fakeAppLastValid = valid;

  if (valid != 0U)
  {
    fakeAppCommandCount++;
  }
  else
  {
    fakeAppInvalidCount++;
  }
}

/* ========================================================================== */
/* ENCODER                                                                     */
/* ========================================================================== */

static uint8_t Encoder_ReadAB(void)
{
  uint8_t a;
  uint8_t b;

  a =
      (HAL_GPIO_ReadPin(
           ENCODER_A_GPIO_PORT,
           ENCODER_A_PIN
       ) == GPIO_PIN_SET)
      ? 1U : 0U;

  b =
      (HAL_GPIO_ReadPin(
           ENCODER_B_GPIO_PORT,
           ENCODER_B_PIN
       ) == GPIO_PIN_SET)
      ? 1U : 0U;

  return (uint8_t)((a << 1) | b);
}

static void Encoder_Init(void)
{
  encoder_count = 0;
  encoder_edge_count = 0U;
  encoder_valid_transition_count = 0U;
  encoder_invalid_transition_count = 0U;
  encoder_invalid_latched = 0U;
  encoder_overflow_latched = 0U;

  encoder_prev_ab = Encoder_ReadAB();
  encoder_valid = 1U;

  encoder_zero_count = 0;
  encoder_position_zeroed = 0U;
  calibration_required = 1U;
  encoder_set_zero_request = 0U;
  encoder_set_zero_status = 0;

  currentLengthMm = INITIAL_CABLE_LENGTH_MM;
  targetLengthMm = INITIAL_CABLE_LENGTH_MM;
  lengthErrorMm = 0.0f;

  lengthAdjustPending = 0U;
  lengthAdjustActive = 0U;
  lengthAdjustBlocked = 0U;

  encoderLengthCalibrated =
      (ENCODER_COUNTS_PER_MM > 0.0f) ? 1U : 0U;
}

static void Encoder_ProcessSetZeroRequest(void)
{
  if (encoder_set_zero_request == 0U)
  {
    return;
  }

  encoder_set_zero_request = 0U;
  encoder_set_zero_status = 0;

  /*
   * 0823 SetZero is accepted only while the bridge is forced safe and the
   * encoder has no latched invalid/overflow condition.
   */
  Motor_ForceSafe();

  if ((encoder_valid == 0U) ||
      (encoder_invalid_latched != 0U) ||
      (encoder_overflow_latched != 0U))
  {
    encoder_position_zeroed = 0U;
    calibration_required = 1U;
    encoder_set_zero_status = -1;
    return;
  }

  encoder_zero_count = encoder_count;
  encoder_position_zeroed = 1U;
  calibration_required = 0U;
  encoder_set_zero_status = 1;
}

static void Encoder_UpdateLength(void)
{
  int32_t countSnapshot;

  countSnapshot = encoder_count - encoder_zero_count;

  if ((ENCODER_COUNTS_PER_MM > 0.0f) &&
      (encoder_position_zeroed != 0U))
  {
    currentLengthMm =
        INITIAL_CABLE_LENGTH_MM +
        (ENCODER_LENGTH_SIGN *
         ((float)countSnapshot /
          ENCODER_COUNTS_PER_MM));

    encoderLengthCalibrated = 1U;
  }
  else
  {
    /*
     * Raw encoder_count still works.
     * mm control remains locked until calibration.
     */
    currentLengthMm = INITIAL_CABLE_LENGTH_MM;
    encoderLengthCalibrated = 0U;
  }

  lengthErrorMm =
      targetLengthMm - currentLengthMm;
}

/*
 * Return 1:
 * App length control owns / blocks motor control in this update.
 *
 * Return 0:
 * Normal tremor state machine may continue.
 */
static uint8_t Length_Adjustment_Update(void)
{
  Encoder_UpdateLength();

  if (lengthAdjustPending == 0U)
  {
    lengthAdjustActive = 0U;
    lengthAdjustBlocked = 0U;
    return 0U;
  }

  /*
   * Only IDLE / HOLDING may execute length adjustment.
   */
  if ((actuator_state != ACTUATOR_IDLE) &&
      (actuator_state != ACTUATOR_HOLDING))
  {
    lengthAdjustActive = 0U;
    lengthAdjustBlocked = 1U;
    return 0U;
  }

  /*
   * Tremor suppression has priority while IDLE.
   */
  if ((actuator_state == ACTUATOR_IDLE) &&
      (suppression_start_allowed != 0U))
  {
    lengthAdjustActive = 0U;
    lengthAdjustBlocked = 1U;
    return 0U;
  }

  /*
   * Safety lock before counts/mm calibration.
   */
  if (encoderLengthCalibrated == 0U)
  {
    Motor_UpdateWithDeadtime(MOTOR_STOP);

    lengthAdjustActive = 0U;
    lengthAdjustBlocked = 1U;

    return 1U;
  }

  lengthAdjustBlocked = 0U;

  if (fabsf(lengthErrorMm) <= LENGTH_TOLERANCE_MM)
  {
    Motor_UpdateWithDeadtime(MOTOR_STOP);

    lengthAdjustActive = 0U;
    lengthAdjustPending = 0U;

    lengthAdjustCompleteCount++;

    return 1U;
  }

  lengthAdjustActive = 1U;

  if (lengthErrorMm > 0.0f)
  {
    /* Too tight -> longer cable -> release */
    Motor_UpdateWithDeadtime(MOTOR_RELEASE_DIRECTION);
  }
  else
  {
    /* Too loose -> shorter cable -> tighten */
    Motor_UpdateWithDeadtime(MOTOR_PULL_DIRECTION);
  }

  return 1U;
}

/* ========================================================================== */
/* MOTOR                                                                       */
/* ========================================================================== */

static uint32_t Motor_DutyPercentToCcr(uint8_t dutyPercent)
{
  uint32_t ccr;

  if (dutyPercent > 100U)
  {
    dutyPercent = 100U;
  }

  ccr =
      ((uint32_t)dutyPercent * MOTOR_PWM_FULL_SCALE_CCR) /
      100U;

  if (ccr >= MOTOR_PWM_FULL_SCALE_CCR)
  {
    ccr = MOTOR_PWM_FULL_SCALE_CCR - 1U;
  }

  return ccr;
}

static void Motor_ForceSafe(void)
{
  /*
   * This may also be called from Error_Handler before all peripherals have
   * finished initialization, so make the GPIO writes self-contained and touch
   * TIM1 only after htim1.Instance has been assigned.
   */
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOG_CLK_ENABLE();
  __HAL_RCC_GPIOK_CLK_ENABLE();

  /* 0823 ForceSafe ordering: STBY low, PWM zero, direction inputs low. */
  HAL_GPIO_WritePin(MOTOR_STBY_GPIO_PORT, MOTOR_STBY_PIN, GPIO_PIN_RESET);

  if (htim1.Instance == TIM1)
  {
    __HAL_TIM_SET_COMPARE(&htim1, MOTOR_PWM_CHANNEL, 0U);
  }

  HAL_GPIO_WritePin(MOTOR_AIN1_GPIO_PORT, MOTOR_AIN1_PIN, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(MOTOR_AIN2_GPIO_PORT, MOTOR_AIN2_PIN, GPIO_PIN_RESET);

  motor_applied_ccr = 0U;
  motor_applied_ain1 = 0U;
  motor_applied_ain2 = 0U;
  motor_applied_stby = 0U;
  motor_output_active_debug = 0U;
  motor_applied_state = MOTOR_STOP;
}

static void Motor_InitSafePwm(void)
{
  Motor_ForceSafe();

  /*
   * TIM1 is the 20 kHz carrier. Starting the channel with CCR=0 is safe and
   * allows later updates without software-generated PWM.
   */
  motor_pwm_start_status =
      HAL_TIM_PWM_Start(&htim1, MOTOR_PWM_CHANNEL);

  __HAL_TIM_SET_COMPARE(&htim1, MOTOR_PWM_CHANNEL, 0U);
  Motor_ForceSafe();
}

void Motor_Control(MotorState state)
{
  uint32_t ccr;

  /*
   * 0823 authoritative motion chain:
   * hardened gate -> SuppressionControl -> PositionGuard -> TB6612 output.
   *
   * This supplied project does not yet contain the authoritative
   * SuppressionControl/PositionGuard integration, so physical output remains
   * fail-safe locked. This prevents a gate result alone from energizing the
   * bridge.
   */
  suppression_control_ready_debug =
      (SUPPRESSION_CONTROL_INTEGRATED != 0U) ? 1U : 0U;

  motor_output_guard_ready_debug =
      (MOTOR_POSITION_GUARD_INTEGRATED != 0U) ? 1U : 0U;

  if ((state == MOTOR_STOP) ||
      (actuation_permitted_debug == 0U) ||
      (suppression_control_ready_debug == 0U) ||
      (motor_output_guard_ready_debug == 0U) ||
      (calibration_required != 0U) ||
      (encoder_position_zeroed == 0U) ||
      (encoder_valid == 0U) ||
      (encoder_invalid_latched != 0U) ||
      (encoder_overflow_latched != 0U) ||
      (motor_pwm_start_status != HAL_OK))
  {
    Motor_ForceSafe();
    return;
  }

  ccr = Motor_DutyPercentToCcr(motorIntensityPercent);

  if (ccr == 0U)
  {
    Motor_ForceSafe();
    return;
  }

  if (state == MOTOR_FORWARD)
  {
    HAL_GPIO_WritePin(MOTOR_AIN1_GPIO_PORT, MOTOR_AIN1_PIN, GPIO_PIN_SET);
    HAL_GPIO_WritePin(MOTOR_AIN2_GPIO_PORT, MOTOR_AIN2_PIN, GPIO_PIN_RESET);
    motor_applied_ain1 = 1U;
    motor_applied_ain2 = 0U;
  }
  else if (state == MOTOR_REVERSE)
  {
    HAL_GPIO_WritePin(MOTOR_AIN1_GPIO_PORT, MOTOR_AIN1_PIN, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(MOTOR_AIN2_GPIO_PORT, MOTOR_AIN2_PIN, GPIO_PIN_SET);
    motor_applied_ain1 = 0U;
    motor_applied_ain2 = 1U;
  }
  else
  {
    Motor_ForceSafe();
    return;
  }

  __HAL_TIM_SET_COMPARE(&htim1, MOTOR_PWM_CHANNEL, ccr);
  HAL_GPIO_WritePin(MOTOR_STBY_GPIO_PORT, MOTOR_STBY_PIN, GPIO_PIN_SET);

  motor_applied_ccr = ccr;
  motor_applied_stby = 1U;
  motor_output_active_debug = 1U;
}

void Motor_Deadtime_Reset(void)
{
  Motor_Control(MOTOR_STOP);

  motor_applied_state = MOTOR_STOP;
  motor_last_drive_direction = MOTOR_STOP;
  motor_pending_direction = MOTOR_STOP;

  motor_reverse_wait_active = 0U;

  motor_stop_started_ms = HAL_GetTick();
  motor_reverse_wait_elapsed_ms = 0U;
}

void Motor_UpdateWithDeadtime(MotorState requestedState)
{
  uint32_t nowMs;

  nowMs = HAL_GetTick();

  if ((requestedState != MOTOR_STOP) &&
      (requestedState != MOTOR_FORWARD) &&
      (requestedState != MOTOR_REVERSE))
  {
    requestedState = MOTOR_STOP;
  }

  if (requestedState == MOTOR_STOP)
  {
    if (motor_applied_state != MOTOR_STOP)
    {
      motor_stop_started_ms = nowMs;
    }

    Motor_Control(MOTOR_STOP);
    motor_applied_state = MOTOR_STOP;

    if ((motor_last_drive_direction != MOTOR_STOP) ||
        (motor_reverse_wait_active != 0U))
    {
      motor_reverse_wait_elapsed_ms =
          nowMs - motor_stop_started_ms;

      if (motor_reverse_wait_elapsed_ms >=
          MOTOR_REVERSE_DEADTIME_MS)
      {
        motor_last_drive_direction = MOTOR_STOP;
        motor_pending_direction = MOTOR_STOP;
        motor_reverse_wait_active = 0U;
        motor_reverse_wait_elapsed_ms = 0U;
      }
    }
    else
    {
      motor_reverse_wait_elapsed_ms = 0U;
    }

    return;
  }

  /*
   * If stopped, or continuing same direction, drive immediately.
   */
  if ((motor_last_drive_direction == MOTOR_STOP) ||
      (requestedState == motor_last_drive_direction))
  {
    Motor_Control(requestedState);

    if (motor_output_active_debug != 0U)
    {
      motor_applied_state = requestedState;
      motor_last_drive_direction = requestedState;
    }
    else
    {
      motor_applied_state = MOTOR_STOP;
      motor_last_drive_direction = MOTOR_STOP;
    }

    motor_pending_direction = MOTOR_STOP;

    motor_reverse_wait_active = 0U;
    motor_reverse_wait_elapsed_ms = 0U;

    return;
  }

  /*
   * Direction reversal:
   * stop first.
   */
  if (motor_applied_state != MOTOR_STOP)
  {
    Motor_Control(MOTOR_STOP);

    motor_applied_state = MOTOR_STOP;
    motor_stop_started_ms = nowMs;
  }

  if ((motor_reverse_wait_active == 0U) ||
      (motor_pending_direction != requestedState))
  {
    motor_pending_direction = requestedState;
    motor_reverse_wait_active = 1U;
    motor_reverse_event_count++;
  }

  motor_reverse_wait_elapsed_ms =
      nowMs - motor_stop_started_ms;

  if (motor_reverse_wait_elapsed_ms >=
      MOTOR_REVERSE_DEADTIME_MS)
  {
    Motor_Control(requestedState);

    if (motor_output_active_debug != 0U)
    {
      motor_applied_state = requestedState;
      motor_last_drive_direction = requestedState;
    }
    else
    {
      motor_applied_state = MOTOR_STOP;
      motor_last_drive_direction = MOTOR_STOP;
    }

    motor_pending_direction = MOTOR_STOP;

    motor_reverse_wait_active = 0U;
    motor_reverse_wait_elapsed_ms = 0U;
  }
  else
  {
    Motor_Control(MOTOR_STOP);
    motor_applied_state = MOTOR_STOP;
  }
}

/* ========================================================================== */
/* ACTUATOR STATE MACHINE                                                      */
/* ========================================================================== */

void Actuator_StateMachine_Reset(void)
{
  Motor_Deadtime_Reset();

  actuator_state = ACTUATOR_IDLE;
  actuator_state_started_ms = HAL_GetTick();
  actuator_state_elapsed_ms = 0U;
}

void Actuator_StateMachine_Update(void)
{
  uint32_t nowMs;

  nowMs = HAL_GetTick();

  actuator_state_elapsed_ms =
      nowMs - actuator_state_started_ms;

  switch (actuator_state)
  {
    case ACTUATOR_IDLE:

      actuator_state_elapsed_ms = 0U;

      /*
       * Tremor suppression has priority.
       */
      if (suppression_start_allowed != 0U)
      {
        if (lengthAdjustPending != 0U)
        {
          lengthAdjustActive = 0U;
          lengthAdjustBlocked = 1U;
        }

        actuator_state = ACTUATOR_PULLING;
        actuator_state_started_ms = nowMs;
        actuator_state_elapsed_ms = 0U;

        actuator_pull_count++;

        Motor_UpdateWithDeadtime(MOTOR_PULL_DIRECTION);
        break;
      }

      /*
       * App adjustment is allowed in IDLE.
       */
      if (Length_Adjustment_Update() != 0U)
      {
        break;
      }

      Motor_UpdateWithDeadtime(MOTOR_STOP);
      break;

    case ACTUATOR_PULLING:

      if (lengthAdjustPending != 0U)
      {
        lengthAdjustActive = 0U;
        lengthAdjustBlocked = 1U;
      }

      if (actuator_state_elapsed_ms >=
          MOTOR_PULL_TIME_MS)
      {
        Motor_UpdateWithDeadtime(MOTOR_STOP);

        actuator_state = ACTUATOR_HOLDING;
        actuator_state_started_ms = nowMs;
        actuator_state_elapsed_ms = 0U;
      }
      else
      {
        Motor_UpdateWithDeadtime(MOTOR_PULL_DIRECTION);
      }

      break;

    case ACTUATOR_HOLDING:

      /*
       * If tremor disappeared, finish normal RETURNING first.
       * Pending App adjustment is kept and will run in IDLE.
       */
      /*
       * 0823: legacy tremor_active / freqEstimate are diagnostics only.
       * Leave HOLDING when the hardened gate-level permission disappears.
       */
      if (suppression_start_allowed == 0U)
      {
        if (lengthAdjustPending != 0U)
        {
          lengthAdjustActive = 0U;
          lengthAdjustBlocked = 1U;
        }

        actuator_state = ACTUATOR_RETURNING;
        actuator_state_started_ms = nowMs;
        actuator_state_elapsed_ms = 0U;

        actuator_return_count++;

        Motor_UpdateWithDeadtime(MOTOR_RELEASE_DIRECTION);
        break;
      }

      /*
       * Tremor still active:
       * App adjustment is allowed in HOLDING.
       */
      if (Length_Adjustment_Update() != 0U)
      {
        break;
      }

      Motor_UpdateWithDeadtime(MOTOR_STOP);
      break;

    case ACTUATOR_RETURNING:

      if (lengthAdjustPending != 0U)
      {
        lengthAdjustActive = 0U;
        lengthAdjustBlocked = 1U;
      }

      if (actuator_state_elapsed_ms >=
          MOTOR_RELEASE_TIME_MS)
      {
        Motor_UpdateWithDeadtime(MOTOR_STOP);

        actuator_state = ACTUATOR_IDLE;
        actuator_state_started_ms = nowMs;
        actuator_state_elapsed_ms = 0U;
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

/* ========================================================================== */
/* ALGORITHM                                                                   */
/* ========================================================================== */

void Tremor_Gate_Reset(void)
{
  selectedGyroInputDps = 0.0;
  tremorPowerEma = 0.0;
  tremorRmsDps = 0.0;
  controlValueDebug = 0.0;

  tremor_active = 0U;
  frequency_gate_ok = 0U;
  amplitude_gate_ok = 0U;

  tremor_on_count = 0U;
  tremor_off_count = 0U;
  algo_warmup_count = 0U;
}

void Algorithm_Init(void)
{
  eHWFLC_KF_step_init();
  Tremor_Gate_Reset();
}

void Bandpass_TremorGate_Init(void)
{
  bandpass_tremor_gate_config =
      TremorGate_DefaultConfig();

  TremorGate_Init(
      &bandpass_tremor_gate,
      &bandpass_tremor_gate_config
  );

  Bandpass_TremorGate_Reset();
}

void Bandpass_TremorGate_Reset(void)
{
  TremorGate_Reset(&bandpass_tremor_gate);

  bandpass_gate_enabled = 0U;
  gate_enabled_debug = 0U;
  hardened_gate_ready = 0U;
  hardened_gate_fault = (uint8_t)TREMOR_GATE_FAULT_NONE;
  gate_precondition_ok_debug = 0U;
  suppression_control_ready_debug =
      (SUPPRESSION_CONTROL_INTEGRATED != 0U) ? 1U : 0U;
  actuation_permitted_debug = 0U;
  suppression_start_allowed = 0U;

  bandpass_tremor_envelope = 0.0f;
  bandpass_voluntary_envelope = 0.0f;
  bandpass_tremor_ratio = 0.0f;

  bandpass_on_count = 0U;
  bandpass_off_count = 0U;
}

void Bandpass_TremorGate_Update(double gyroDps)
{
  bandpass_gate_enabled =
      TremorGate_Update(
          &bandpass_tremor_gate,
          gyroDps
      );

  bandpass_tremor_envelope =
      bandpass_tremor_gate.tremor_envelope;

  bandpass_voluntary_envelope =
      bandpass_tremor_gate.voluntary_envelope;

  bandpass_tremor_ratio =
      bandpass_tremor_gate.tremor_ratio;

  bandpass_on_count =
      bandpass_tremor_gate.on_count;

  bandpass_off_count =
      bandpass_tremor_gate.off_count;

  /*
   * 0823 motor-start condition at the gate layer:
   *   - hardened TremorGate must be healthy
   *   - hardened TremorGate must be enabled
   *   - eHWFLC freqEstimate / tremor_active do not authorize the motor
   *
   * Full 0823 final integration requires the authoritative SuppressionControl
   * output and MotorPositionGuard before physical motion is permitted.
   */
  hardened_gate_ready = TremorGate_IsReady(&bandpass_tremor_gate);
  hardened_gate_fault = bandpass_tremor_gate.last_fault;
  gate_enabled_debug = bandpass_gate_enabled;

  gate_precondition_ok_debug =
      ((hardened_gate_ready != 0U) &&
       (hardened_gate_fault == (uint8_t)TREMOR_GATE_FAULT_NONE) &&
       (gate_enabled_debug != 0U))
      ? 1U : 0U;

  /*
   * 0823 explicitly separates gate_enabled from actuation_permitted.
   * Do NOT promote the gate directly to motor permission.
   *
   * The authoritative SuppressionControl source/API was not supplied, so the
   * only compliant fail-safe value here is 0 until that module is integrated.
   */
  suppression_control_ready_debug =
      (SUPPRESSION_CONTROL_INTEGRATED != 0U) ? 1U : 0U;

  actuation_permitted_debug = 0U;
  suppression_start_allowed = 0U;
}

void Tremor_Detector_Update(float gx, float gy, float gz)
{
  double inputGyro;
  double instantaneousPower;
  uint8_t keepActive;
  uint32_t t0;

#if (TREMOR_INPUT_AXIS == TREMOR_AXIS_X)
  selectedGyroInputDps = (double)gx;
#elif (TREMOR_INPUT_AXIS == TREMOR_AXIS_Y)
  selectedGyroInputDps = (double)gy;
#elif (TREMOR_INPUT_AXIS == TREMOR_AXIS_Z)
  selectedGyroInputDps = (double)gz;
#else
#error "TREMOR_INPUT_AXIS must be X, Y, or Z"
#endif

  inputGyro = selectedGyroInputDps;

  t0 = DWT->CYCCNT;

  eHWFLC_KF_step(
      inputGyro,
      &tremorEstimate,
      &freqEstimate
  );

  algo_cycles = DWT->CYCCNT - t0;

  algo_time_us =
      (float)algo_cycles /
      ((float)SystemCoreClock / 1000000.0f);

  if ((!isfinite(tremorEstimate)) ||
      (!isfinite(freqEstimate)))
  {
    Tremor_Gate_Reset();
    return;
  }

  instantaneousPower =
      tremorEstimate * tremorEstimate;

  tremorPowerEma +=
      TREMOR_POWER_EMA_ALPHA *
      (instantaneousPower - tremorPowerEma);

  if (tremorPowerEma < 0.0)
  {
    tremorPowerEma = 0.0;
  }

  tremorRmsDps = sqrt(tremorPowerEma);

  /*
   * 200 samples @ 100 Hz = 2 seconds warm-up.
   */
  if (algo_warmup_count <
      ALGO_WARMUP_SAMPLES)
  {
    algo_warmup_count++;
    controlValueDebug = 0.0;
    return;
  }

  if (tremor_active == 0U)
  {
    frequency_gate_ok =
        ((freqEstimate >= TREMOR_FREQ_ON_MIN_HZ) &&
         (freqEstimate <= TREMOR_FREQ_ON_MAX_HZ))
        ? 1U : 0U;

    amplitude_gate_ok =
        (tremorRmsDps >= TREMOR_RMS_ON_DPS)
        ? 1U : 0U;

    if ((frequency_gate_ok != 0U) &&
        (amplitude_gate_ok != 0U))
    {
      if (tremor_on_count <
          TREMOR_ON_CONFIRM_SAMPLES)
      {
        tremor_on_count++;
      }
    }
    else
    {
      tremor_on_count = 0U;
    }

    if (tremor_on_count >=
        TREMOR_ON_CONFIRM_SAMPLES)
    {
      tremor_active = 1U;
      tremor_on_count = 0U;
      tremor_off_count = 0U;
    }
  }
  else
  {
    frequency_gate_ok =
        ((freqEstimate >= TREMOR_FREQ_OFF_MIN_HZ) &&
         (freqEstimate <= TREMOR_FREQ_OFF_MAX_HZ))
        ? 1U : 0U;

    amplitude_gate_ok =
        (tremorRmsDps >= TREMOR_RMS_OFF_DPS)
        ? 1U : 0U;

    keepActive =
        ((frequency_gate_ok != 0U) &&
         (amplitude_gate_ok != 0U))
        ? 1U : 0U;

    if (keepActive == 0U)
    {
      if (tremor_off_count <
          TREMOR_OFF_CONFIRM_SAMPLES)
      {
        tremor_off_count++;
      }
    }
    else
    {
      tremor_off_count = 0U;
    }

    if (tremor_off_count >=
        TREMOR_OFF_CONFIRM_SAMPLES)
    {
      tremor_active = 0U;

      tremor_on_count = 0U;
      tremor_off_count = 0U;

      controlValueDebug = 0.0;
      return;
    }
  }

  if (tremor_active == 0U)
  {
    controlValueDebug = 0.0;
    return;
  }

  controlValueDebug =
      -(MOTOR_GAIN * tremorEstimate);
}

/* ========================================================================== */
/* IMU                                                                         */
/* ========================================================================== */

void Read_IMU_TestData(float *gx, float *gy, float *gz)
{
  static uint32_t sampleIndex = 0U;

  double phase;
  float testValue;

  phase =
      2.0 *
      PI_D *
      TEST_TREMOR_FREQ_HZ *
      ((double)sampleIndex /
       CONTROL_SAMPLE_RATE_HZ);

  testValue =
      (float)(
          TEST_TREMOR_AMPLITUDE_DPS *
          sin(phase)
      );

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

  if (sampleIndex >=
      (uint32_t)CONTROL_SAMPLE_RATE_HZ)
  {
    sampleIndex = 0U;
  }
}

HAL_StatusTypeDef Read_IMU_RealData(
    float *gx,
    float *gy,
    float *gz
)
{
  HAL_StatusTypeDef status;

  status =
      ReadData(
          &BNO055_Data,
          SENSOR_GYRO
      );

  if (status == HAL_OK)
  {
    *gx = BNO055_Data.Gyro.X;
    *gy = BNO055_Data.Gyro.Y;
    *gz = BNO055_Data.Gyro.Z;

    gyroXRaw =
        (int16_t)(
            BNO055_Data.Gyro.X *
            16.0f
        );

    gyroYRaw =
        (int16_t)(
            BNO055_Data.Gyro.Y *
            16.0f
        );

    gyroZRaw =
        (int16_t)(
            BNO055_Data.Gyro.Z *
            16.0f
        );
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

  /* USER CODE END 1 */
/* USER CODE BEGIN Boot_Mode_Sequence_0 */
  int32_t timeout;
/* USER CODE END Boot_Mode_Sequence_0 */

/* USER CODE BEGIN Boot_Mode_Sequence_1 */
  timeout = 0xFFFF;

  while ((__HAL_RCC_GET_FLAG(RCC_FLAG_D2CKRDY) != RESET) &&
         (timeout-- > 0))
  {
  }

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

  __HAL_RCC_HSEM_CLK_ENABLE();

  HAL_HSEM_FastTake(HSEM_ID_0);

  HAL_HSEM_Release(HSEM_ID_0, 0);

  timeout = 0xFFFF;

  while ((__HAL_RCC_GET_FLAG(RCC_FLAG_D2CKRDY) == RESET) &&
         (timeout-- > 0))
  {
  }

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
  MX_TIM1_Init();
  /* USER CODE BEGIN 2 */

  /* 0823 boot-safe motor state before any control logic is allowed to run. */
  Motor_InitSafePwm();

  Encoder_Init();

  Actuator_StateMachine_Reset();

  DWT_Init();

  Algorithm_Init();

  Bandpass_TremorGate_Init();

  /*
   * Start real ESP32 -> STM32 UART reception.
   */
  Control_StartReceive();

  /* ------------------------------------------------------------------------ */
  /* BNO055 startup probe                                                     */
  /* ------------------------------------------------------------------------ */

  i2c4_scl_level =
      (HAL_GPIO_ReadPin(
           GPIOD,
           GPIO_PIN_12
       ) == GPIO_PIN_SET)
      ? 1U : 0U;

  i2c4_sda_level =
      (HAL_GPIO_ReadPin(
           GPIOD,
           GPIO_PIN_13
       ) == GPIO_PIN_SET)
      ? 1U : 0U;

  /* First try 0x28 */
  bno_ready_28 =
      HAL_I2C_IsDeviceReady(
          &hi2c4,
          (0x28U << 1),
          3U,
          100U
      );

  i2c4_state_after_28 =
      (uint32_t)hi2c4.State;

  i2c4_error_after_28 =
      (uint32_t)hi2c4.ErrorCode;

  if (bno_ready_28 == HAL_OK)
  {
    bno_ready_29 = HAL_ERROR;
    bno_detected_address = 0x28U;

    bno_probe_chip_id = 0U;

    bno_read_status =
        HAL_I2C_Mem_Read(
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
      bno_init_status =
          Sensor_GyroOnly_Init();

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
    I2C4_RecoverAndReInit();

    i2c4_scl_level =
        (HAL_GPIO_ReadPin(
             GPIOD,
             GPIO_PIN_12
         ) == GPIO_PIN_SET)
        ? 1U : 0U;

    i2c4_sda_level =
        (HAL_GPIO_ReadPin(
             GPIOD,
             GPIO_PIN_13
         ) == GPIO_PIN_SET)
        ? 1U : 0U;

    /* Try 0x29 */
    bno_ready_29 =
        HAL_I2C_IsDeviceReady(
            &hi2c4,
            (0x29U << 1),
            3U,
            100U
        );

    i2c4_state_after_29 =
        (uint32_t)hi2c4.State;

    i2c4_error_after_29 =
        (uint32_t)hi2c4.ErrorCode;

    if (bno_ready_29 == HAL_OK)
    {
      bno_detected_address = 0x29U;

      bno_probe_chip_id = 0U;

      bno_read_status =
          HAL_I2C_Mem_Read(
              &hi2c4,
              (0x29U << 1),
              CHIP_ID_ADDR,
              I2C_MEMADD_SIZE_8BIT,
              (uint8_t *)&bno_probe_chip_id,
              1U,
              100U
          );

      /*
       * Existing driver is still compiled for 0x28.
       * Keep real actuator disabled if module is actually 0x29.
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

  i2c4_scl_level =
      (HAL_GPIO_ReadPin(
           GPIOD,
           GPIO_PIN_12
       ) == GPIO_PIN_SET)
      ? 1U : 0U;

  i2c4_sda_level =
      (HAL_GPIO_ReadPin(
           GPIOD,
           GPIO_PIN_13
       ) == GPIO_PIN_SET)
      ? 1U : 0U;

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
     * Fake App is checked continuously.
     * When you write fakeAppTrigger = 1 in Live Expressions,
     * this function processes the request once and clears trigger back to 0.
     */
    FakeApp_Process();
    Encoder_ProcessSetZeroRequest();

    if (tick_flag != 0U)
    {
      tick_flag = 0U;

      control_tick_count++;
      fakeAppHeartbeat++;

      if (imu_ready != 0U)
      {
        bno_read_status =
            Read_IMU_RealData(
                &gyroX,
                &gyroY,
                &gyroZ
            );

        if (bno_read_status == HAL_OK)
        {
          imu_read_ok_count++;
          imu_consecutive_error_count = 0U;
        }
        else
        {
          imu_read_error_count++;
          imu_consecutive_error_count++;

          if (imu_consecutive_error_count >= 5U)
          {
            imu_ready = 0U;
            using_test_data = 1U;

            Tremor_Gate_Reset();
            Bandpass_TremorGate_Reset();
            Motor_ForceSafe();
          }
        }
      }

      /*
       * If real BNO055 is unavailable,
       * algorithm may still run on internal 5 Hz data.
       * Real actuator remains reset below.
       */
      if (imu_ready == 0U)
      {
        Read_IMU_TestData(
            &gyroX,
            &gyroY,
            &gyroZ
        );
      }

      Tremor_Detector_Update(
          gyroX,
          gyroY,
          gyroZ
      );

      Bandpass_TremorGate_Update(
          selectedGyroInputDps
      );

      algo_call_count++;

      Encoder_UpdateLength();

      /*
       * 0823: fake/test IMU data may exercise algorithms, but may never drive
       * the real actuator. Also, because authoritative SuppressionControl and
       * PositionGuard are not yet integrated, the physical output remains safe.
       */
      if ((imu_ready != 0U) &&
          (bno_read_status == HAL_OK) &&
          (suppression_control_ready_debug != 0U) &&
          (motor_output_guard_ready_debug != 0U))
      {
        Actuator_StateMachine_Update();
      }
      else
      {
        Actuator_StateMachine_Reset();
        Motor_ForceSafe();
      }

      Tremor_TransmitCurrentSample(
          ((imu_ready != 0U) &&
           (bno_read_status == HAL_OK))
          ? 1U : 0U
      );
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
  * @brief TIM1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_TIM1_Init(void)
{

  /* USER CODE BEGIN TIM1_Init 0 */

  /* USER CODE END TIM1_Init 0 */

  TIM_ClockConfigTypeDef sClockSourceConfig = {0};
  TIM_MasterConfigTypeDef sMasterConfig = {0};
  TIM_OC_InitTypeDef sConfigOC = {0};
  TIM_BreakDeadTimeConfigTypeDef sBreakDeadTimeConfig = {0};

  /* USER CODE BEGIN TIM1_Init 1 */

  /* USER CODE END TIM1_Init 1 */
  htim1.Instance = TIM1;
  htim1.Init.Prescaler = 0;
  htim1.Init.CounterMode = TIM_COUNTERMODE_UP;
  htim1.Init.Period = 3199;
  htim1.Init.ClockDivision = TIM_CLOCKDIVISION_DIV1;
  htim1.Init.RepetitionCounter = 0;
  htim1.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_DISABLE;
  if (HAL_TIM_Base_Init(&htim1) != HAL_OK)
  {
    Error_Handler();
  }
  sClockSourceConfig.ClockSource = TIM_CLOCKSOURCE_INTERNAL;
  if (HAL_TIM_ConfigClockSource(&htim1, &sClockSourceConfig) != HAL_OK)
  {
    Error_Handler();
  }
  if (HAL_TIM_PWM_Init(&htim1) != HAL_OK)
  {
    Error_Handler();
  }
  sMasterConfig.MasterOutputTrigger = TIM_TRGO_RESET;
  sMasterConfig.MasterOutputTrigger2 = TIM_TRGO2_RESET;
  sMasterConfig.MasterSlaveMode = TIM_MASTERSLAVEMODE_DISABLE;
  if (HAL_TIMEx_MasterConfigSynchronization(&htim1, &sMasterConfig) != HAL_OK)
  {
    Error_Handler();
  }
  sConfigOC.OCMode = TIM_OCMODE_PWM1;
  sConfigOC.Pulse = 0;
  sConfigOC.OCPolarity = TIM_OCPOLARITY_HIGH;
  sConfigOC.OCNPolarity = TIM_OCNPOLARITY_HIGH;
  sConfigOC.OCFastMode = TIM_OCFAST_DISABLE;
  sConfigOC.OCIdleState = TIM_OCIDLESTATE_RESET;
  sConfigOC.OCNIdleState = TIM_OCNIDLESTATE_RESET;
  if (HAL_TIM_PWM_ConfigChannel(&htim1, &sConfigOC, TIM_CHANNEL_1) != HAL_OK)
  {
    Error_Handler();
  }
  sBreakDeadTimeConfig.OffStateRunMode = TIM_OSSR_DISABLE;
  sBreakDeadTimeConfig.OffStateIDLEMode = TIM_OSSI_DISABLE;
  sBreakDeadTimeConfig.LockLevel = TIM_LOCKLEVEL_OFF;
  sBreakDeadTimeConfig.DeadTime = 0;
  sBreakDeadTimeConfig.BreakState = TIM_BREAK_DISABLE;
  sBreakDeadTimeConfig.BreakPolarity = TIM_BREAKPOLARITY_HIGH;
  sBreakDeadTimeConfig.BreakFilter = 0;
  sBreakDeadTimeConfig.Break2State = TIM_BREAK2_DISABLE;
  sBreakDeadTimeConfig.Break2Polarity = TIM_BREAK2POLARITY_HIGH;
  sBreakDeadTimeConfig.Break2Filter = 0;
  sBreakDeadTimeConfig.AutomaticOutput = TIM_AUTOMATICOUTPUT_DISABLE;
  if (HAL_TIMEx_ConfigBreakDeadTime(&htim1, &sBreakDeadTimeConfig) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN TIM1_Init 2 */

  /* USER CODE END TIM1_Init 2 */
  HAL_TIM_MspPostInit(&htim1);

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
  __HAL_RCC_GPIOB_CLK_ENABLE();
  __HAL_RCC_GPIOC_CLK_ENABLE();
  __HAL_RCC_GPIOI_CLK_ENABLE();
  __HAL_RCC_GPIOE_CLK_ENABLE();
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOG_CLK_ENABLE();
  __HAL_RCC_GPIOH_CLK_ENABLE();
  __HAL_RCC_GPIOD_CLK_ENABLE();
  __HAL_RCC_GPIOK_CLK_ENABLE();

  /*
   * 0823 boot-safe bridge levels MUST be established before enabling outputs.
   * STBY also requires the external ~10 kOhm pulldown to GND.
   */
  HAL_GPIO_WritePin(MOTOR_AIN1_GPIO_PORT, MOTOR_AIN1_PIN, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(MOTOR_AIN2_GPIO_PORT, MOTOR_AIN2_PIN, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(MOTOR_STBY_GPIO_PORT, MOTOR_STBY_PIN, GPIO_PIN_RESET);

  /* AIN1 PG3, AIN2 PA6, STBY PK1 */
  GPIO_InitStruct.Pin = MOTOR_AIN1_PIN;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(MOTOR_AIN1_GPIO_PORT, &GPIO_InitStruct);

  GPIO_InitStruct.Pin = MOTOR_AIN2_PIN;
  HAL_GPIO_Init(MOTOR_AIN2_GPIO_PORT, &GPIO_InitStruct);

  GPIO_InitStruct.Pin = MOTOR_STBY_PIN;
  HAL_GPIO_Init(MOTOR_STBY_GPIO_PORT, &GPIO_InitStruct);

  /*
   * Encoder x4 path: both A/B edges trigger EXTI; callback reads both levels
   * and applies the quadrature transition table.
   */
  GPIO_InitStruct.Pin = ENCODER_B_PIN;
  GPIO_InitStruct.Mode = GPIO_MODE_IT_RISING_FALLING;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(ENCODER_B_GPIO_PORT, &GPIO_InitStruct);

  GPIO_InitStruct.Pin = ENCODER_A_PIN;
  GPIO_InitStruct.Mode = GPIO_MODE_IT_RISING_FALLING;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(ENCODER_A_GPIO_PORT, &GPIO_InitStruct);

  /* EXTI interrupt init */
  HAL_NVIC_SetPriority(EXTI9_5_IRQn, 5, 0);
  HAL_NVIC_EnableIRQ(EXTI9_5_IRQn);
}

/* USER CODE BEGIN 4 */

/* ========================================================================== */
/* TIM6 callback                                                               */
/* ========================================================================== */

void HAL_TIM_PeriodElapsedCallback(
    TIM_HandleTypeDef *htim
)
{
  if (htim->Instance == TIM6)
  {
    tim6_irq_count++;
    software_tick_count++;
    tick_flag = 1U;
  }
}

/* ========================================================================== */
/* Encoder EXTI callback                                                       */
/* ========================================================================== */

void HAL_GPIO_EXTI_Callback(
    uint16_t GPIO_Pin
)
{
  static const int8_t transitionTable[16] =
  {
     0, -1,  1,  0,
     1,  0,  0, -1,
    -1,  0,  0,  1,
     0,  1, -1,  0
  };

  uint8_t currentAB;
  uint8_t index;
  int8_t delta;

  if ((GPIO_Pin != ENCODER_A_PIN) &&
      (GPIO_Pin != ENCODER_B_PIN))
  {
    return;
  }

  encoder_edge_count++;

  currentAB = Encoder_ReadAB();

  index =
      (uint8_t)(
          (encoder_prev_ab << 2) |
          currentAB
      );

  delta = transitionTable[index];

  if (delta > 0)
  {
    if (encoder_count == INT32_MAX)
    {
      encoder_overflow_latched = 1U;
      encoder_valid = 0U;
      Motor_ForceSafe();
    }
    else
    {
      encoder_count++;
      encoder_valid_transition_count++;
    }
  }
  else if (delta < 0)
  {
    if (encoder_count == INT32_MIN)
    {
      encoder_overflow_latched = 1U;
      encoder_valid = 0U;
      Motor_ForceSafe();
    }
    else
    {
      encoder_count--;
      encoder_valid_transition_count++;
    }
  }
  else
  {
    if (encoder_prev_ab != currentAB)
    {
      encoder_invalid_transition_count++;
      encoder_invalid_latched = 1U;
      encoder_valid = 0U;
      Motor_ForceSafe();
    }
  }

  encoder_prev_ab = currentAB;
}

/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /*
   * 0823 fail-safe: any fatal main-level error must remove bridge/PWM output
   * before the CPU enters the permanent error loop.
   */
  Motor_ForceSafe();
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
  /* User can add his own implementation to report the file name and line number,
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */

/************************ (C) COPYRIGHT STMicroelectronics *****END OF FILE****/
