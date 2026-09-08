/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Tremor gate + distance-based encoder cable control + App length motion
  *
  * The current profile is intentionally ready for off-body powered testing:
  * a valid 4-6 Hz gate and estimator command can reach TIM1/TB6612 without a
  * debugger arm or encoder SetZero.  See motor_bench_config.h for every bench
  * adjustment.  Sensor freshness, scheduler, driver and HAL faults still stop
  * the bridge in the same 100 Hz sample.
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
#include "motor_bench_config.h"
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

/* Tremor-triggered cable position controller.
 * Gate only triggers the motion; tremorEstimate sign no longer reverses motor. */
typedef enum
{
  TREMOR_POSITION_IDLE = 0,
  TREMOR_POSITION_PULLING,
  TREMOR_POSITION_HOLDING,
  TREMOR_POSITION_RETURNING,
  TREMOR_POSITION_APP_ADJUSTING,
  TREMOR_POSITION_FAULT
} TremorPositionState;

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
   * Command-active status sent to ESP32 / App (wire name kept for
   * compatibility):
   *   0 = no ACTIVE motor command was applied
   *   1 = the full safety chain accepted and HAL applied a nonzero command
   * This does not prove that the physical motor moved.
   *
   * App-side normal-use rule:
   *   0 -> length controls may be adjusted
   *   1 -> command is active; temporarily disable length controls
   */
  uint8_t motor_enabled;
} TremorSample_t;

typedef struct
{
  uint16_t battery_mv;
  uint8_t battery_percent;
  uint8_t battery_flags;
} BatteryStatus_t;
#pragma pack(pop)

typedef char TremorSample_t_must_be_16_bytes[
  (sizeof(TremorSample_t) == 16U) ? 1 : -1
];

