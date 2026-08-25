/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Canonical 0822/0823 suppression + guarded TB6612 reference
  *
  * Derived from Ryan d62eb42 without changing Ryan's branch.  This reference
  * is deliberately MOTOR-OFF by default: the bridge cannot be energized until
  * MOTOR_BENCH_CONFIG_APPROVED, explicit runtime arm, encoder SetZero, and all
  * authoritative safety modules agree in the same fresh 100 Hz sample.
  ******************************************************************************
  */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include <stdint.h>
#include <math.h>
#include <string.h>

#include "BNO055_STM32.h"
#include "suppression_control.h"
#include "motor_command_mapper.h"
#include "quadrature_encoder.h"
#include "motor_position_guard.h"
#include "tb6612_driver.h"
#include "stm32_tb6612_hal.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

typedef enum
{
  MOTOR_STOP = 0,
  MOTOR_FORWARD,
  MOTOR_REVERSE
} MotorState;

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
 * PRODUCT-SAFETY LOCK.  Keep zero until every mapper, position, PWM, travel,
 * timeout, direction and encoder-polarity value below has bench evidence and
 * review.  Zero is a supported shadow/gate-validation build, not an error.
 */
#define MOTOR_BENCH_CONFIG_APPROVED      0U

/* User's mechanical convention: forward releases cable.  The final bench
 * check must make direction +1 == RELEASE == encoder count increasing. */
#define MOTOR_RELEASE_AIN1_LEVEL         1U
#define MOTOR_ENCODER_COUNT_POLARITY     1

/* 100 Hz */
#define CONTROL_SAMPLE_RATE_HZ          100.0

/* BNO055 dps telemetry is encoded as signed int16 at 16 LSB/(deg/s).
 * Reject non-finite/out-of-range data before either control or conversion. */
#define GYRO_RAW_LSB_PER_DPS            16.0f
#define GYRO_RAW_MAX_ABS_DPS            2047.0f

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
/* Boot at zero; a reviewed App/bench action must explicitly choose intensity. */
volatile uint8_t motorIntensityPercent = 0U;
static uint8_t controlRxBuffer[CONTROL_PACKET_SIZE] = {0U, 0U};

volatile uint32_t controlRxCount = 0U;
volatile uint32_t controlInvalidCount = 0U;
volatile uint32_t controlUartErrorCount = 0U;

volatile uint8_t lastControlCommand = 0U;
volatile uint8_t lastControlRawValue = 0U;
volatile int16_t lastControlDecodedValue = 0;
volatile uint8_t lastControlValid = 0U;

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
/* Authoritative suppression / actuator chain                                  */
/* -------------------------------------------------------------------------- */
static SuppressionControl suppression_control;
static SuppressionControlOutput suppression_output;
static MotorCommandMapper motor_mapper;
static MotorCommandOutput motor_command_output;
static QuadratureEncoder quadrature_encoder;
static MotorPositionGuard motor_position_guard;
static MotorPositionGuardOutput position_guard_output;
static Tb6612Driver tb6612_driver;
static Tb6612Output tb6612_output;
static Stm32Tb6612Hal tb6612_hal;

/*
 * Deliberately invalid placeholders.  There are no product defaults for
 * torque, travel or timeout.  MOTOR_BENCH_CONFIG_APPROVED remains zero until
 * these two independent mapper records and all position/driver fields are
 * replaced with reviewed bench values.
 */
static const MotorCommandMapperConfig motor_mapper_config = {
  0.0, 0.0, 0.0, 0.0, 0.0, 0U, 1
};
static const MotorCommandMapperConfig approved_motor_mapper_config = {
  0.0, 0.0, 0.0, 0.0, 0.0, 0U, 1
};
static const MotorPositionGuardConfig motor_position_config = {
  0U, 0U, 0U, 0U, 0U, 0U, 0U
};
static const Tb6612DriverConfig tb6612_driver_config = {
  MOTOR_PWM_FULL_SCALE_CCR, 0.0, 0U, MOTOR_RELEASE_AIN1_LEVEL
};

double selectedGyroInputDps = 0.0;
double tremorEstimate = 0.0;
double diagnosticFrequencyHz = 0.0; /* local-only; never a gate/biomarker */
double compensationRequestDps = 0.0;

volatile uint8_t suppression_control_ready_debug = 0U;
volatile uint8_t motor_chain_initialized = 0U;
volatile uint8_t motor_runtime_armed = 0U;
volatile uint8_t motor_bench_config_approved = MOTOR_BENCH_CONFIG_APPROVED;
volatile uint8_t motor_runtime_fault_latched = 0U;

/* Fresh-sample identity: successful BNO reads are the only producer. */
volatile uint32_t imu_sample_generation = 0U;
volatile uint32_t last_controlled_sample_generation = 0U;
volatile uint8_t fresh_sample_available = 0U;
volatile uint32_t stale_sample_reject_count = 0U;

