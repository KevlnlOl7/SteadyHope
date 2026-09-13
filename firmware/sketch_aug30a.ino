#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ============================================================
// SteadyHope ESP32-C3 communication bridge
//
// STM32 -> ESP32 UART:
//   AA 55 TYPE LENGTH PAYLOAD
//
//   TYPE 0x01 = TremorSample, 16-byte payload, 100 Hz
//   TYPE 0x02 = BatteryStatus, 4-byte payload, 1 Hz
//
// ESP32 -> App BLE Notify:
//   First byte is message type.
//   0x01 + N * 16-byte TremorSample (normally N=5, 81 bytes total)
//   0x02 + 4-byte BatteryStatus (5 bytes total)
//
// App -> ESP32 -> STM32 control:
//   fixed 3 bytes [command][value_high][value_low]
//   value is a big-endian uint16 magnitude in mm (0..50 = 0..5 cm)
//   0x02 preset negative adjustment
//   0x03 preset positive adjustment
//   0x04 manual negative input
//   0x05 manual positive input
//   0x06 initial baseline length in mm (260..400 = 0..14 cm take-up from 400 mm Home)
//   0x07 automatic mode (0 = MANUAL, 1 = AUTO)
// ============================================================

// ============================================================
// BLE
// ============================================================

#define DEVICE_NAME "SteadyHope"

#define SERVICE_UUID \
  "12345678-1234-1234-1234-123456789000"

#define CONTROL_CHAR_UUID \
  "12345678-1234-1234-1234-123456789001"

static constexpr uint16_t LOCAL_MTU = 185;
static constexpr uint8_t SAMPLES_PER_PACKET = 5;

// BLE notification types.
#define BLE_TYPE_TREMOR   0x01
#define BLE_TYPE_BATTERY  0x02

// ============================================================
// App -> ESP32 -> STM32 control protocol
// ============================================================

#define CMD_LENGTH_NEGATIVE        0x02
#define CMD_LENGTH_POSITIVE        0x03
#define CMD_MANUAL_LENGTH_NEGATIVE 0x04
#define CMD_MANUAL_LENGTH_POSITIVE 0x05
#define CMD_SET_BASELINE_LENGTH    0x06
#define CMD_SET_AUTOMATIC_MODE     0x07
#define CONTROL_PACKET_SIZE        3
#define CONTROL_MAX_MAGNITUDE_MM   50
#define CONTROL_MIN_BASELINE_MM    260
#define CONTROL_MAX_BASELINE_MM    400

// ============================================================
// UART to STM32
// ============================================================

#define STM32_RX_PIN 6
#define STM32_TX_PIN 7
#define STM32_BAUD   115200

HardwareSerial STM32Serial(1);

// STM32 -> ESP32 frame protocol.
#define UART_HEADER_1      0xAA
#define UART_HEADER_2      0x55
#define UART_TYPE_TREMOR   0x01
#define UART_TYPE_BATTERY  0x02

static constexpr uint8_t UART_TREMOR_PAYLOAD_SIZE = 16;
static constexpr uint8_t UART_BATTERY_PAYLOAD_SIZE = 4;
static constexpr uint8_t UART_MAX_PAYLOAD_SIZE = 16;

// ============================================================
// Payload structures - must match STM32 exactly
// ============================================================

#pragma pack(push, 1)

struct TremorSample
{
  uint32_t sequence;
  uint32_t sample_tick_ms;

  int16_t gyro_x_raw;
  int16_t gyro_y_raw;
  int16_t gyro_z_raw;

  uint8_t sensor_valid;
  uint8_t motor_enabled;
};

struct BatteryStatus
{
  uint16_t battery_mv;
  uint8_t battery_percent;
  uint8_t battery_flags;
};

#pragma pack(pop)

static_assert(
  sizeof(TremorSample) == UART_TREMOR_PAYLOAD_SIZE,
  "TremorSample must be exactly 16 bytes"
);

static_assert(
  sizeof(BatteryStatus) == UART_BATTERY_PAYLOAD_SIZE,
  "BatteryStatus must be exactly 4 bytes"
);