typedef char BatteryStatus_t_must_be_4_bytes[
  (sizeof(BatteryStatus_t) == 4U) ? 1 : -1
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

/* 100 Hz */
#define CONTROL_SAMPLE_RATE_HZ          100.0

/* BNO055 dps telemetry is encoded as signed int16 at 16 LSB/(deg/s).
 * Reject non-finite/out-of-range data before either control or conversion. */
#define GYRO_RAW_LSB_PER_DPS            16.0f
#define GYRO_RAW_MAX_ABS_DPS            2047.0f

/* USART1 <-> ESP32 communication */
#define TREMOR_UART_TIMEOUT_MS          5U

/*
 * STM32 -> ESP32 framed UART protocol:
 *
 *   Byte0 = 0xAA
 *   Byte1 = 0x55
 *   Byte2 = TYPE
 *   Byte3 = PAYLOAD LENGTH
 *   Byte4.. = PAYLOAD
 *
 * TYPE 0x01 = TremorSample_t, 16-byte payload
 *               complete frame = AA 55 01 10 + 16 payload bytes
 * TYPE 0x02 = BatteryStatus_t, 4-byte payload
 *               complete frame = AA 55 02 04 + 4 payload bytes
 *
 * These type/length pairs match the ESP32 parser exactly.
 */
#define COMM_HEADER_1                   0xAAU
#define COMM_HEADER_2                   0x55U
#define COMM_TYPE_TREMOR                0x01U
#define COMM_TYPE_BATTERY               0x02U
#define COMM_HEADER_SIZE                4U
#define COMM_MAX_PAYLOAD_SIZE           16U

/*
 * Battery monitor / telemetry:
 *   PC0 -> ADC1_IN10
 *   0~25 V five-times divider module
 *   ADC update once per second
 *   Battery UART status once every 1 second (matches ESP32 expectation)
 */
#define BATTERY_UPDATE_INTERVAL_MS      1000U
#define BATTERY_SEND_INTERVAL_MS        1000U
#define BATTERY_ADC_SAMPLES             8U
#define ADC_REFERENCE_VOLTAGE           3.300f
#define ADC_MAX_VALUE_12BIT             4095.0f
#define VOLTAGE_DIVIDER_RATIO           5.000f
#define VOLTAGE_CALIBRATION             1.00000f

#define BATTERY_LOW_PERCENT             20U
#define BATTERY_CRITICAL_PERCENT        10U
#define BATTERY_FLAG_LOW                0x01U
#define BATTERY_FLAG_CRITICAL           0x02U
#define BATTERY_FLAG_ADC_ERROR          0x04U

/*
 * ESP32 -> STM32 control packet (3 bytes):
 *
 * Byte0 = command
 * Byte1 = magnitude high byte
 * Byte2 = magnitude low byte
 * magnitude = unsigned big-endian UInt16 in mm, 0..50 (0..5 cm).
 *
 * 0x02: Slider NEGATIVE relative adjustment
 *       Example: [0x02][0x00][0x06] = -6 mm
 *                [0x02][0x00][0x32] = -50 mm
 *
 * 0x03: Slider POSITIVE relative adjustment
 *       Example: [0x03][0x00][0x06] = +6 mm
 *                [0x03][0x00][0x32] = +50 mm
 *
 * 0x04: Manual NEGATIVE relative adjustment
 *       Example: [0x04][0x00][0x06] = -6 mm
 *
 * 0x05: Manual POSITIVE relative adjustment
 *       Example: [0x05][0x00][0x06] = +6 mm
 *
 * The magnitude bytes are always positive. Direction is selected by command.
 */
#define CONTROL_PACKET_SIZE                 3U
#define CMD_ADJUST_LENGTH_NEGATIVE_MM       0x02U
#define CMD_ADJUST_LENGTH_POSITIVE_MM       0x03U
#define CMD_MANUAL_LENGTH_NEGATIVE_MM       0x04U
#define CMD_MANUAL_LENGTH_POSITIVE_MM       0x05U
#define CONTROL_MAX_MAGNITUDE_MM            50U

/* Cable / spool calibration supplied from the final mechanism test.
 *
 * Measured: 70 mm of cable per output-shaft revolution
 *           720 encoder counts per output-shaft revolution
 * Therefore: 720 / 70 = 10.285714 counts/mm.
 *
 * Physical home (power-on) free cable length = 400 mm.
 * Tremor target removes 200 mm of free cable, so target free length = 200 mm.
 *
 * IMPORTANT: before reset/power-on, mechanically place the cable at the known
 * 400 mm starting length.  After boot the encoder counter is allowed to keep
 * accumulating; every motion uses a relative start count and travelled counts. */
#define LENGTH_MIN_MM                       0.0f
#define LENGTH_MAX_MM                       900.0f
#define INITIAL_CABLE_LENGTH_MM             400.0f
#define TREMOR_PULL_LENGTH_MM               200.0f
#define TREMOR_TARGET_CABLE_LENGTH_MM       \
    (INITIAL_CABLE_LENGTH_MM - TREMOR_PULL_LENGTH_MM)

#define SPOOL_CABLE_PER_REV_MM              70.0f
#define ENCODER_COUNTS_PER_OUTPUT_REV       720.0f
#define ENCODER_COUNTS_PER_MM               \
    (ENCODER_COUNTS_PER_OUTPUT_REV / SPOOL_CABLE_PER_REV_MM)

/* 200 mm * 720 / 70 = 2057.14 counts -> 2057 counts. */
#define TREMOR_PULL_COUNTS                  2057L

/* Encoder count polarity is deliberately NOT used to decide distance.
 * Motion completion uses ABS(current_count - move_start_count), so the encoder
 * counter may accumulate positive or negative values.  Motor direction still
 * comes from the TAKE_UP / RELEASE semantic driver commands below. */

/* The reviewed TB6612 driver already defines semantic TAKE_UP / RELEASE
 * directions.  These two macros isolate the physical motor convention. */
#define POSITION_TAKE_UP_MOTOR_DIRECTION    MOTOR_POSITION_DIRECTION_TAKE_UP
#define POSITION_RETURN_MOTOR_DIRECTION     MOTOR_POSITION_DIRECTION_RELEASE

/* Position-controller tuning at 100 Hz.
 *
 * There is intentionally NO target tolerance, NO total motion timeout and NO
 * maximum encoder-excursion fault.  Each motion stores its own start count and
 * stops when the absolute encoder travel reaches the requested count distance.
 * Therefore encoder_count may keep accumulating across cycles and does not need
 * to return to zero. */
#define POSITION_MEDIUM_ZONE_COUNTS         600L  /* ~= 58.3 mm */
#define POSITION_SLOW_ZONE_COUNTS           200L  /* ~= 19.4 mm */

#define POSITION_FAST_DUTY                  0.60
#define POSITION_MEDIUM_DUTY                0.45
#define POSITION_SLOW_DUTY                  0.30

/* Cable length is updated from commanded motion direction plus absolute
 * encoder travel, so no signed ENCODER_LENGTH_SIGN calibration is required. */

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
#define TREMOR_INPUT_AXIS               MOTOR_TREMOR_INPUT_AXIS

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

ADC_HandleTypeDef hadc1;

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
 * Debug / outgoing command-active status byte (wire name kept for
 * compatibility):
 *   0 = no ACTIVE motor command was applied
 *   1 = the full safety chain accepted and HAL applied a nonzero command
 * This does not prove that the physical motor moved.
 *
 * During normal operation the App may use:
 *   0 -> enable length controls
 *   1 -> disable length controls while a command is active
 */
volatile uint8_t motorEnabledForApp = 0U;

static uint32_t tremorSequence = 0U;
static TremorSample_t lastTremorSample = {0};

/* -------------------------------------------------------------------------- */
/* Battery status -> ESP32 / App                                               */
/* -------------------------------------------------------------------------- */
volatile uint16_t batteryVoltageMv = 0U;
volatile uint8_t batteryPercent = 0U;
volatile uint8_t batteryFlags = BATTERY_FLAG_ADC_ERROR;
volatile uint32_t batteryAdcErrorCount = 0U;
volatile uint32_t batteryUartErrorCount = 0U;

/* UART framing diagnostics for STM32 -> ESP32. */
volatile uint32_t commTxFrameCount = 0U;
volatile uint32_t commTxErrorCount = 0U;
volatile uint32_t commTremorTxCount = 0U;
volatile uint32_t commBatteryTxCount = 0U;
volatile uint8_t lastCommTxType = 0U;
volatile uint8_t lastCommTxLength = 0U;
volatile HAL_StatusTypeDef lastCommTxStatus = HAL_OK;

static uint32_t nextBatteryTickMs = 0U;
static uint32_t nextBatterySendTickMs = 0U;
static float filteredBatteryVoltage = 0.0f;
static uint8_t batteryFilterInitialized = 0U;

/* -------------------------------------------------------------------------- */
/* REAL APP / ESP32 UART RX                                                    */
/* -------------------------------------------------------------------------- */
static uint8_t controlRxBuffer[CONTROL_PACKET_SIZE] = {0U, 0U, 0U};

volatile uint32_t controlRxCount = 0U;
volatile uint32_t controlInvalidCount = 0U;
volatile uint32_t controlUartErrorCount = 0U;

volatile uint8_t lastControlCommand = 0U;
volatile uint16_t lastControlRawValue = 0U;
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
/* Cable length represented by the current IDLE/home position. */
volatile float baseCableLengthMm = INITIAL_CABLE_LENGTH_MM;

volatile uint8_t lengthAdjustPending = 0U;
volatile uint8_t lengthAdjustActive = 0U;
volatile uint8_t lengthAdjustBlocked = 0U;
volatile uint8_t encoderLengthCalibrated = 0U;

volatile int16_t lastLengthDeltaMm = 0;

/* App target is kept separate from the tremor target so a received App command
 * is not overwritten by the 100 Hz tremor state machine. */
volatile float appRequestedLengthMm = INITIAL_CABLE_LENGTH_MM;
volatile uint8_t appAdjustmentResumeHolding = 0U;

/* Generic encoder-distance motion diagnostics.  All position moves use
 * abs(encoder_count - positionMoveStartCount) as the travelled distance. */
volatile int32_t positionMoveStartCount = 0;
volatile int32_t positionMoveRequestedCounts = 0;
volatile int32_t positionMoveTravelCounts = 0;
volatile float positionMoveStartLengthMm = INITIAL_CABLE_LENGTH_MM;
volatile int8_t positionMoveLengthDirection = 0; /* -1 take-up, +1 release */

volatile uint32_t lengthAdjustRequestCount = 0U;
volatile uint32_t lengthAdjustCompleteCount = 0U;
volatile uint32_t lengthAdjustRejectedCount = 0U;

/* -------------------------------------------------------------------------- */
/* Tremor-triggered encoder position controller                                */
/* -------------------------------------------------------------------------- */
volatile TremorPositionState tremorPositionState = TREMOR_POSITION_IDLE;
volatile int32_t tremorHomeCount = 0;
volatile int32_t tremorTargetCount = 0;
volatile int32_t tremorPositionErrorCounts = 0;
volatile uint8_t tremorPositionFaultLatched = 0U;
volatile uint32_t tremorPullTriggerCount = 0U;
volatile uint32_t tremorReturnCompleteCount = 0U;
/* MotionStartMs is diagnostic only; it no longer imposes a total duration limit. */
/* Actual take-up distance reached in the current/last cycle.
 * The return controller still targets the absolute home count; this value is
 * exposed for Debug so you can verify how many encoder counts were wound. */
volatile int32_t tremorActualPulledCounts = 0;

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

/* Both mapper records must remain bit-identical.  All tunable powered-bench
 * values live in motor_bench_config.h so the firmware team has one entry. */
static const MotorCommandMapperConfig motor_mapper_config = {
  MOTOR_COMMAND_DEADBAND_DPS,
  MOTOR_COMMAND_GAIN_DUTY_FRACTION_PER_DPS,
  MOTOR_COMMAND_MAX_DUTY_FRACTION,
  MOTOR_COMMAND_MAX_DUTY_STEP_PER_TICK,
  MOTOR_COMMAND_MAX_ABS_REQUEST_DPS,
  MOTOR_MAPPER_REVERSAL_DEAD_TICKS,
  MOTOR_COMMAND_DIRECTION_POLARITY
};
static const MotorCommandMapperConfig approved_motor_mapper_config = {
  MOTOR_COMMAND_DEADBAND_DPS,
  MOTOR_COMMAND_GAIN_DUTY_FRACTION_PER_DPS,
  MOTOR_COMMAND_MAX_DUTY_FRACTION,
  MOTOR_COMMAND_MAX_DUTY_STEP_PER_TICK,
  MOTOR_COMMAND_MAX_ABS_REQUEST_DPS,
  MOTOR_MAPPER_REVERSAL_DEAD_TICKS,
  MOTOR_COMMAND_DIRECTION_POLARITY
};
/* The position path is compiled for the later guarded profile, but is not an
 * authority input while MOTOR_POWERED_BENCH_MODE is one. */
static const MotorPositionGuardConfig motor_position_config = {
  1000000U, 1000000U, 1000000U, 1U, 1000000U, 1000000U, 1000000U
};
static const Tb6612DriverConfig tb6612_driver_config = {
  MOTOR_PWM_FULL_SCALE_CCR,
  MOTOR_COMMAND_MAX_DUTY_FRACTION,
  MOTOR_DRIVER_REVERSAL_DEAD_TICKS,
  MOTOR_RELEASE_AIN1_LEVEL
};

double selectedGyroInputDps = 0.0;
double tremorEstimate = 0.0;
double diagnosticFrequencyHz = 0.0; /* local-only; never a gate/biomarker */
double compensationRequestDps = 0.0;

volatile uint8_t suppression_control_ready_debug = 0U;
volatile uint8_t motor_chain_initialized = 0U;
volatile uint8_t motor_runtime_armed = MOTOR_DEFAULT_RUNTIME_ARMED;
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
uint16_t bno_i2c_address = (0x28U << 1);

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
static void MX_ADC1_Init(void);
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

static HAL_StatusTypeDef Comm_SendPacket(
    uint8_t type,
    const void *payload,
    uint8_t length
);
static void Tremor_TransmitCurrentSample(uint8_t sensorValid);

static uint8_t Battery_VoltageToPercent(float packVoltage);
static uint8_t Battery_MakeFlags(uint8_t percent, uint8_t adcOk);
static uint8_t Battery_ReadVoltage(float *packVoltage);
static void Battery_Update(void);
static void Battery_SendStatus(void);

static void Control_StartReceive(void);
static int16_t Control_DecodeValue(uint8_t command, uint16_t rawValue);
static uint8_t Control_ApplyCommand(uint8_t command, int16_t value);

static void Encoder_Init(void);
static void Encoder_UpdateLength(void);
static void TremorPositionController_Init(void);
static uint8_t TremorPositionController_Update(
    uint8_t gateActive,
    int8_t *motorDirection,
    double *dutyFraction
);
static double TremorPosition_SelectDuty(int32_t absErrorCounts);
static void TremorPosition_EnterFault(void);
static int32_t Encoder_AbsDeltaCounts(int32_t a, int32_t b);
static int32_t Encoder_MmToCounts(float mm);
static uint8_t App_StartPendingAdjustment(
    int32_t currentCount,
    uint8_t resumeHolding
);

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* ========================================================================== */
/* STM32 -> ESP32 framed UART transport                                        */
/* ========================================================================== */

static HAL_StatusTypeDef Comm_SendPacket(
    uint8_t type,
    const void *payload,
    uint8_t length
)
{
  uint8_t frame[COMM_HEADER_SIZE + COMM_MAX_PAYLOAD_SIZE];
  HAL_StatusTypeDef status;

  /*
   * ESP32 parser accepts ONLY:
   *   AA 55 01 10 + 16-byte TremorSample_t
   *   AA 55 02 04 +  4-byte BatteryStatus_t
   */
  if (payload == NULL)
  {
    commTxErrorCount++;
    lastCommTxStatus = HAL_ERROR;
    return HAL_ERROR;
  }

  if (((type == COMM_TYPE_TREMOR) &&
       (length != (uint8_t)sizeof(TremorSample_t))) ||
      ((type == COMM_TYPE_BATTERY) &&
       (length != (uint8_t)sizeof(BatteryStatus_t))) ||
      ((type != COMM_TYPE_TREMOR) &&
       (type != COMM_TYPE_BATTERY)) ||
      (length == 0U) ||
      (length > COMM_MAX_PAYLOAD_SIZE))
  {
    commTxErrorCount++;
    lastCommTxType = type;
    lastCommTxLength = length;
    lastCommTxStatus = HAL_ERROR;
    return HAL_ERROR;
  }

  frame[0] = COMM_HEADER_1;  /* 0xAA */
  frame[1] = COMM_HEADER_2;  /* 0x55 */
  frame[2] = type;           /* 0x01 tremor / 0x02 battery */
  frame[3] = length;         /* 0x10 tremor / 0x04 battery */

  memcpy(&frame[COMM_HEADER_SIZE], payload, length);

  lastCommTxType = type;
  lastCommTxLength = length;

  status = HAL_UART_Transmit(
      &huart1,
      frame,
      (uint16_t)(COMM_HEADER_SIZE + length),
      TREMOR_UART_TIMEOUT_MS
  );

  lastCommTxStatus = status;

  if (status == HAL_OK)
  {
    commTxFrameCount++;

    if (type == COMM_TYPE_TREMOR)
    {
      commTremorTxCount++;
    }
    else
    {
      commBatteryTxCount++;
    }
  }
  else
  {
    commTxErrorCount++;
  }

  return status;
}


/* ========================================================================== */
/* Battery monitor / battery telemetry                                         */
/* ========================================================================== */

static uint8_t Battery_VoltageToPercent(float packVoltage)
{
  const float cell = packVoltage / 3.0f;

  if (cell >= 4.20f) return 100U;
  if (cell >= 4.15f) return 95U;
  if (cell >= 4.11f) return 90U;
  if (cell >= 4.08f) return 85U;
  if (cell >= 4.02f) return 80U;
  if (cell >= 3.98f) return 75U;
  if (cell >= 3.95f) return 70U;
  if (cell >= 3.91f) return 65U;
  if (cell >= 3.87f) return 60U;
  if (cell >= 3.85f) return 55U;
  if (cell >= 3.84f) return 50U;
  if (cell >= 3.82f) return 45U;
  if (cell >= 3.80f) return 40U;
  if (cell >= 3.79f) return 35U;
  if (cell >= 3.77f) return 30U;
  if (cell >= 3.75f) return 25U;
  if (cell >= 3.73f) return 20U;
  if (cell >= 3.71f) return 15U;
  if (cell >= 3.69f) return 10U;
  if (cell >= 3.61f) return 5U;

  return 0U;
}

static uint8_t Battery_MakeFlags(uint8_t percent, uint8_t adcOk)
{
  uint8_t flags = 0U;

  if (adcOk == 0U)
  {
    flags |= BATTERY_FLAG_ADC_ERROR;
  }

  if (percent <= BATTERY_LOW_PERCENT)
  {
    flags |= BATTERY_FLAG_LOW;
  }

  if (percent <= BATTERY_CRITICAL_PERCENT)
  {
    flags |= BATTERY_FLAG_CRITICAL;
  }

  return flags;
}

static uint8_t Battery_ReadVoltage(float *packVoltage)
{
  uint32_t sum = 0U;
  uint32_t validSamples = 0U;
  uint32_t i;

  if (packVoltage == NULL)
  {
    return 0U;
  }

  for (i = 0U; i < BATTERY_ADC_SAMPLES; ++i)
  {
    if (HAL_ADC_Start(&hadc1) != HAL_OK)
    {
      continue;
    }

    if (HAL_ADC_PollForConversion(&hadc1, 2U) == HAL_OK)
    {
      sum += HAL_ADC_GetValue(&hadc1);
      validSamples++;
    }

    (void)HAL_ADC_Stop(&hadc1);
  }

  if (validSamples == 0U)
  {
    return 0U;
  }

  {
    const float adcRaw =
        (float)sum / (float)validSamples;

    const float adcVoltage =
        (adcRaw / ADC_MAX_VALUE_12BIT) *
        ADC_REFERENCE_VOLTAGE;

    *packVoltage =
        adcVoltage *
        VOLTAGE_DIVIDER_RATIO *
        VOLTAGE_CALIBRATION;
  }

  return 1U;
}

static void Battery_Update(void)
{
  float measuredVoltage = 0.0f;
  const uint8_t adcOk =
      Battery_ReadVoltage(&measuredVoltage);

  if (adcOk == 0U)
  {
    batteryAdcErrorCount++;
    batteryFlags =
        Battery_MakeFlags(batteryPercent, 0U);
    return;
  }

  if (batteryFilterInitialized == 0U)
  {
    filteredBatteryVoltage = measuredVoltage;
    batteryFilterInitialized = 1U;
  }
  else
  {
    filteredBatteryVoltage =
        (filteredBatteryVoltage * 0.75f) +
        (measuredVoltage * 0.25f);
  }

  if (filteredBatteryVoltage < 0.0f)
  {
    filteredBatteryVoltage = 0.0f;
  }

  if (filteredBatteryVoltage > 65.535f)
  {
    filteredBatteryVoltage = 65.535f;
  }

  batteryVoltageMv =
      (uint16_t)(filteredBatteryVoltage * 1000.0f + 0.5f);

  batteryPercent =
      Battery_VoltageToPercent(filteredBatteryVoltage);

  batteryFlags =
      Battery_MakeFlags(batteryPercent, 1U);
}

static void Battery_SendStatus(void)
{
  BatteryStatus_t status = {0};

  status.battery_mv = batteryVoltageMv;
  status.battery_percent = batteryPercent;
  status.battery_flags = batteryFlags;

  if (Comm_SendPacket(
          COMM_TYPE_BATTERY,
          &status,
          (uint8_t)sizeof(status)
      ) != HAL_OK)
  {
    batteryUartErrorCount++;
  }
}

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

  /* Actual applied motor-command status, not merely gate status. */
  sample.motor_enabled = (motor_output_active_debug != 0U) ? 1U : 0U;
  motorEnabledForApp = sample.motor_enabled;

  imuUartStatus = Comm_SendPacket(
      COMM_TYPE_TREMOR,
      &sample,
      (uint8_t)sizeof(sample)
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

static int16_t Control_DecodeValue(uint8_t command, uint16_t rawValue)
{
  /*
   * New App protocol:
   *
   *   0x02 00 06 -> -6 mm (preset negative)
   *   0x03 00 06 -> +6 mm (preset positive)
   *   0x04 00 06 -> -6 mm (manual negative input)
   *   0x05 00 06 -> +6 mm (manual positive input)
   *   0x04 00 32 -> -50 mm (manual negative input)
   *   0x05 00 32 -> +50 mm (manual positive input)
   *
   * Byte1..Byte2 is always sent as a positive big-endian magnitude.
   */
  if (rawValue > CONTROL_MAX_MAGNITUDE_MM)
  {
    return (int16_t)(CONTROL_MAX_MAGNITUDE_MM + 1U);
  }

  if ((command == CMD_ADJUST_LENGTH_NEGATIVE_MM) ||
      (command == CMD_MANUAL_LENGTH_NEGATIVE_MM))
  {
    return -(int16_t)rawValue;
  }

  return (int16_t)rawValue;
}

static uint8_t Control_ApplyCommand(uint8_t command, int16_t value)
{
  float candidateTargetMm;
  float commandBaseMm;

  switch (command)
  {
    case CMD_ADJUST_LENGTH_NEGATIVE_MM:
    case CMD_ADJUST_LENGTH_POSITIVE_MM:
    case CMD_MANUAL_LENGTH_NEGATIVE_MM:
    case CMD_MANUAL_LENGTH_POSITIVE_MM:
      /*
       * value has already been decoded:
       *   0x02 00 06 -> value = -6 mm -> TAKE-UP 6 mm (preset)
       *   0x03 00 06 -> value = +6 mm -> RELEASE 6 mm (preset)
       *   0x04 00 06 -> value = -6 mm -> TAKE-UP 6 mm (manual App input)
       *   0x05 00 06 -> value = +6 mm -> RELEASE 6 mm (manual App input)
       *   0x04 00 32 -> value = -50 mm
       *   0x05 00 32 -> value = +50 mm
       */
      if ((value < -(int16_t)CONTROL_MAX_MAGNITUDE_MM) ||
          (value > (int16_t)CONTROL_MAX_MAGNITUDE_MM))
      {
        lengthAdjustRejectedCount++;
        return 0U;
      }

      if ((tremorPositionState != TREMOR_POSITION_IDLE) &&
          (tremorPositionState != TREMOR_POSITION_HOLDING))
      {
        lengthAdjustBlocked = 1U;
        lengthAdjustRejectedCount++;
        return 0U;
      }

      commandBaseMm = currentLengthMm;
      candidateTargetMm = commandBaseMm + (float)value;

      if ((candidateTargetMm < LENGTH_MIN_MM) ||
          (candidateTargetMm > LENGTH_MAX_MM))
      {
        lengthAdjustRejectedCount++;
        return 0U;
      }

      if ((tremorPositionState == TREMOR_POSITION_HOLDING) &&
          (candidateTargetMm > baseCableLengthMm))
      {
        lengthAdjustBlocked = 1U;
        lengthAdjustRejectedCount++;
        return 0U;
      }

      appRequestedLengthMm = candidateTargetMm;
      targetLengthMm = appRequestedLengthMm;
      lengthErrorMm = targetLengthMm - currentLengthMm;
      lastLengthDeltaMm = value;

      if (value != 0)
      {
        lengthAdjustPending = 1U;
        lengthAdjustBlocked = 0U;
        lengthAdjustRequestCount++;
      }
      else
      {
        lengthAdjustPending = 0U;
      }

      return 1U;

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
  uint16_t rawValue;
  int16_t decodedValue;
  uint8_t valid;

  if (huart->Instance != USART1)
  {
    return;
  }

  command = controlRxBuffer[0];
  rawValue = ((uint16_t)controlRxBuffer[1] << 8) |
             (uint16_t)controlRxBuffer[2];

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

  /* The supplied final-mechanism calibration makes the encoder authoritative
   * for this test.  Count zero is defined as the 400 mm physical home. */
  encoder_zero_count = 0;
  encoder_position_zeroed = (encoder_valid != 0U) ? 1U : 0U;
  calibration_required = (encoder_valid != 0U) ? 0U : 1U;
  encoder_set_zero_request = 0U;
  encoder_set_zero_status = (encoder_valid != 0U) ? 1 : -1;

  currentLengthMm = INITIAL_CABLE_LENGTH_MM;
  targetLengthMm = INITIAL_CABLE_LENGTH_MM;
  lengthErrorMm = 0.0f;
  baseCableLengthMm = INITIAL_CABLE_LENGTH_MM;
  appRequestedLengthMm = INITIAL_CABLE_LENGTH_MM;
  positionMoveStartCount = 0;
  positionMoveRequestedCounts = 0;
  positionMoveTravelCounts = 0;
  positionMoveStartLengthMm = INITIAL_CABLE_LENGTH_MM;
  positionMoveLengthDirection = 0;
  lengthAdjustPending = 0U;
  lengthAdjustActive = 0U;
  lengthAdjustBlocked = 0U;
  encoderLengthCalibrated = (encoder_valid != 0U) ? 1U : 0U;
}

static int32_t Encoder_AbsDeltaCounts(int32_t a, int32_t b)
{
  int64_t delta = (int64_t)a - (int64_t)b;

  if (delta < 0)
  {
    delta = -delta;
  }

  if (delta > (int64_t)INT32_MAX)
  {
    return INT32_MAX;
  }

  return (int32_t)delta;
}

static int32_t Encoder_MmToCounts(float mm)
{
  float magnitude = fabsf(mm);
  float counts = magnitude * ENCODER_COUNTS_PER_MM;

  if (counts <= 0.0f)
  {
    return 0;
  }

  if (counts >= (float)INT32_MAX)
  {
    return INT32_MAX;
  }

  return (int32_t)(counts + 0.5f);
}

static double TremorPosition_SelectDuty(int32_t absErrorCounts)
{
  double duty;

  if (absErrorCounts > POSITION_MEDIUM_ZONE_COUNTS)
  {
    duty = POSITION_FAST_DUTY;
  }
  else if (absErrorCounts > POSITION_SLOW_ZONE_COUNTS)
  {
    duty = POSITION_MEDIUM_DUTY;
  }
  else
  {
    duty = POSITION_SLOW_DUTY;
  }

  /* Never request more than the reviewed motor-bench configuration permits. */
  if (duty > MOTOR_COMMAND_MAX_DUTY_FRACTION)
  {
    duty = MOTOR_COMMAND_MAX_DUTY_FRACTION;
  }


  if (duty < 0.0)
  {
    duty = 0.0;
  }

  return duty;
}

static void TremorPosition_EnterFault(void)
{
  tremorPositionFaultLatched = 1U;
  tremorPositionState = TREMOR_POSITION_FAULT;
  motor_runtime_fault_latched = 1U;
  lengthAdjustActive = 0U;
  ControlPipeline_ForceSafe();
}

static uint8_t App_StartPendingAdjustment(
    int32_t currentCount,
    uint8_t resumeHolding
)
{
  float deltaMm;
  int32_t requestedCounts;

  if (lengthAdjustPending == 0U)
  {
    return 0U;
  }

  deltaMm = appRequestedLengthMm - currentLengthMm;
  requestedCounts = Encoder_MmToCounts(deltaMm);

  /* A sub-count request is already effectively complete. */
  if (requestedCounts <= 0)
  {
    currentLengthMm = appRequestedLengthMm;
    targetLengthMm = appRequestedLengthMm;
    lengthErrorMm = 0.0f;
    lengthAdjustPending = 0U;
    lengthAdjustActive = 0U;
    lengthAdjustBlocked = 0U;
    lengthAdjustCompleteCount++;

    if (resumeHolding == 0U)
    {
      baseCableLengthMm = currentLengthMm;
      tremorHomeCount = currentCount;
      tremorTargetCount = currentCount;
    }

    return 0U;
  }

  positionMoveStartCount = currentCount;
  positionMoveRequestedCounts = requestedCounts;
  positionMoveTravelCounts = 0;
  positionMoveStartLengthMm = currentLengthMm;
  positionMoveLengthDirection = (deltaMm < 0.0f) ? -1 : 1;
  appAdjustmentResumeHolding = (resumeHolding != 0U) ? 1U : 0U;

  targetLengthMm = appRequestedLengthMm;
  lengthErrorMm = targetLengthMm - currentLengthMm;
  lengthAdjustActive = 1U;
  lengthAdjustBlocked = 0U;
  tremorPositionState = TREMOR_POSITION_APP_ADJUSTING;

  return 1U;
}

static void TremorPositionController_Init(void)
{
  tremorPositionState = TREMOR_POSITION_IDLE;
  tremorHomeCount = encoder_count;
  tremorTargetCount = tremorHomeCount;
  tremorPositionErrorCounts = 0;
  tremorPositionFaultLatched = 0U;
  tremorPullTriggerCount = 0U;
  tremorReturnCompleteCount = 0U;
  tremorActualPulledCounts = 0;

  positionMoveStartCount = encoder_count;
  positionMoveRequestedCounts = 0;
  positionMoveTravelCounts = 0;
  positionMoveStartLengthMm = INITIAL_CABLE_LENGTH_MM;
  positionMoveLengthDirection = 0;

  baseCableLengthMm = INITIAL_CABLE_LENGTH_MM;
  appRequestedLengthMm = INITIAL_CABLE_LENGTH_MM;
  targetLengthMm = INITIAL_CABLE_LENGTH_MM;
  currentLengthMm = INITIAL_CABLE_LENGTH_MM;
  lengthErrorMm = 0.0f;
}

static uint8_t TremorPositionController_Update(
    uint8_t gateActive,
    int8_t *motorDirection,
    double *dutyFraction
)
{
  QuadratureEncoderSnapshot snapshot;
  int32_t currentCount;
  int32_t remainingCounts;
  float availablePullMm;
  float pullMm;

  if ((motorDirection == NULL) || (dutyFraction == NULL))
  {
    TremorPosition_EnterFault();
    return 0U;
  }

  *motorDirection = 0;
  *dutyFraction = 0.0;

  memset(&snapshot, 0, sizeof(snapshot));
  if (SnapshotEncoder(&snapshot) != 1U)
  {
    TremorPosition_EnterFault();
    return 0U;
  }

  currentCount = snapshot.count;
  encoder_count = currentCount;

  switch (tremorPositionState)
  {
    case TREMOR_POSITION_IDLE:
      tremorHomeCount = currentCount;
      tremorTargetCount = currentCount;
      tremorPositionErrorCounts = 0;
      lengthAdjustActive = 0U;
      targetLengthMm = baseCableLengthMm;

      /* App adjustment is allowed in IDLE and is handled before a new Gate. */
      if (lengthAdjustPending != 0U)
      {
        (void)App_StartPendingAdjustment(currentCount, 0U);
        return 0U;
      }

      if (gateActive != 0U)
      {
        /* Each tremor event captures the current encoder count as its own Home.
         * Completion depends only on travelled encoder counts, not count sign. */
        tremorHomeCount = currentCount;

        availablePullMm = currentLengthMm - LENGTH_MIN_MM;
        pullMm = TREMOR_PULL_LENGTH_MM;
        if (pullMm > availablePullMm)
        {
          pullMm = availablePullMm;
        }

        positionMoveStartCount = currentCount;
        positionMoveRequestedCounts = Encoder_MmToCounts(pullMm);
        positionMoveTravelCounts = 0;
        positionMoveStartLengthMm = currentLengthMm;
        positionMoveLengthDirection = -1; /* TAKE-UP shortens cable. */

        tremorTargetCount = currentCount; /* legacy debug only; sign-independent. */
        targetLengthMm = currentLengthMm - pullMm;
        tremorActualPulledCounts = 0;
        tremorPositionErrorCounts = positionMoveRequestedCounts;
        tremorPositionState = TREMOR_POSITION_PULLING;
        tremorPullTriggerCount++;
      }
      return 0U;

    case TREMOR_POSITION_PULLING:
      positionMoveTravelCounts =
          Encoder_AbsDeltaCounts(currentCount, positionMoveStartCount);
      remainingCounts =
          positionMoveRequestedCounts - positionMoveTravelCounts;
      if (remainingCounts < 0)
      {
        remainingCounts = 0;
      }
      tremorPositionErrorCounts = remainingCounts;
      lengthAdjustActive = 1U;

      /* Gate disappeared before full pull: remember exactly how many encoder
       * counts were actually wound, then release that same distance. */
      if (gateActive == 0U)
      {
        tremorActualPulledCounts = positionMoveTravelCounts;
        positionMoveStartCount = currentCount;
        positionMoveRequestedCounts = tremorActualPulledCounts;
        positionMoveTravelCounts = 0;
        positionMoveStartLengthMm = currentLengthMm;
        positionMoveLengthDirection = 1; /* RELEASE lengthens cable. */
        targetLengthMm = baseCableLengthMm;
        tremorTargetCount = tremorHomeCount;
        tremorPositionState = TREMOR_POSITION_RETURNING;
        return 0U;
      }

      if (positionMoveTravelCounts >= positionMoveRequestedCounts)
      {
        tremorActualPulledCounts = positionMoveTravelCounts;
        currentLengthMm = targetLengthMm;
        tremorPositionState = TREMOR_POSITION_HOLDING;
        tremorPositionErrorCounts = 0;
        lengthAdjustActive = 0U;
        return 0U;
      }

      *motorDirection = POSITION_TAKE_UP_MOTOR_DIRECTION;
      *dutyFraction = TremorPosition_SelectDuty(remainingCounts);
      return (*dutyFraction > 0.0) ? 1U : 0U;

    case TREMOR_POSITION_HOLDING:
      lengthAdjustActive = 0U;
      tremorPositionErrorCounts = 0;

      if (gateActive == 0U)
      {
        /* Return by the actual encoder distance from this tremor event. */
        tremorActualPulledCounts =
            Encoder_AbsDeltaCounts(currentCount, tremorHomeCount);
        positionMoveStartCount = currentCount;
        positionMoveRequestedCounts = tremorActualPulledCounts;
        positionMoveTravelCounts = 0;
        positionMoveStartLengthMm = currentLengthMm;
        positionMoveLengthDirection = 1; /* RELEASE */
        targetLengthMm = baseCableLengthMm;
        tremorTargetCount = tremorHomeCount;
        tremorPositionState = TREMOR_POSITION_RETURNING;
        return 0U;
      }

      /* App may fine-tune the held cable length.  Home remains unchanged so
       * Gate-off still returns to the pre-tremor baseline. */
      if (lengthAdjustPending != 0U)
      {
        (void)App_StartPendingAdjustment(currentCount, 1U);
      }
      return 0U;

    case TREMOR_POSITION_RETURNING:
      positionMoveTravelCounts =
          Encoder_AbsDeltaCounts(currentCount, positionMoveStartCount);
      remainingCounts =
          positionMoveRequestedCounts - positionMoveTravelCounts;
      if (remainingCounts < 0)
      {
        remainingCounts = 0;
      }
      tremorPositionErrorCounts = remainingCounts;
      lengthAdjustActive = 1U;

      if (positionMoveTravelCounts >= positionMoveRequestedCounts)
      {
        currentLengthMm = baseCableLengthMm;
        tremorPositionState = TREMOR_POSITION_IDLE;
        tremorHomeCount = currentCount;
        tremorTargetCount = currentCount;
        tremorPositionErrorCounts = 0;
        targetLengthMm = baseCableLengthMm;
        lengthAdjustActive = 0U;
        tremorReturnCompleteCount++;
        return 0U;
      }

      *motorDirection = POSITION_RETURN_MOTOR_DIRECTION;
      *dutyFraction = TremorPosition_SelectDuty(remainingCounts);
      return (*dutyFraction > 0.0) ? 1U : 0U;

    case TREMOR_POSITION_APP_ADJUSTING:
      positionMoveTravelCounts =
          Encoder_AbsDeltaCounts(currentCount, positionMoveStartCount);
      remainingCounts =
          positionMoveRequestedCounts - positionMoveTravelCounts;
      if (remainingCounts < 0)
      {
        remainingCounts = 0;
      }
      tremorPositionErrorCounts = remainingCounts;
      lengthAdjustActive = 1U;
      targetLengthMm = appRequestedLengthMm;

      if (positionMoveTravelCounts >= positionMoveRequestedCounts)
      {
        currentLengthMm = appRequestedLengthMm;
        lengthErrorMm = 0.0f;
        lengthAdjustPending = 0U;
        lengthAdjustActive = 0U;
        lengthAdjustBlocked = 0U;
        lengthAdjustCompleteCount++;
        tremorPositionErrorCounts = 0;

        if (appAdjustmentResumeHolding != 0U)
        {
          /* App changed the held tension.  Re-measure actual pull distance from
           * the original tremor Home so Gate-off releases exactly that amount. */
          tremorActualPulledCounts =
              Encoder_AbsDeltaCounts(currentCount, tremorHomeCount);
          tremorPositionState = TREMOR_POSITION_HOLDING;
        }
        else
        {
          /* An IDLE App adjustment becomes the new baseline/home. */
          baseCableLengthMm = currentLengthMm;
          tremorHomeCount = currentCount;
          tremorTargetCount = currentCount;
          tremorPositionState = TREMOR_POSITION_IDLE;
        }

        return 0U;
      }

      if (positionMoveLengthDirection < 0)
      {
        *motorDirection = POSITION_TAKE_UP_MOTOR_DIRECTION;
      }
      else
      {
        *motorDirection = POSITION_RETURN_MOTOR_DIRECTION;
      }

      *dutyFraction = TremorPosition_SelectDuty(remainingCounts);
      return (*dutyFraction > 0.0) ? 1U : 0U;

    case TREMOR_POSITION_FAULT:
    default:
      lengthAdjustActive = 0U;
      return 0U;
  }
}

static void Encoder_UpdateLength(void)
{
  QuadratureEncoderSnapshot snapshot;
  int32_t travelCounts;
  float movedMm;

  memset(&snapshot, 0, sizeof(snapshot));
  if (SnapshotEncoder(&snapshot) != 1U)
  {
    encoder_position_zeroed = 0U;
    calibration_required = 1U;
    TremorPosition_EnterFault();
    return;
  }

  if ((tremorPositionState == TREMOR_POSITION_PULLING) ||
      (tremorPositionState == TREMOR_POSITION_RETURNING) ||
      (tremorPositionState == TREMOR_POSITION_APP_ADJUSTING))
  {
    travelCounts =
        Encoder_AbsDeltaCounts(snapshot.count, positionMoveStartCount);
    positionMoveTravelCounts = travelCounts;
    movedMm = (float)travelCounts / ENCODER_COUNTS_PER_MM;

    currentLengthMm =
        positionMoveStartLengthMm +
        ((float)positionMoveLengthDirection * movedMm);

    if (currentLengthMm < LENGTH_MIN_MM)
    {
      currentLengthMm = LENGTH_MIN_MM;
    }
    else if (currentLengthMm > LENGTH_MAX_MM)
    {
      currentLengthMm = LENGTH_MAX_MM;
    }
  }

  encoderLengthCalibrated = 1U;
  encoder_position_zeroed = 1U;
  calibration_required = 0U;
  lengthErrorMm = targetLengthMm - currentLengthMm;
  lengthAdjustBlocked = (tremorPositionFaultLatched != 0U) ? 1U : 0U;
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

  motor_runtime_armed = MOTOR_DEFAULT_RUNTIME_ARMED;
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
      MOTOR_SUPPRESSION_ESTIMATOR,
      NULL
  );
  suppression_control_ready_debug = suppression_ok;

  hal_config.pwm_timer = &htim1;
  hal_config.pwm_channel = MOTOR_PWM_CHANNEL;
  hal_config.pwm_full_scale_ccr = MOTOR_PWM_FULL_SCALE_CCR;
  hal_config.max_active_ccr = MOTOR_MAX_ACTIVE_CCR;
  hal_config.release_ain1_level = MOTOR_RELEASE_AIN1_LEVEL;
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
  TremorPositionController_Init();

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
           &initial_output) != HAL_OK))
  {
    mapper_fault_debug = motor_mapper.current_fault;
    driver_fault_debug = initial_output.fault;
    position_fault_debug = motor_position_guard.fault;
    motor_runtime_fault_latched = 1U;
    ControlPipeline_ForceSafe();
    return suppression_ok;
  }