/* Keep gate, permission and applied-output meanings separate. */
volatile uint8_t gate_enabled_debug = 0U;
volatile uint8_t hardened_gate_ready = 0U;
volatile uint8_t gate_precondition_ok_debug = 0U;
volatile uint8_t actuation_permitted_debug = 0U;
/* Compatibility diagnostic only: final same-tick actuator authority after
 * gate, safety chain, arm and calibration checks.  It is not gate_enabled. */
volatile uint8_t suppression_start_allowed = 0U;
volatile uint8_t suppression_fault_debug =
    (uint8_t)SUPPRESSION_CONTROL_FAULT_NONE;

/* -------------------------------------------------------------------------- */
/* Actuator                                                                    */
/* -------------------------------------------------------------------------- */
volatile MotorState motor_applied_state = MOTOR_STOP;
volatile HAL_StatusTypeDef motor_pwm_start_status = HAL_ERROR;
volatile uint32_t motor_applied_ccr = 0U;
volatile uint8_t motor_applied_ain1 = 0U;
volatile uint8_t motor_applied_ain2 = 0U;
volatile uint8_t motor_applied_stby = 0U;
volatile uint8_t motor_output_active_debug = 0U;
volatile uint8_t motor_output_guard_ready_debug = 0U;
volatile int8_t motor_applied_direction = 0;
volatile uint8_t mapper_fault_debug = (uint8_t)MOTOR_MAPPER_FAULT_NONE;
volatile uint8_t position_fault_debug = (uint8_t)MOTOR_POSITION_FAULT_NONE;
volatile uint8_t driver_fault_debug = (uint8_t)TB6612_DRIVER_FAULT_NONE;
volatile uint8_t motor_hal_error_debug = 0U;

/* -------------------------------------------------------------------------- */
/* TIM6 / Debug                                                                */
/* -------------------------------------------------------------------------- */
volatile uint8_t tick_flag = 0U;

uint32_t algo_cycles = 0U;
float algo_time_us = 0.0f;

volatile uint32_t tim6_irq_count = 0U;
volatile uint32_t software_tick_count = 0U;
volatile uint32_t control_tick_count = 0U;
volatile uint32_t scheduler_pending_tick_count = 0U;
volatile uint32_t scheduler_overrun_count = 0U;
volatile uint8_t scheduler_overrun_this_tick = 0U;

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

static uint8_t ControlPipeline_Init(void);
static void ControlPipeline_ForceSafe(void);
static void ControlPipeline_100HzFreshSample(double raw_gyro_dps);
static void ControlPipeline_RejectStaleSample(void);
static double SelectTremorAxisDps(float gx, float gy, float gz);
static uint8_t SnapshotEncoder(QuadratureEncoderSnapshot *snapshot);
static void Encoder_ProcessSetZeroRequest(void);
HAL_StatusTypeDef Read_IMU_RealData(float *gx, float *gy, float *gz);

HAL_StatusTypeDef Sensor_GyroOnly_Init(void);
void I2C4_RecoverAndReInit(void);
void DWT_Init(void);

static void Tremor_TransmitCurrentSample(uint8_t sensorValid);

static void Control_StartReceive(void);
static int16_t Control_DecodeValue(uint8_t command, uint8_t rawValue);
static uint8_t Control_ApplyCommand(uint8_t command, int16_t value);

static void Encoder_Init(void);
static void Encoder_UpdateLength(void);

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

  /* This byte has one meaning only: an ACTIVE command was accepted by the
   * complete safety chain and applied to TB6612 HAL in this control tick. */
  sample.motor_enabled = motor_output_active_debug;
  motorEnabledForApp = sample.motor_enabled;

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
/* AUTHORITATIVE ENCODER + IMMEDIATE HARDWARE SAFE PATH                        */
/* ========================================================================== */

static uint8_t ReadDigitalLevel(GPIO_TypeDef *port, uint16_t pin)
{
  return (HAL_GPIO_ReadPin(port, pin) == GPIO_PIN_SET) ? 1U : 0U;
}

static uint8_t SnapshotEncoder(QuadratureEncoderSnapshot *snapshot)
{
  uint8_t snapshot_ok;
  uint8_t strict_valid;

  if (snapshot == NULL)
  {
    return 0U;
  }

  snapshot_ok = QuadratureEncoder_Snapshot(&quadrature_encoder, snapshot);
  strict_valid =
      ((snapshot_ok == 1U) &&
       (snapshot->initialized == 1U) &&
       (snapshot->invalid_transition_latched == 0U) &&
       (snapshot->overflow_latched == 0U))
      ? 1U : 0U;

  encoder_count = snapshot->count;
  encoder_valid_transition_count = snapshot->valid_transition_count;
  encoder_invalid_transition_count = snapshot->invalid_transition_count;
  encoder_invalid_latched = snapshot->invalid_transition_latched;
  encoder_overflow_latched = snapshot->overflow_latched;
  encoder_valid = strict_valid;
  return strict_valid;
}