static_assert(
  SAMPLES_PER_PACKET >= 1 &&
  SAMPLES_PER_PACKET <= 5,
  "SAMPLES_PER_PACKET must be between 1 and 5"
);

// ============================================================
// BLE state
// ============================================================

BLEServer *pServer = nullptr;
BLECharacteristic *controlCharacteristic = nullptr;

volatile bool deviceConnected = false;
bool oldDeviceConnected = false;
volatile bool clearBlePacketRequested = false;

// ============================================================
// Control state
// ============================================================

int16_t lastLengthAdjustMm = 0;
uint16_t lastBaselineLengthMm = 400;
bool lastAutomaticMode = false;

uint32_t uartControlTxCount = 0;
uint32_t uartControlTxErrorCount = 0;
uint32_t bleControlRxCount = 0;
uint32_t bleControlInvalidCount = 0;

// ============================================================
// UART framed parser
// ============================================================

enum UartParserState : uint8_t
{
  WAIT_HEADER_1 = 0,
  WAIT_HEADER_2,
  READ_TYPE,
  READ_LENGTH,
  READ_PAYLOAD
};

UartParserState uartParserState = WAIT_HEADER_1;
uint8_t uartPacketType = 0;
uint8_t uartPayloadLength = 0;
uint8_t uartPayloadIndex = 0;
uint8_t uartPayload[UART_MAX_PAYLOAD_SIZE] = {0};

uint32_t uartInvalidFrameCount = 0;
uint32_t uartTremorPacketCount = 0;
uint32_t uartBatteryPacketCount = 0;

// ============================================================
// IMU / BLE batching
// ============================================================

TremorSample blePacketBuffer[SAMPLES_PER_PACKET];
uint8_t blePacketSampleCount = 0;

bool hasPreviousSample = false;
uint32_t previousSequence = 0;
uint32_t previousTickMs = 0;

uint32_t uartSampleCount = 0;
uint32_t bleSentSampleCount = 0;
uint32_t bleImuPacketCount = 0;
uint32_t bleBatteryPacketCount = 0;

uint32_t uartSamplesLastSecond = 0;
uint32_t bleSamplesLastSecond = 0;
uint32_t bleImuPacketsLastSecond = 0;
uint32_t batteryPacketsLastSecond = 0;

uint32_t uartSequenceGapCount = 0;
uint32_t uartDuplicateCount = 0;
uint32_t uartTimingErrorCount = 0;
uint32_t invalidFlagCount = 0;

BatteryStatus lastBatteryStatus = {0};
uint32_t lastStatsMs = 0;

// ============================================================
// BLE callbacks
// ============================================================

class ServerCallbacks : public BLEServerCallbacks
{
  void onConnect(BLEServer *server) override
  {
    deviceConnected = true;
    clearBlePacketRequested = true;

    Serial.println();
    Serial.println("[BLE] Device connected");
  }

  void onDisconnect(BLEServer *server) override
  {
    deviceConnected = false;
    clearBlePacketRequested = true;

    Serial.println();
    Serial.println("[BLE] Device disconnected");
  }
};

// ============================================================
// App -> STM32 control
// ============================================================

bool sendControlPacketToSTM32(
  uint8_t command,
  uint16_t value
)
{
  uint8_t uartPacket[CONTROL_PACKET_SIZE] = {
    command,
    static_cast<uint8_t>((value >> 8) & 0xFF),
    static_cast<uint8_t>(value & 0xFF)
  };

  const size_t sent = STM32Serial.write(
    uartPacket,
    sizeof(uartPacket)
  );

  if (sent == sizeof(uartPacket))
  {
    uartControlTxCount++;

    Serial.printf(
      "[UART TX CONTROL] %02X %02X %02X OK\n",
      command,
      uartPacket[1],
      uartPacket[2]
    );

    return true;
  }

  uartControlTxErrorCount++;

  Serial.printf(
    "[UART TX CONTROL] %02X %02X %02X ERROR sent=%u\n",
    command,
    uartPacket[1],
    uartPacket[2],
    static_cast<unsigned int>(sent)
  );

  return false;
}