#if (MOTOR_POWERED_BENCH_MODE == 0U)
  if ((MotorPositionGuard_Init(
           &motor_position_guard,
           &motor_position_config) != 1U) ||
      (encoder_valid != 1U))
  {
    position_fault_debug = motor_position_guard.fault;
    motor_runtime_fault_latched = 1U;
    ControlPipeline_ForceSafe();
    return suppression_ok;
  }
#else
  /* Encoder-position mode: the legacy MotorPositionGuard remains bypassed,
   * but the quadrature encoder itself is now authoritative for stopping. */
  (void)motor_position_config;
  calibration_required = (encoder_valid != 0U) ? 0U : 1U;
  motor_output_guard_ready_debug = (encoder_valid != 0U) ? 1U : 0U;
#endif

  motor_chain_initialized = 1U;
#else
  /* Explicit disabled profile. */
  (void)motor_mapper_config;
  (void)approved_motor_mapper_config;
  (void)motor_position_config;
  (void)tb6612_driver_config;
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
      ((MOTOR_POWERED_BENCH_MODE == 1U) ||
       ((motor_position_guard.zeroed == 1U) &&
        (motor_position_guard.fault_latched == 0U) &&
        (encoder_ok == 1U)))
      ? 1U : 0U;
}

static void ControlPipeline_100HzFreshSample(double raw_gyro_dps)
{
  Tb6612Output candidate;
  Tb6612Output safe_output;
  Tb6612DriverResult driver_result;
  Tb6612DriverResult safe_result;
  uint32_t cycle_start;
  uint32_t irq_primask;
  HAL_StatusTypeDef apply_status;
  uint8_t suppression_permission;
  uint8_t gate_trigger;
  uint8_t hardware_permission;
  uint8_t position_command_active;
  uint8_t candidate_active;
  uint8_t prior_driver_fault;
  uint8_t final_recheck_ok;
  int8_t position_direction;
  double position_duty;

  memset(&candidate, 0, sizeof(candidate));
  memset(&safe_output, 0, sizeof(safe_output));
  memset(&motor_command_output, 0, sizeof(motor_command_output));

  prior_driver_fault =
      ((motor_runtime_fault_latched != 0U) ||
       (motor_hal_error_debug != 0U) ||
       (driver_fault_debug != (uint8_t)TB6612_DRIVER_FAULT_NONE) ||
       (tremorPositionFaultLatched != 0U))
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

  /* Gate is now a TRIGGER only.  tremorEstimate / compensationRequestDps sign
   * is still available for diagnostics but no longer commands motor direction. */
  gate_trigger =
      ((suppression_permission == 1U) &&
       (suppression_output.actuation_permitted == 1U) &&
       (gate_enabled_debug == 1U))
      ? 1U : 0U;
  suppression_start_allowed = gate_trigger;

  hardware_permission =
      ((motor_bench_config_approved == 1U) &&
       (motor_chain_initialized == 1U) &&
       (motor_runtime_armed == 1U) &&
       (motor_runtime_fault_latched == 0U) &&
       (tremorPositionFaultLatched == 0U) &&
       (encoder_valid != 0U))
      ? 1U : 0U;

  if (hardware_permission != 1U)
  {
    ControlPipeline_ForceSafe();
    return;
  }

  position_direction = 0;
  position_duty = 0.0;
  position_command_active = TremorPositionController_Update(
      gate_trigger,
      &position_direction,
      &position_duty
  );

  if ((tremorPositionFaultLatched != 0U) ||
      (motor_runtime_fault_latched != 0U))
  {
    ControlPipeline_ForceSafe();
    return;
  }

  /* Keep the existing Live Expressions useful even though the signed tremor
   * mapper is intentionally bypassed by the position controller. */
  motor_command_output.direction =
      (position_command_active != 0U) ? position_direction : 0;
  motor_command_output.duty_fraction =
      (position_command_active != 0U) ? position_duty : 0.0;
  motor_command_output.bridge_enable =
      (position_command_active != 0U) ? 1U : 0U;
  motor_command_output.current_fault = (uint8_t)MOTOR_MAPPER_FAULT_NONE;
  mapper_fault_debug = (uint8_t)MOTOR_MAPPER_FAULT_NONE;

  driver_result = TB6612Driver_Update(
      &tb6612_driver,
      (position_command_active != 0U) ? position_direction : 0,
      (position_command_active != 0U) ? position_duty : 0.0,
      (position_command_active != 0U) ? 1U : 0U,
      &candidate
  );
  driver_fault_debug = candidate.fault;

  if (driver_result == TB6612_DRIVER_ERROR)
  {
    motor_runtime_fault_latched = 1U;
    ControlPipeline_ForceSafe();
    return;
  }

  candidate_active =
      ((driver_result == TB6612_DRIVER_ACTIVE) &&
       (candidate.stby == 1U) &&
       (candidate.ccr > 0U))
      ? 1U : 0U;

  if (candidate_active == 1U)
  {
    irq_primask = __get_PRIMASK();
    __disable_irq();

    final_recheck_ok =
        ((fresh_sample_available == 1U) &&
         (scheduler_overrun_this_tick == 0U) &&
         (tick_flag == 0U) &&
         (software_tick_count == control_tick_count) &&
         (motor_runtime_fault_latched == 0U) &&
         (tremorPositionFaultLatched == 0U) &&
         (motor_runtime_armed == 1U) &&
         (motor_bench_config_approved == 1U) &&
         (quadrature_encoder.initialized == 1U) &&
         (quadrature_encoder.invalid_transition_latched == 0U) &&
         (quadrature_encoder.overflow_latched == 0U))
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
    safe_result = TB6612Driver_Update(
        &tb6612_driver, 0, 0.0, 0U, &safe_output);
    if ((safe_result == TB6612_DRIVER_ERROR) ||
        (STM32_TB6612_HAL_Apply(&tb6612_hal, &safe_output) != HAL_OK))
    {
      motor_hal_error_debug = 1U;
      motor_runtime_fault_latched = 1U;
      ControlPipeline_ForceSafe();
      return;
    }
    PublishSafeDriverTelemetry(&safe_output);
  }

  motor_output_guard_ready_debug =
      ((encoder_valid != 0U) &&
       (tremorPositionFaultLatched == 0U) &&
       (motor_runtime_fault_latched == 0U))
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
/* int32_t timeout; */  /* CM4 synchronization disabled for CM7-only test. */
/* USER CODE END Boot_Mode_Sequence_0 */

/* USER CODE BEGIN Boot_Mode_Sequence_1 */
/*
 * CM4 / D2 domain startup synchronization disabled for CM7-only test.
 * Original code is intentionally kept here as comments and can be restored.
 *
  timeout = 0xFFFF;

  while ((__HAL_RCC_GET_FLAG(RCC_FLAG_D2CKRDY) != RESET) &&
         (timeout-- > 0))
  {
  }

  if (timeout < 0)
  {
    Error_Handler();
  }
*/
/* USER CODE END Boot_Mode_Sequence_1 */
  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /*
   * Cold-boot diagnostic delay:
   * allow board power rails and external clock source to stabilize
   * before SystemClock_Config().
   */
  HAL_Delay(1000U);

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();
/* USER CODE BEGIN Boot_Mode_Sequence_2 */
/*
 * CM4 HSEM wake-up / D2 domain synchronization disabled for CM7-only test.
 * Original code is intentionally kept here as comments and can be restored.
 *
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
*/
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
  MX_ADC1_Init();
  /* USER CODE BEGIN 2 */

  DWT_Init();

  /* Initializes the gate/estimator and powered-bench motor path.  GPIO still
   * starts safe; STBY rises only after a fresh sample makes the gate active. */
  (void)ControlPipeline_Init();

  /*
   * Battery ADC calibration + first reading.
   * PC0 / ADC1_IN10 is configured by the reviewed CubeIDE MSP file.
   */
  if (HAL_ADCEx_Calibration_Start(
          &hadc1,
          ADC_CALIB_OFFSET,
          ADC_SINGLE_ENDED
      ) != HAL_OK)
  {
    batteryAdcErrorCount++;
  }

  Battery_Update();
  nextBatteryTickMs = HAL_GetTick() + BATTERY_UPDATE_INTERVAL_MS;
  nextBatterySendTickMs = HAL_GetTick() + BATTERY_SEND_INTERVAL_MS;

  /*
   * Start real ESP32 -> STM32 UART reception.
   * USART1 TX carries framed tremor/battery telemetry; RX consumes 3-byte
   * App commands.  Keep its IRQ below the 100 Hz control-timer priority.
   */
  HAL_NVIC_SetPriority(USART1_IRQn, 5, 0);
  HAL_NVIC_EnableIRQ(USART1_IRQn);
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
    bno_i2c_address = (0x28U << 1);

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
      bno_i2c_address = (0x29U << 1);

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

      if ((bno_read_status == HAL_OK) &&
          (bno_probe_chip_id == BNO055_ID))
      {
        bno_init_status = Sensor_GyroOnly_Init();
        imu_ready = (bno_init_status == HAL_OK) ? 1U : 0U;
      }
      else
      {
        bno_init_status = HAL_ERROR;
        imu_ready = 0U;
      }
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
    uint32_t nowMs;

    Encoder_ProcessSetZeroRequest();

    /*
     * Service battery telemetry only when a control tick is not already
     * pending, so ADC/UART work cannot delay an available 100 Hz sample.
     */
    if (tick_flag == 0U)
    {
      nowMs = HAL_GetTick();

      if ((int32_t)(nowMs - nextBatteryTickMs) >= 0)
      {
        nextBatteryTickMs = nowMs + BATTERY_UPDATE_INTERVAL_MS;
        Battery_Update();
      }

      nowMs = HAL_GetTick();
      if ((int32_t)(nowMs - nextBatterySendTickMs) >= 0)
      {
        nextBatterySendTickMs = nowMs + BATTERY_SEND_INTERVAL_MS;
        Battery_SendStatus();
      }
    }

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
  * @brief ADC1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_ADC1_Init(void)
{

  /* USER CODE BEGIN ADC1_Init 0 */

  /* USER CODE END ADC1_Init 0 */

  ADC_MultiModeTypeDef multimode = {0};
  ADC_ChannelConfTypeDef sConfig = {0};

  /* USER CODE BEGIN ADC1_Init 1 */

  /* USER CODE END ADC1_Init 1 */
  /** Common config
  */
  hadc1.Instance = ADC1;
  hadc1.Init.ClockPrescaler = ADC_CLOCK_ASYNC_DIV2;
  hadc1.Init.Resolution = ADC_RESOLUTION_12B;
  hadc1.Init.ScanConvMode = ADC_SCAN_DISABLE;
  hadc1.Init.EOCSelection = ADC_EOC_SINGLE_CONV;
  hadc1.Init.LowPowerAutoWait = DISABLE;
  hadc1.Init.ContinuousConvMode = DISABLE;
  hadc1.Init.NbrOfConversion = 1;
  hadc1.Init.DiscontinuousConvMode = DISABLE;
  hadc1.Init.ExternalTrigConv = ADC_SOFTWARE_START;
  hadc1.Init.ExternalTrigConvEdge = ADC_EXTERNALTRIGCONVEDGE_NONE;
  hadc1.Init.ConversionDataManagement = ADC_CONVERSIONDATA_DR;
  hadc1.Init.Overrun = ADC_OVR_DATA_PRESERVED;
  hadc1.Init.LeftBitShift = ADC_LEFTBITSHIFT_NONE;
  hadc1.Init.OversamplingMode = DISABLE;
  if (HAL_ADC_Init(&hadc1) != HAL_OK)
  {
    Error_Handler();
  }
  /** Configure the ADC multi-mode
  */
  multimode.Mode = ADC_MODE_INDEPENDENT;
  if (HAL_ADCEx_MultiModeConfigChannel(&hadc1, &multimode) != HAL_OK)
  {
    Error_Handler();
  }
  /** Configure Regular Channel
  */
  sConfig.Channel = ADC_CHANNEL_10;
  sConfig.Rank = ADC_REGULAR_RANK_1;
  sConfig.SamplingTime = ADC_SAMPLETIME_64CYCLES_5;
  sConfig.SingleDiff = ADC_SINGLE_ENDED;
  sConfig.OffsetNumber = ADC_OFFSET_NONE;
  sConfig.Offset = 0;
  sConfig.OffsetSignedSaturation = DISABLE;
  if (HAL_ADC_ConfigChannel(&hadc1, &sConfig) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN ADC1_Init 2 */

  /* USER CODE END ADC1_Init 2 */

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
   * STBY must be wired to D4/PK1, never hardwired to 3V3.  The TB6612 input
   * has an internal pulldown; an external ~10 kOhm fail-low is optional.
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
  GPIO_InitStruct.Pull = GPIO_PULLUP;
  HAL_GPIO_Init(ENCODER_B_GPIO_PORT, &GPIO_InitStruct);

  GPIO_InitStruct.Pin = ENCODER_A_PIN;
  GPIO_InitStruct.Mode = GPIO_MODE_IT_RISING_FALLING;
  GPIO_InitStruct.Pull = GPIO_PULLUP;
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
  int32_t live_count;

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
  live_count = quadrature_encoder.count;
  encoder_count = live_count;

  if ((quadrature_encoder.initialized != 1U) ||
      (quadrature_encoder.invalid_transition_latched != 0U) ||
      (quadrature_encoder.overflow_latched != 0U))
  {
    encoder_valid = 0U;
    calibration_required = 1U;
    tremorPositionFaultLatched = 1U;
    tremorPositionState = TREMOR_POSITION_FAULT;
    motor_runtime_fault_latched = 1U;
    ControlPipeline_ForceSafe();
    return;
  }

  /* Encoder is the stopping authority.  Stop immediately when the requested
   * travel distance has been reached.  Count sign is intentionally ignored. */
  if ((tremorPositionState == TREMOR_POSITION_PULLING) ||
      (tremorPositionState == TREMOR_POSITION_RETURNING) ||
      (tremorPositionState == TREMOR_POSITION_APP_ADJUSTING))
  {
    const int32_t live_travel =
        Encoder_AbsDeltaCounts(live_count, positionMoveStartCount);

    positionMoveTravelCounts = live_travel;

    if ((positionMoveRequestedCounts > 0) &&
        (live_travel >= positionMoveRequestedCounts))
    {
      ControlPipeline_ForceSafe();
    }
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