static void Encoder_Init(void)
{
  uint8_t initial_a;
  uint8_t initial_b;

  HAL_NVIC_DisableIRQ(EXTI9_5_IRQn);
  initial_a = ReadDigitalLevel(ENCODER_A_GPIO_PORT, ENCODER_A_PIN);
  initial_b = ReadDigitalLevel(ENCODER_B_GPIO_PORT, ENCODER_B_PIN);

  memset(&quadrature_encoder, 0, sizeof(quadrature_encoder));
  encoder_valid = QuadratureEncoder_Init(
      &quadrature_encoder,
      initial_a,
      initial_b,
      MOTOR_ENCODER_COUNT_POLARITY
  );

  __HAL_GPIO_EXTI_CLEAR_IT(ENCODER_A_PIN);
  __HAL_GPIO_EXTI_CLEAR_IT(ENCODER_B_PIN);
  HAL_NVIC_EnableIRQ(EXTI9_5_IRQn);

  encoder_count = 0;
  encoder_edge_count = 0U;
  encoder_valid_transition_count = 0U;
  encoder_invalid_transition_count = 0U;
  encoder_invalid_latched = 0U;
  encoder_overflow_latched = 0U;
  encoder_prev_ab = (uint8_t)((initial_a << 1U) | initial_b);

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
  lengthAdjustBlocked = 1U;
  encoderLengthCalibrated =
      (ENCODER_COUNTS_PER_MM > 0.0f) ? 1U : 0U;
}