class ControlCallbacks : public BLECharacteristicCallbacks
{
  void onWrite(BLECharacteristic *characteristic) override
  {
    String rxValue = characteristic->getValue();
    const int length = rxValue.length();

    if (length != CONTROL_PACKET_SIZE)
    {
      bleControlInvalidCount++;
      Serial.printf(
        "[BLE CONTROL] invalid length=%d, expected=%u\n",
        length,
        static_cast<unsigned int>(CONTROL_PACKET_SIZE)
      );
      return;
    }

    const uint8_t command = (uint8_t)rxValue[0];
    const uint16_t value =
      (static_cast<uint16_t>((uint8_t)rxValue[1]) << 8) |
      static_cast<uint16_t>((uint8_t)rxValue[2]);

    bleControlRxCount++;

    switch (command)
    {
      case CMD_LENGTH_NEGATIVE:
      case CMD_MANUAL_LENGTH_NEGATIVE:
        if (value > CONTROL_MAX_MAGNITUDE_MM)
        {
          bleControlInvalidCount++;
          Serial.printf(
            "[BLE CONTROL] invalid relative magnitude=%u, max=%u\n",
            static_cast<unsigned int>(value),
            static_cast<unsigned int>(CONTROL_MAX_MAGNITUDE_MM)
          );
          return;
        }

        // Byte1..Byte2 is always a positive magnitude; command selects minus direction.
        lastLengthAdjustMm = -(int16_t)value;
        sendControlPacketToSTM32(command, value);
        break;

      case CMD_LENGTH_POSITIVE:
      case CMD_MANUAL_LENGTH_POSITIVE:
        if (value > CONTROL_MAX_MAGNITUDE_MM)
        {
          bleControlInvalidCount++;
          Serial.printf(
            "[BLE CONTROL] invalid relative magnitude=%u, max=%u\n",
            static_cast<unsigned int>(value),
            static_cast<unsigned int>(CONTROL_MAX_MAGNITUDE_MM)
          );
          return;
        }

        // Byte1..Byte2 is always a positive magnitude; command selects plus direction.
        lastLengthAdjustMm = (int16_t)value;
        sendControlPacketToSTM32(command, value);
        break;

      case CMD_SET_BASELINE_LENGTH:
        if (value < CONTROL_MIN_BASELINE_MM ||
            value > CONTROL_MAX_BASELINE_MM)
        {
          bleControlInvalidCount++;
          Serial.printf(
            "[BLE CONTROL] invalid initial baseline=%u, allowed=%u..%u mm\n",
            static_cast<unsigned int>(value),
            static_cast<unsigned int>(CONTROL_MIN_BASELINE_MM),
            static_cast<unsigned int>(CONTROL_MAX_BASELINE_MM)
          );
          return;
        }

        lastBaselineLengthMm = value;
        sendControlPacketToSTM32(command, value);
        break;

      case CMD_SET_AUTOMATIC_MODE:
        if (value > 1U)
        {
          bleControlInvalidCount++;
          Serial.printf(
            "[BLE CONTROL] invalid auto mode=%u, expected 0 or 1\n",
            static_cast<unsigned int>(value)
          );
          return;
        }

        lastAutomaticMode = (value == 1U);
        sendControlPacketToSTM32(command, value);
        break;

      default:
        bleControlInvalidCount++;
        Serial.printf(
          "[BLE CONTROL] unknown command=0x%02X\n",
          command
        );
        return;
    }
  }
};

// ============================================================
// BLE notification helpers
// ============================================================

void sendBleImuPacket()
{
  if (
    !deviceConnected ||
    blePacketSampleCount == 0
  )
  {
    blePacketSampleCount = 0;
    return;
  }

  // BLE payload:
  // Byte 0 = 0x01
  // Byte 1.. = N * 16-byte TremorSample
  uint8_t packet[
    1 + SAMPLES_PER_PACKET * sizeof(TremorSample)
  ];

  packet[0] = BLE_TYPE_TREMOR;

  const size_t imuBytes =
    blePacketSampleCount * sizeof(TremorSample);

  memcpy(
    &packet[1],
    blePacketBuffer,
    imuBytes
  );

  const size_t packetSize = 1 + imuBytes;

  controlCharacteristic->setValue(
    packet,
    packetSize
  );

  controlCharacteristic->notify();

  bleSentSampleCount += blePacketSampleCount;
  bleSamplesLastSecond += blePacketSampleCount;
  bleImuPacketCount++;
  bleImuPacketsLastSecond++;

  blePacketSampleCount = 0;
}

void sendBleBatteryPacket(
  const BatteryStatus &status
)
{
  if (!deviceConnected)
  {
    return;
  }

  // BLE payload:
  // Byte 0 = 0x02
  // Byte 1..4 = BatteryStatus
  uint8_t packet[1 + sizeof(BatteryStatus)];

  packet[0] = BLE_TYPE_BATTERY;

  memcpy(
    &packet[1],
    &status,
    sizeof(status)
  );

  controlCharacteristic->setValue(
    packet,
    sizeof(packet)
  );

  controlCharacteristic->notify();

  bleBatteryPacketCount++;
}

// ============================================================
// IMU handling
// ============================================================

void printSample(
  const TremorSample &sample
)
{
  Serial.printf(
    "[IMU] seq=%lu tick=%lu "
    "raw=(%d,%d,%d) "
    "dps=(%.3f,%.3f,%.3f) "
    "valid=%u motor=%u\n",

    static_cast<unsigned long>(sample.sequence),
    static_cast<unsigned long>(sample.sample_tick_ms),

    sample.gyro_x_raw,
    sample.gyro_y_raw,
    sample.gyro_z_raw,

    sample.gyro_x_raw / 16.0f,
    sample.gyro_y_raw / 16.0f,
    sample.gyro_z_raw / 16.0f,

    sample.sensor_valid,
    sample.motor_enabled
  );
}

void validateUartSample(
  const TremorSample &sample
)
{
  if (
    sample.sensor_valid > 1U ||
    sample.motor_enabled > 1U
  )
  {
    invalidFlagCount++;
  }

  if (!hasPreviousSample)
  {
    previousSequence = sample.sequence;
    previousTickMs = sample.sample_tick_ms;
    hasPreviousSample = true;
    return;
  }

  const uint32_t expectedSequence =
    previousSequence + 1U;

  if (sample.sequence == previousSequence)
  {
    uartDuplicateCount++;
  }
  else if (sample.sequence != expectedSequence)
  {
    const uint32_t missing =
      sample.sequence - expectedSequence;

    uartSequenceGapCount += missing;
  }

  const uint32_t tickDelta =
    sample.sample_tick_ms - previousTickMs;

  if (
    tickDelta < 8U ||
    tickDelta > 12U
  )
  {
    uartTimingErrorCount++;
  }

  previousSequence = sample.sequence;
  previousTickMs = sample.sample_tick_ms;
}

void handleNewSample(
  const TremorSample &sample
)
{
  uartSampleCount++;
  uartSamplesLastSecond++;

  validateUartSample(sample);

  if (uartSampleCount <= 10U)
  {
    printSample(sample);
  }

  if (!deviceConnected)
  {
    blePacketSampleCount = 0;
    return;
  }

  blePacketBuffer[blePacketSampleCount] = sample;
  blePacketSampleCount++;

  if (blePacketSampleCount >= SAMPLES_PER_PACKET)
  {
    sendBleImuPacket();
  }
}

void handleBatteryStatus(
  const BatteryStatus &status
)
{
  lastBatteryStatus = status;
  uartBatteryPacketCount++;
  batteryPacketsLastSecond++;

  Serial.printf(
    "[BATTERY] %.3f V %u%% flags=0x%02X\n",
    status.battery_mv / 1000.0f,
    status.battery_percent,
    status.battery_flags
  );

  sendBleBatteryPacket(status);
}