static void ControlPipeline_ForceSafe(void)
{
  HAL_StatusTypeDef safe_status = HAL_ERROR;

  /* This path is safe before adapter initialization and from Error_Handler. */
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOG_CLK_ENABLE();
  __HAL_RCC_GPIOK_CLK_ENABLE();

  if (tb6612_hal.initialized == 1U)
  {
    safe_status = STM32_TB6612_HAL_ForceSafe(&tb6612_hal);
    if (safe_status != HAL_OK)
    {
      motor_hal_error_debug = 1U;
      motor_runtime_fault_latched = 1U;
    }
  }

  if (safe_status != HAL_OK)
  {
    HAL_GPIO_WritePin(MOTOR_STBY_GPIO_PORT, MOTOR_STBY_PIN, GPIO_PIN_RESET);
    if (htim1.Instance == TIM1)
    {
      __HAL_TIM_SET_COMPARE(&htim1, MOTOR_PWM_CHANNEL, 0U);
    }
    HAL_GPIO_WritePin(MOTOR_AIN1_GPIO_PORT, MOTOR_AIN1_PIN, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(MOTOR_AIN2_GPIO_PORT, MOTOR_AIN2_PIN, GPIO_PIN_RESET);
  }

  motor_applied_ccr = 0U;
  motor_applied_ain1 = 0U;
  motor_applied_ain2 = 0U;
  motor_applied_stby = 0U;
  motor_applied_direction = 0;
  motor_output_active_debug = 0U;
  motorEnabledForApp = 0U;
  motor_applied_state = MOTOR_STOP;
}

static void Encoder_ProcessSetZeroRequest(void)
{
  QuadratureEncoderSnapshot snapshot;
  uint8_t strict_valid;
  uint8_t bridge_is_off;

  if (encoder_set_zero_request == 0U)
  {
    return;
  }

  encoder_set_zero_request = 0U;
  encoder_set_zero_status = 0;
  ControlPipeline_ForceSafe();

  memset(&snapshot, 0, sizeof(snapshot));
  strict_valid = SnapshotEncoder(&snapshot);
  bridge_is_off =
      ((motor_output_active_debug == 0U) &&
       (HAL_GPIO_ReadPin(MOTOR_STBY_GPIO_PORT,
                         MOTOR_STBY_PIN) == GPIO_PIN_RESET) &&
       (__HAL_TIM_GET_COMPARE(&htim1, MOTOR_PWM_CHANNEL) == 0U))
      ? 1U : 0U;

  if ((motor_chain_initialized != 1U) ||
      (strict_valid != 1U) ||
      (bridge_is_off != 1U) ||
      (MotorPositionGuard_SetZero(
           &motor_position_guard,
           snapshot.count,
           strict_valid,
           bridge_is_off) != 1U))
  {
    encoder_position_zeroed = 0U;
    calibration_required = 1U;
    encoder_set_zero_status = -1;
    position_fault_debug = motor_position_guard.fault;
    return;
  }

  encoder_zero_count = snapshot.count;
  encoder_position_zeroed = 1U;
  calibration_required = 0U;
  encoder_set_zero_status = 1;
  position_fault_debug = (uint8_t)MOTOR_POSITION_FAULT_NONE;
  motor_output_guard_ready_debug = 1U;
  if ((motor_hal_error_debug == 0U) &&
      (driver_fault_debug == (uint8_t)TB6612_DRIVER_FAULT_NONE) &&
      (mapper_fault_debug == (uint8_t)MOTOR_MAPPER_FAULT_NONE))
  {
    /* A verified neutral SetZero may recover a position-guard latch, but not
     * an encoder, mapper, driver or HAL fault. */
    motor_runtime_fault_latched = 0U;
  }
}

static void Encoder_UpdateLength(void)
{
  QuadratureEncoderSnapshot snapshot;
  int64_t relative_counts;

  memset(&snapshot, 0, sizeof(snapshot));
  if (SnapshotEncoder(&snapshot) != 1U)
  {
    encoder_position_zeroed = 0U;
    calibration_required = 1U;
    ControlPipeline_ForceSafe();
    return;
  }

  relative_counts =
      (int64_t)snapshot.count - (int64_t)encoder_zero_count;
  if ((ENCODER_COUNTS_PER_MM > 0.0f) &&
      (encoder_position_zeroed != 0U))
  {
    currentLengthMm =
        INITIAL_CABLE_LENGTH_MM +
        (ENCODER_LENGTH_SIGN *
         ((float)relative_counts / ENCODER_COUNTS_PER_MM));
    encoderLengthCalibrated = 1U;
  }
  else
  {
    currentLengthMm = INITIAL_CABLE_LENGTH_MM;
    encoderLengthCalibrated = 0U;
  }

  lengthErrorMm = targetLengthMm - currentLengthMm;
  /* App length requests are recorded, but this canonical suppression path does
   * not translate them into an unreviewed motor command. */
  lengthAdjustActive = 0U;
  lengthAdjustBlocked = (lengthAdjustPending != 0U) ? 1U : 0U;
}

/* ========================================================================== */
/* SINGLE AUTHORITATIVE 100 Hz CONTROL PIPELINE                                */
/* ========================================================================== */

static double SelectTremorAxisDps(float gx, float gy, float gz)
{
#if (TREMOR_INPUT_AXIS == TREMOR_AXIS_X)
  (void)gy;
  (void)gz;
  return (double)gx;
#elif (TREMOR_INPUT_AXIS == TREMOR_AXIS_Y)
  (void)gx;
  (void)gz;
  return (double)gy;
#elif (TREMOR_INPUT_AXIS == TREMOR_AXIS_Z)
  (void)gx;
  (void)gy;
  return (double)gz;
#else
#error "TREMOR_INPUT_AXIS must be X, Y, or Z"
#endif
}

static void PublishSuppressionTelemetry(void)
{
  tremorEstimate = suppression_output.tremor_estimate_dps;
  diagnosticFrequencyHz = suppression_output.diagnostic_frequency_hz;
  compensationRequestDps = suppression_output.compensation_request_dps;

  gate_enabled_debug = suppression_output.gate_enabled;
  suppression_fault_debug = suppression_output.current_fault;
  hardened_gate_ready =
      ((suppression_control_ready_debug == 1U) &&
       (suppression_output.current_fault ==
        (uint8_t)SUPPRESSION_CONTROL_FAULT_NONE))
      ? 1U : 0U;
  gate_precondition_ok_debug =
      ((hardened_gate_ready == 1U) &&
       (gate_enabled_debug == 1U))
      ? 1U : 0U;

  actuation_permitted_debug = suppression_output.actuation_permitted;
}

static void PublishSafeDriverTelemetry(const Tb6612Output *output)
{
  if (output != NULL)
  {
    driver_fault_debug = output->fault;
  }
  motor_applied_ccr = 0U;
  motor_applied_ain1 = 0U;
  motor_applied_ain2 = 0U;
  motor_applied_stby = 0U;
  motor_applied_direction = 0;
  motor_applied_state = MOTOR_STOP;
  motor_output_active_debug = 0U;
  motorEnabledForApp = 0U;
}

static uint8_t ControlPipeline_Init(void)
{
  Stm32Tb6612HalConfig hal_config;
  Tb6612Output initial_output;
  uint8_t suppression_ok;

  memset(&suppression_control, 0, sizeof(suppression_control));
  memset(&suppression_output, 0, sizeof(suppression_output));
  memset(&motor_mapper, 0, sizeof(motor_mapper));
  memset(&motor_command_output, 0, sizeof(motor_command_output));
  memset(&motor_position_guard, 0, sizeof(motor_position_guard));
  memset(&position_guard_output, 0, sizeof(position_guard_output));
  memset(&tb6612_driver, 0, sizeof(tb6612_driver));
  memset(&tb6612_output, 0, sizeof(tb6612_output));
  memset(&tb6612_hal, 0, sizeof(tb6612_hal));
  memset(&hal_config, 0, sizeof(hal_config));
  memset(&initial_output, 0, sizeof(initial_output));

  motor_runtime_armed = 0U;
  motor_runtime_fault_latched = 0U;
  motor_hal_error_debug = 0U;
  motor_chain_initialized = 0U;
  motor_output_guard_ready_debug = 0U;
  calibration_required = 1U;
  ControlPipeline_ForceSafe();

  /* NULL selects the reviewed hardened gate default inside SuppressionControl.
   * Estimator diagnostic frequency is never consumed by a gate or App field. */
  suppression_ok = SuppressionControl_Init(
      &suppression_control,
      SUPPRESSION_ESTIMATOR_EHWFLC_KF,
      NULL
  );
  suppression_control_ready_debug = suppression_ok;

  hal_config.pwm_timer = &htim1;
  hal_config.pwm_channel = MOTOR_PWM_CHANNEL;
  hal_config.pwm_full_scale_ccr = MOTOR_PWM_FULL_SCALE_CCR;
  hal_config.ain1_port = MOTOR_AIN1_GPIO_PORT;
  hal_config.ain1_pin = MOTOR_AIN1_PIN;
  hal_config.ain2_port = MOTOR_AIN2_GPIO_PORT;
  hal_config.ain2_pin = MOTOR_AIN2_PIN;
  hal_config.stby_port = MOTOR_STBY_GPIO_PORT;
  hal_config.stby_pin = MOTOR_STBY_PIN;

  motor_pwm_start_status = STM32_TB6612_HAL_Init(&tb6612_hal, &hal_config);
  if (motor_pwm_start_status != HAL_OK)
  {
    motor_hal_error_debug = 1U;
    motor_runtime_fault_latched = 1U;
    ControlPipeline_ForceSafe();
    return suppression_ok;
  }

  Encoder_Init();

#if (MOTOR_BENCH_CONFIG_APPROVED == 1U)
  if ((MotorCommandMapper_Init(
           &motor_mapper,
           &motor_mapper_config,
           &approved_motor_mapper_config) != 1U) ||
      (TB6612Driver_Init(
           &tb6612_driver,
           &tb6612_driver_config,
           &initial_output) == TB6612_DRIVER_ERROR) ||
      (STM32_TB6612_HAL_Apply(
           &tb6612_hal,
           &initial_output) != HAL_OK) ||
      (MotorPositionGuard_Init(
           &motor_position_guard,
           &motor_position_config) != 1U) ||
      (encoder_valid != 1U))
  {
    mapper_fault_debug = motor_mapper.current_fault;
    driver_fault_debug = initial_output.fault;
    position_fault_debug = motor_position_guard.fault;
    motor_runtime_fault_latched = 1U;
    ControlPipeline_ForceSafe();
    return suppression_ok;
  }

  motor_chain_initialized = 1U;
#else
  /* Expected canonical state until reviewed bench constants replace zeros. */
  motor_chain_initialized = 0U;
#endif

  ControlPipeline_ForceSafe();
  return suppression_ok;
}

static void ControlPipeline_ApplySafeTick(void)
{
  QuadratureEncoderSnapshot snapshot;
  Tb6612Output safe_output;
  Tb6612DriverResult safe_result;
  uint8_t encoder_ok;

  suppression_start_allowed = 0U;
  memset(&motor_command_output, 0, sizeof(motor_command_output));
  memset(&position_guard_output, 0, sizeof(position_guard_output));
  memset(&safe_output, 0, sizeof(safe_output));
  memset(&snapshot, 0, sizeof(snapshot));

  if (motor_chain_initialized != 1U)
  {
    ControlPipeline_ForceSafe();
    return;
  }

  (void)MotorCommandMapper_Update(
      &motor_mapper, 0.0, 0U, 0U, 0U, &motor_command_output);
  mapper_fault_debug = motor_command_output.current_fault;

  safe_result = TB6612Driver_Update(
      &tb6612_driver, 0, 0.0, 0U, &safe_output);
  driver_fault_debug = safe_output.fault;
  if (safe_result == TB6612_DRIVER_ERROR)
  {
    motor_runtime_fault_latched = 1U;
    ControlPipeline_ForceSafe();
    return;
  }

  encoder_ok = SnapshotEncoder(&snapshot);
  if ((motor_position_guard.zeroed == 1U) && (encoder_ok == 1U))
  {
    (void)MotorPositionGuard_Update(
        &motor_position_guard,
        snapshot.count,
        encoder_ok,
        MOTOR_POSITION_DIRECTION_STOP,
        0U,
        &position_guard_output
    );
    position_fault_debug = position_guard_output.fault;
  }

  if (STM32_TB6612_HAL_Apply(&tb6612_hal, &safe_output) != HAL_OK)
  {
    motor_hal_error_debug = 1U;
    motor_runtime_fault_latched = 1U;
    ControlPipeline_ForceSafe();
    return;
  }

  PublishSafeDriverTelemetry(&safe_output);
  motor_output_guard_ready_debug =
      ((motor_position_guard.zeroed == 1U) &&
       (motor_position_guard.fault_latched == 0U) &&
       (encoder_ok == 1U))
      ? 1U : 0U;
}

static void ControlPipeline_100HzFreshSample(double raw_gyro_dps)
{
  QuadratureEncoderSnapshot snapshot;
  Tb6612Output candidate;
  Tb6612Output safe_output;
  Tb6612DriverResult driver_result;
  Tb6612DriverResult safe_result;
  uint32_t cycle_start;
  uint32_t irq_primask;
  HAL_StatusTypeDef apply_status;
  double intensity_scale;
  double limited_request;
  uint8_t suppression_permission;
  uint8_t final_permission;
  uint8_t mapper_active;
  uint8_t encoder_ok;
  uint8_t candidate_active;
  uint8_t position_allowed;
  uint8_t prior_driver_fault;
  uint8_t final_recheck_ok;

  memset(&candidate, 0, sizeof(candidate));
  memset(&safe_output, 0, sizeof(safe_output));
  memset(&snapshot, 0, sizeof(snapshot));
  memset(&position_guard_output, 0, sizeof(position_guard_output));

  prior_driver_fault =
      ((motor_runtime_fault_latched != 0U) ||
       (motor_hal_error_debug != 0U) ||
       (driver_fault_debug != (uint8_t)TB6612_DRIVER_FAULT_NONE) ||
       (motor_position_guard.fault_latched != 0U))
      ? 1U : 0U;

  cycle_start = DWT->CYCCNT;
  suppression_permission = SuppressionControl_Update(
      &suppression_control,
      raw_gyro_dps,
      1U,
      0U,
      prior_driver_fault,
      0U,
      &suppression_output
  );
  algo_cycles = DWT->CYCCNT - cycle_start;
  algo_time_us =
      (float)algo_cycles / ((float)SystemCoreClock / 1000000.0f);
  algo_call_count++;
  PublishSuppressionTelemetry();

  if (suppression_control_ready_debug != 1U)
  {
    ControlPipeline_ForceSafe();
    return;
  }

  final_permission =
      ((suppression_permission == 1U) &&
       (suppression_output.actuation_permitted == 1U) &&
       (motor_bench_config_approved == 1U) &&
       (motor_chain_initialized == 1U) &&
       (motor_runtime_armed == 1U) &&
       (motor_runtime_fault_latched == 0U) &&
       (calibration_required == 0U) &&
       (motor_position_guard.zeroed == 1U) &&
       (motor_position_guard.fault_latched == 0U))
      ? 1U : 0U;
  suppression_start_allowed = final_permission;

  if (motor_chain_initialized != 1U)
  {
    ControlPipeline_ForceSafe();
    return;
  }

  intensity_scale =
      ((motorIntensityPercent <= 100U) ?
       (double)motorIntensityPercent : 0.0) / 100.0;
  limited_request =
      suppression_output.compensation_request_dps * intensity_scale;

  mapper_active = MotorCommandMapper_Update(
      &motor_mapper,
      limited_request,
      final_permission,
      prior_driver_fault,
      0U,
      &motor_command_output
  );
  mapper_fault_debug = motor_command_output.current_fault;

  driver_result = TB6612Driver_Update(
      &tb6612_driver,
      (mapper_active == 1U) ? motor_command_output.direction : 0,
      (mapper_active == 1U) ? motor_command_output.duty_fraction : 0.0,
      (mapper_active == 1U) ? motor_command_output.bridge_enable : 0U,
      &candidate
  );
  driver_fault_debug = candidate.fault;
  if (driver_result == TB6612_DRIVER_ERROR)
  {
    motor_runtime_fault_latched = 1U;
    ControlPipeline_ForceSafe();
    return;
  }

  encoder_ok = SnapshotEncoder(&snapshot);
  if (encoder_ok != 1U)
  {
    if (motor_position_guard.zeroed == 1U)
    {
      (void)MotorPositionGuard_Update(
          &motor_position_guard,
          snapshot.count,
          0U,
          MOTOR_POSITION_DIRECTION_STOP,
          0U,
          &position_guard_output
      );
      position_fault_debug = position_guard_output.fault;
    }
    calibration_required = 1U;
    motor_runtime_fault_latched = 1U;
    ControlPipeline_ForceSafe();
    return;
  }

  candidate_active =
      ((driver_result == TB6612_DRIVER_ACTIVE) &&
       (candidate.stby == 1U) &&
       (candidate.ccr > 0U))
      ? 1U : 0U;

  if (motor_position_guard.zeroed != 1U)
  {
    position_allowed = 0U;
  }
  else
  {
    position_allowed = MotorPositionGuard_Update(
        &motor_position_guard,
        snapshot.count,
        encoder_ok,
        (candidate_active == 1U) ?
            candidate.direction : MOTOR_POSITION_DIRECTION_STOP,
        candidate_active,
        &position_guard_output
    );
    position_fault_debug = position_guard_output.fault;
    calibration_required =
        (position_guard_output.zeroed == 1U) ? 0U : 1U;
  }

  if (((candidate_active == 1U) && (position_allowed != 1U)) ||
      ((candidate_active == 0U) && (position_allowed != 0U)))
  {
    safe_result = TB6612Driver_Update(
        &tb6612_driver, 0, 0.0, 0U, &safe_output);
    if ((safe_result == TB6612_DRIVER_ERROR) ||
        (STM32_TB6612_HAL_Apply(&tb6612_hal, &safe_output) != HAL_OK))
    {
      motor_hal_error_debug = 1U;
      motor_runtime_fault_latched = 1U;
    }
    PublishSafeDriverTelemetry(&safe_output);
    return;
  }

  if ((candidate_active == 1U) && (position_allowed == 1U))
  {
    /* Encoder EXTI can hard-stop asynchronously.  Prevent main from applying
     * a stale ACTIVE candidate after that ISR: recheck all latches and commit
     * GPIO/CCR plus applied-output telemetry in one short critical section. */
    irq_primask = __get_PRIMASK();
    __disable_irq();
    final_recheck_ok =
        ((fresh_sample_available == 1U) &&
         (scheduler_overrun_this_tick == 0U) &&
         (tick_flag == 0U) &&
         (software_tick_count == control_tick_count) &&
         (motor_runtime_fault_latched == 0U) &&
         (motor_runtime_armed == 1U) &&
         (motor_bench_config_approved == 1U) &&
         (quadrature_encoder.initialized == 1U) &&
         (quadrature_encoder.invalid_transition_latched == 0U) &&
         (quadrature_encoder.overflow_latched == 0U) &&
         (motor_position_guard.zeroed == 1U) &&
         (motor_position_guard.fault_latched == 0U))
        ? 1U : 0U;

    if (final_recheck_ok == 1U)
    {
      apply_status = STM32_TB6612_HAL_Apply(&tb6612_hal, &candidate);
      if (apply_status == HAL_OK)
      {
        motor_applied_ccr = candidate.ccr;
        motor_applied_ain1 = candidate.ain1;
        motor_applied_ain2 = candidate.ain2;
        motor_applied_stby = candidate.stby;
        motor_applied_direction = candidate.direction;
        motor_applied_state =
            (candidate.direction == MOTOR_POSITION_DIRECTION_RELEASE) ?
            MOTOR_FORWARD : MOTOR_REVERSE;
        motor_output_active_debug = 1U;
        motorEnabledForApp = 1U;
      }
    }
    else
    {
      apply_status = HAL_ERROR;
    }
    __set_PRIMASK(irq_primask);

    if (apply_status != HAL_OK)
    {
      (void)TB6612Driver_Update(
          &tb6612_driver, 0, 0.0, 0U, &safe_output);
      if (final_recheck_ok == 1U)
      {
        motor_hal_error_debug = 1U;
        motor_runtime_fault_latched = 1U;
      }
      ControlPipeline_ForceSafe();
      return;
    }
  }
  else
  {
    if (STM32_TB6612_HAL_Apply(&tb6612_hal, &candidate) != HAL_OK)
    {
      motor_hal_error_debug = 1U;
      motor_runtime_fault_latched = 1U;
      ControlPipeline_ForceSafe();
      return;
    }
    PublishSafeDriverTelemetry(&candidate);
  }

  motor_output_guard_ready_debug =
      ((motor_position_guard.zeroed == 1U) &&
       (motor_position_guard.fault_latched == 0U))
      ? 1U : 0U;
}

static void ControlPipeline_RejectStaleSample(void)
{
  uint8_t prior_driver_fault;

  stale_sample_reject_count++;
  fresh_sample_available = 0U;
  prior_driver_fault =
      ((motor_runtime_fault_latched != 0U) ||
       (motor_hal_error_debug != 0U) ||
       (driver_fault_debug != (uint8_t)TB6612_DRIVER_FAULT_NONE) ||
       (motor_position_guard.fault_latched != 0U))
      ? 1U : 0U;

  if (suppression_control_ready_debug == 1U)
  {
    (void)SuppressionControl_Update(
        &suppression_control,
        0.0,
        0U,
        1U,
        prior_driver_fault,
        SUPPRESSION_CONTROL_INHIBIT_SYSTEM,
        &suppression_output
    );
    PublishSuppressionTelemetry();
  }
  ControlPipeline_ApplySafeTick();
}

/* ========================================================================== */
/* IMU                                                                         */
/* ========================================================================== */

HAL_StatusTypeDef Read_IMU_RealData(
    float *gx,
    float *gy,
    float *gz
)
{
  HAL_StatusTypeDef status;

  if ((gx == NULL) || (gy == NULL) || (gz == NULL))
  {
    gyroXRaw = 0;
    gyroYRaw = 0;
    gyroZRaw = 0;
    return HAL_ERROR;
  }

  status =
      ReadData(
          &BNO055_Data,
          SENSOR_GYRO
      );

  if ((status == HAL_OK) &&
      ((!isfinite(BNO055_Data.Gyro.X)) ||
       (!isfinite(BNO055_Data.Gyro.Y)) ||
       (!isfinite(BNO055_Data.Gyro.Z)) ||
       (fabsf(BNO055_Data.Gyro.X) > GYRO_RAW_MAX_ABS_DPS) ||
       (fabsf(BNO055_Data.Gyro.Y) > GYRO_RAW_MAX_ABS_DPS) ||
       (fabsf(BNO055_Data.Gyro.Z) > GYRO_RAW_MAX_ABS_DPS)))
  {
    status = HAL_ERROR;
  }

  if (status == HAL_OK)
  {
    *gx = BNO055_Data.Gyro.X;
    *gy = BNO055_Data.Gyro.Y;
    *gz = BNO055_Data.Gyro.Z;

    gyroXRaw =
        (int16_t)(
            BNO055_Data.Gyro.X *
            GYRO_RAW_LSB_PER_DPS
        );

    gyroYRaw =
        (int16_t)(
            BNO055_Data.Gyro.Y *
            GYRO_RAW_LSB_PER_DPS
        );

    gyroZRaw =
        (int16_t)(
            BNO055_Data.Gyro.Z *
            GYRO_RAW_LSB_PER_DPS
        );
  }
  else
  {
    *gx = 0.0f;
    *gy = 0.0f;
    *gz = 0.0f;
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
  uint32_t tick_primask;
  uint32_t pending_ticks;
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

  DWT_Init();

  /* Initializes SuppressionControl and the safe HAL adapter.  The canonical
   * build remains motor-off because MOTOR_BENCH_CONFIG_APPROVED is zero. */
  (void)ControlPipeline_Init();

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
      }
      else
      {
        imu_ready = 0U;
      }
    }
    else
    {
      bno_init_status = HAL_ERROR;

      imu_ready = 0U;
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
    Encoder_ProcessSetZeroRequest();

    if (tick_flag != 0U)
    {
      /* Consume the Boolean timer flag and its monotonic count atomically.
       * A pending count other than exactly one means at least one 100 Hz
       * deadline was lost; that tick is inhibited instead of using old data. */
      tick_primask = __get_PRIMASK();
      __disable_irq();
      pending_ticks = software_tick_count - control_tick_count;
      scheduler_pending_tick_count = pending_ticks;
      control_tick_count = software_tick_count;
      tick_flag = 0U;
      __set_PRIMASK(tick_primask);

      scheduler_overrun_this_tick =
          (pending_ticks == 1U) ? 0U : 1U;
      fresh_sample_available = 0U;

      if (scheduler_overrun_this_tick != 0U)
      {
        if (scheduler_overrun_count < UINT32_MAX)
        {
          scheduler_overrun_count++;
        }
        ControlPipeline_RejectStaleSample();
      }
      else
      {
        if (imu_ready != 0U)
        {
          bno_read_status =
              Read_IMU_RealData(&gyroX, &gyroY, &gyroZ);

          if (bno_read_status == HAL_OK)
          {
            imu_read_ok_count++;
            imu_consecutive_error_count = 0U;

            /* A successful hardware read is the only producer of a new control
             * sample identity.  Test/fallback data never reaches this path. */
            imu_sample_generation++;
            selectedGyroInputDps =
                SelectTremorAxisDps(gyroX, gyroY, gyroZ);
            fresh_sample_available =
                (imu_sample_generation !=
                 last_controlled_sample_generation)
                ? 1U : 0U;
          }
          else
          {
            imu_read_error_count++;
            imu_consecutive_error_count++;

            if (imu_consecutive_error_count >= 5U)
            {
              imu_ready = 0U;
            }
          }
        }

        if (fresh_sample_available != 0U)
        {
          ControlPipeline_100HzFreshSample(selectedGyroInputDps);
          last_controlled_sample_generation = imu_sample_generation;
        }
        else
        {
          /* A failed/missing read must reset the gate/estimator and force the
           * bridge safe; the previous gyro sample is never processed again. */
          ControlPipeline_RejectStaleSample();
        }
      }

      Encoder_UpdateLength();
      Tremor_TransmitCurrentSample(fresh_sample_available);
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
  uint8_t level_a;
  uint8_t level_b;

  if ((GPIO_Pin != ENCODER_A_PIN) &&
      (GPIO_Pin != ENCODER_B_PIN))
  {
    return;
  }

  encoder_edge_count++;
  level_a = ReadDigitalLevel(ENCODER_A_GPIO_PORT, ENCODER_A_PIN);
  level_b = ReadDigitalLevel(ENCODER_B_GPIO_PORT, ENCODER_B_PIN);
  (void)QuadratureEncoder_OnEdge(
      &quadrature_encoder,
      level_a,
      level_b
  );
  encoder_prev_ab = (uint8_t)((level_a << 1U) | level_b);

  if ((quadrature_encoder.initialized != 1U) ||
      (quadrature_encoder.invalid_transition_latched != 0U) ||
      (quadrature_encoder.overflow_latched != 0U))
  {
    encoder_valid = 0U;
    calibration_required = 1U;
    motor_runtime_fault_latched = 1U;
    ControlPipeline_ForceSafe();
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
  /*
   * 0823 fail-safe: any fatal main-level error must remove bridge/PWM output
   * before the CPU enters the permanent error loop.
   */
  ControlPipeline_ForceSafe();
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