// ============================================================
// UART frame parser
// ============================================================

void resetUartParser()
{
  uartParserState = WAIT_HEADER_1;
  uartPacketType = 0;
  uartPayloadLength = 0;
  uartPayloadIndex = 0;
}

bool uartPacketDefinitionIsValid(
  uint8_t type,
  uint8_t length
)
{
  if (
    type == UART_TYPE_TREMOR &&
    length == sizeof(TremorSample)
  )
  {
    return true;
  }

  if (
    type == UART_TYPE_BATTERY &&
    length == sizeof(BatteryStatus)
  )
  {
    return true;
  }

  return false;
}

void handleCompleteUartPacket()
{
  if (
    uartPacketType == UART_TYPE_TREMOR &&
    uartPayloadLength == sizeof(TremorSample)
  )
  {
    TremorSample sample{};

    memcpy(
      &sample,
      uartPayload,
      sizeof(sample)
    );

    uartTremorPacketCount++;
    handleNewSample(sample);
    return;
  }

  if (
    uartPacketType == UART_TYPE_BATTERY &&
    uartPayloadLength == sizeof(BatteryStatus)
  )
  {
    BatteryStatus status{};

    memcpy(
      &status,
      uartPayload,
      sizeof(status)
    );

    handleBatteryStatus(status);
    return;
  }

  uartInvalidFrameCount++;
}

void processUartByte(uint8_t value)
{
  switch (uartParserState)
  {
    case WAIT_HEADER_1:
      if (value == UART_HEADER_1)
      {
        uartParserState = WAIT_HEADER_2;
      }
      break;

    case WAIT_HEADER_2:
      if (value == UART_HEADER_2)
      {
        uartParserState = READ_TYPE;
      }
      else if (value == UART_HEADER_1)
      {
        // Could be the first byte of a new header.
        uartParserState = WAIT_HEADER_2;
      }
      else
      {
        uartParserState = WAIT_HEADER_1;
      }
      break;

    case READ_TYPE:
      uartPacketType = value;
      uartParserState = READ_LENGTH;
      break;

    case READ_LENGTH:
      uartPayloadLength = value;
      uartPayloadIndex = 0;

      if (
        uartPayloadLength == 0 ||
        uartPayloadLength > UART_MAX_PAYLOAD_SIZE ||
        !uartPacketDefinitionIsValid(
          uartPacketType,
          uartPayloadLength
        )
      )
      {
        uartInvalidFrameCount++;
        resetUartParser();
      }
      else
      {
        uartParserState = READ_PAYLOAD;
      }
      break;

    case READ_PAYLOAD:
      uartPayload[uartPayloadIndex] = value;
      uartPayloadIndex++;

      if (uartPayloadIndex >= uartPayloadLength)
      {
        handleCompleteUartPacket();
        resetUartParser();
      }
      break;
  }
}

void readSTM32Data()
{
  while (STM32Serial.available() > 0)
  {
    const int received = STM32Serial.read();

    if (received < 0)
    {
      return;
    }

    processUartByte((uint8_t)received);
  }
}

// ============================================================
// Statistics
// ============================================================

void printStatistics()
{
  const uint32_t now = millis();

  if (now - lastStatsMs < 1000U)
  {
    return;
  }

  lastStatsMs = now;

  Serial.printf(
    "[STAT] BLE=%u "
    "IMU_UART=%lu/s BAT_UART=%lu/s "
    "BLE_IMU_samples=%lu/s BLE_IMU_notify=%lu/s "
    "battery=%.3fV %u%% "
    "invalidFrames=%lu gaps=%lu duplicates=%lu timingErr=%lu "
    "controlRX=%lu controlInvalid=%lu controlTX=%lu controlTXerr=%lu "
    "auto=%u baseline=%u lastAdjust=%dmm\n",

    deviceConnected ? 1U : 0U,
    static_cast<unsigned long>(uartSamplesLastSecond),
    static_cast<unsigned long>(batteryPacketsLastSecond),
    static_cast<unsigned long>(bleSamplesLastSecond),
    static_cast<unsigned long>(bleImuPacketsLastSecond),
    lastBatteryStatus.battery_mv / 1000.0f,
    lastBatteryStatus.battery_percent,
    static_cast<unsigned long>(uartInvalidFrameCount),
    static_cast<unsigned long>(uartSequenceGapCount),
    static_cast<unsigned long>(uartDuplicateCount),
    static_cast<unsigned long>(uartTimingErrorCount),
    static_cast<unsigned long>(bleControlRxCount),
    static_cast<unsigned long>(bleControlInvalidCount),
    static_cast<unsigned long>(uartControlTxCount),
    static_cast<unsigned long>(uartControlTxErrorCount),
    lastAutomaticMode ? 1U : 0U,
    static_cast<unsigned int>(lastBaselineLengthMm),
    static_cast<int>(lastLengthAdjustMm)
  );

  uartSamplesLastSecond = 0;
  batteryPacketsLastSecond = 0;
  bleSamplesLastSecond = 0;
  bleImuPacketsLastSecond = 0;
}

// ============================================================
// Setup
// ============================================================

void setup()
{
  Serial.begin(115200);
  delay(1000);

  Serial.println();
  Serial.println("====================================");
  Serial.println("SteadyHope BLE + framed UART bridge");
  Serial.println("====================================");

  STM32Serial.begin(
    STM32_BAUD,
    SERIAL_8N1,
    STM32_RX_PIN,
    STM32_TX_PIN
  );

  Serial.printf(
    "STM32 UART: baud=%d RX=%d TX=%d\n",
    STM32_BAUD,
    STM32_RX_PIN,
    STM32_TX_PIN
  );

  Serial.printf(
    "UART Tremor: AA 55 01 10 + %u bytes, 100 Hz\n",
    static_cast<unsigned int>(sizeof(TremorSample))
  );

  Serial.printf(
    "UART Battery: AA 55 02 04 + %u bytes, 1 Hz\n",
    static_cast<unsigned int>(sizeof(BatteryStatus))
  );

  Serial.printf(
    "BLE IMU notify: 1 type byte + %u samples = %u bytes\n",
    SAMPLES_PER_PACKET,
    static_cast<unsigned int>(
      1 + SAMPLES_PER_PACKET * sizeof(TremorSample)
    )
  );

  Serial.printf(
    "BLE Battery notify: %u bytes\n",
    static_cast<unsigned int>(1 + sizeof(BatteryStatus))
  );

  BLEDevice::init(DEVICE_NAME);
  BLEDevice::setMTU(LOCAL_MTU);

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService *service = pServer->createService(
    SERVICE_UUID
  );

  controlCharacteristic = service->createCharacteristic(
    CONTROL_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_WRITE_NR
  );

  controlCharacteristic->setCallbacks(
    new ControlCallbacks()
  );

  controlCharacteristic->addDescriptor(
    new BLE2902()
  );

  uint8_t initialData[1] = {0};
  controlCharacteristic->setValue(
    initialData,
    sizeof(initialData)
  );

  service->start();

  BLEAdvertising *advertising =
    BLEDevice::getAdvertising();

  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();

  resetUartParser();
  lastStatsMs = millis();

  Serial.println("BLE Advertising started");
  Serial.println("Waiting for BLE connection...");
}

// ============================================================
// Loop
// ============================================================

void loop()
{
  readSTM32Data();

  if (clearBlePacketRequested)
  {
    clearBlePacketRequested = false;
    blePacketSampleCount = 0;
  }

  printStatistics();

  if (
    !deviceConnected &&
    oldDeviceConnected
  )
  {
    delay(300);
    pServer->startAdvertising();
    Serial.println("[BLE] Advertising restarted");
    oldDeviceConnected = false;
  }

  if (
    deviceConnected &&
    !oldDeviceConnected
  )
  {
    oldDeviceConnected = true;
  }

  delay(1);
}
