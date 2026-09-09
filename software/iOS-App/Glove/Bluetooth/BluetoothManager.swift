import CoreBluetooth
import Foundation

/// 定義藍牙管理器與外部呼叫端之間的委派協定
public protocol BluetoothManagerDelegate: AnyObject {
    /// 接收解析完成之批次震顫資料點
    func bluetoothManager(_ manager: BluetoothManager, didReceivePoints points: [TremorDataPoint])
    /// 接收最新手套電池電量狀態
    func bluetoothManager(_ manager: BluetoothManager, didUpdateBattery battery: BatteryStatus)
    /// 接收手機系統 CoreBluetooth 狀態變更
    func bluetoothManager(_ manager: BluetoothManager, didUpdateState state: CBManagerState)
    /// 接收藍牙連線就緒狀態（需讀寫與通知皆完成初始化）
    func bluetoothManager(_ manager: BluetoothManager, didUpdateConnection isConnected: Bool)
}

/// 底層 CoreBluetooth 傳輸管理類別，負責設備掃描、GATT 連線、特徵值訂閱及微調指令封裝發送
public final class BluetoothManager: NSObject {

    /// 藍牙委派監聽對象
    public weak var delegate: BluetoothManagerDelegate?

    /// 目標周邊設備名稱與 GATT 服務特徵值識別碼
    private let targetDeviceName = "SteadyHope"
    private let serviceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789000")
    private let ioCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789001")

    /// 單次相對長度命令最大上限值（單位：公釐，50 mm 等於 5 cm）
    private let controlMaxMagnitudeMm = 50

    /// 控制指令位元組標頭列舉
    private enum ControlCommand: UInt8 {
        /// 滑桿相對長度縮短（負值）
        case lengthNegative = 0x02
        /// 滑桿相對長度加長（正值）
        case lengthPositive = 0x03
        /// 手動輸入相對長度縮短（負值）
        case manualLengthNegative = 0x04
        /// 手動輸入相對長度加長（正值）
        case manualLengthPositive = 0x05
    }

    /// CoreBluetooth 核心物件與當前連線周邊設備
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var ioCharacteristic: CBCharacteristic?

    /// 藍牙通道就緒與連線回報狀態旗標
    private var writeReady = false
    private var notifyReady = false
    private var reportedConnectionReady = false

    /// 紀錄前一次發送之控制指令封包資訊（指令 ID 與數值）
    private var lastSentCommand: (commandId: UInt8, value: UInt16)?

    /// 檢查手機系統藍牙是否已開啟
    public var isBluetoothEnabled: Bool {
        centralManager.state == .poweredOn
    }

    /// 檢查手機系統藍牙權限是否未獲授權
    public var isBluetoothUnauthorized: Bool {
        centralManager.state == .unauthorized
    }

    /// 初始化藍牙管理實體並建立 CBCentralManager
    public override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    /// 觸發系統預設之藍牙未開啟提示對話框
    public func triggerSystemPowerAlert() {
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }

    /// 依據指定之服務 UUID 啟動藍牙裝置掃描
    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("[Bluetooth] 無法掃描：藍牙尚未開啟")
            return
        }

        if let peripheral = connectedPeripheral,
           peripheral.state == .connected {
            return
        }

        print("[Bluetooth] 開始搜尋 Service: \(serviceUUID.uuidString)...")

        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// 停止藍牙裝置掃描
    public func stopScanning() {
        if centralManager.isScanning {
            centralManager.stopScan()
            print("[Bluetooth] 停止掃描")
        }
    }

    /// 中斷當前周邊裝置之藍牙連線
    public func disconnect() {
        if let peripheral = connectedPeripheral {
            print("[Bluetooth] 中斷連線: \(peripheral.name ?? targetDeviceName)")
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    /// 發送滑桿相對線長調整量（負值對應 0x02，正值對應 0x03）
    /// - Parameter offsetMm: 帶正負號之調整位移量（公釐）
    public func sendLengthAdjustment(_ offsetMm: Int) {
        print("[Bluetooth] sendLengthAdjustment called: \(offsetMm) mm")

        if offsetMm == 0 {
            print("[Bluetooth] 長度調整為 0 mm，不需送出指令。")
            return
        }

        guard offsetMm != Int.min else {
            print("[Bluetooth] 指令無法發送：調整量無效。")
            return
        }

        let magnitude = abs(offsetMm)
        guard magnitude <= controlMaxMagnitudeMm else {
            print("[Bluetooth] 指令無法發送：單次調整量必須介於 -50...50 mm。")
            return
        }

        let command: ControlCommand = offsetMm < 0 ? .lengthNegative : .lengthPositive
        sendControlPacket(command: command, value: UInt16(magnitude))
    }

    /// 發送手動輸入之相對長度調整量（負值對應 0x04，正值對應 0x05）
    /// - Parameter signedMm: 帶正負號之調整位移量（公釐）
    public func sendManualLengthInput(_ signedMm: Int) {
        print("[Bluetooth] sendManualLengthInput called: \(signedMm) mm")

        if signedMm == 0 {
            print("[Bluetooth] 手動長度輸入為 0 mm，不需送出指令。")
            return
        }

        guard signedMm != Int.min else {
            print("[Bluetooth] 指令無法發送：手動調整量無效。")
            return
        }

        let magnitude = abs(signedMm)
        guard magnitude <= controlMaxMagnitudeMm else {
            print("[Bluetooth] 指令無法發送：手動調整量必須介於 -50...50 mm。")
            return
        }

        let command: ControlCommand = signedMm < 0
            ? .manualLengthNegative
            : .manualLengthPositive

        sendControlPacket(command: command, value: UInt16(magnitude))
    }

    /// 發送手動輸入之負向長度調整量（縮短線長）
    /// - Parameter magnitudeMm: 正整數之縮短量（公釐，範圍 1 至 50）
    public func sendManualNegativeLength(magnitudeMm: Int) {
        guard (1...controlMaxMagnitudeMm).contains(magnitudeMm) else {
            print("[Bluetooth] 負值 magnitude 必須介於 1...50 mm。")
            return
        }
        sendControlPacket(command: .manualLengthNegative, value: UInt16(magnitudeMm))
    }

    /// 發送手動輸入之正向長度調整量（放長線長）
    /// - Parameter magnitudeMm: 正整數之放長量（公釐，範圍 1 至 50）
    public func sendManualPositiveLength(magnitudeMm: Int) {
        guard (1...controlMaxMagnitudeMm).contains(magnitudeMm) else {
            print("[Bluetooth] 正值 magnitude 必須介於 1...50 mm。")
            return
        }
        sendControlPacket(command: .manualLengthPositive, value: UInt16(magnitudeMm))
    }

    /// 組裝 3 位元組控制指令二進位封包並寫入至特徵值
    /// - Parameters:
    ///   - command: 控制指令標頭列舉
    ///   - value: 16 位元無號整數絕對量值（Big-Endian 排列）
    private func sendControlPacket(command: ControlCommand, value: UInt16) {
        guard let peripheral = connectedPeripheral else {
            print("[Bluetooth] 指令無法發送：尚未抓取到周邊設備。")
            return
        }

        guard peripheral.state == .connected else {
            print("[Bluetooth] 指令無法發送：Peripheral 尚未完成 BLE 連線。")
            return
        }

        guard let characteristic = ioCharacteristic else {
            print("[Bluetooth] 指令無法發送：控制 Characteristic 尚未綁定。")
            return
        }

        guard characteristic.uuid == ioCharacteristicUUID else {
            print("[Bluetooth] 指令無法發送：Characteristic UUID 不正確。")
            return
        }

        let high = UInt8((value >> 8) & 0xFF)
        let low = UInt8(value & 0xFF)
        let packet = Data([command.rawValue, high, low])
        let packetHex = packet
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")

        let writeType: CBCharacteristicWriteType
        if characteristic.properties.contains(.write) {
            writeType = .withResponse
        } else if characteristic.properties.contains(.writeWithoutResponse) {
            writeType = .withoutResponse
        } else {
            print("[Bluetooth] 指令無法發送：Characteristic 不支援 Write。")
            return
        }

        print("[Bluetooth] TX -> ESP32: \(packetHex)")

        peripheral.writeValue(
            packet,
            for: characteristic,
            type: writeType
        )

        lastSentCommand = (command.rawValue, value)

        if writeType == .withoutResponse {
            print("[Bluetooth] BLE Write Without Response 已送出: \(packetHex)")
        }
    }

    /// 重設內部特徵值參照與連線就緒狀態
    private func resetConnectionState() {
        ioCharacteristic = nil
        writeReady = false
        notifyReady = false
        reportedConnectionReady = false
        lastSentCommand = nil
    }

    /// 檢查寫入與通知特徵值是否皆已就緒，並於狀態變更時通知委派對象
    private func updateReadyState() {
        let ready = writeReady && notifyReady

        guard ready != reportedConnectionReady else {
            return
        }

        reportedConnectionReady = ready
        delegate?.bluetoothManager(self, didUpdateConnection: ready)
    }
}

extension BluetoothManager: CBCentralManagerDelegate {

    /// 處理系統藍牙狀態更新回呼
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("[Bluetooth] 藍牙狀態變更: \(central.state.rawValue)")
        delegate?.bluetoothManager(self, didUpdateState: central.state)

        if central.state != .poweredOn {
            resetConnectionState()
            delegate?.bluetoothManager(self, didUpdateConnection: false)
        }
    }

    /// 發現目標周邊設備回呼，自動停止掃描並發起連線
    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let discoveredName = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "未知名稱"

        print(
            "[Bluetooth] 發現設備: \(discoveredName), " +
            "UUID: \(peripheral.identifier.uuidString)"
        )

        connectedPeripheral = peripheral
        peripheral.delegate = self

        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    /// 周邊設備連線成功回呼，觸發服務探索流程
    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        let deviceName = peripheral.name ?? targetDeviceName
        print("[Bluetooth] BLE Link 建立成功: \(deviceName)")

        resetConnectionState()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    /// 周邊設備連線失敗回呼，清理狀態並通知委派對象
    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        print("[Bluetooth] 連線失敗: \(error?.localizedDescription ?? "未知原因")")
        connectedPeripheral = nil
        resetConnectionState()
        delegate?.bluetoothManager(self, didUpdateConnection: false)
    }

    /// 周邊設備連線中斷回呼，清理狀態並通知委派對象
    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        print("[Bluetooth] 連線中斷: \(peripheral.name ?? targetDeviceName)")

        connectedPeripheral = nil
        resetConnectionState()
        delegate?.bluetoothManager(self, didUpdateConnection: false)
    }
}

extension BluetoothManager: CBPeripheralDelegate {

    /// 探索 GATT 服務回呼，尋找匹配之目標服務並探索其特徵值
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let error = error {
            print("[Bluetooth] Service 探索失敗: \(error.localizedDescription)")
            delegate?.bluetoothManager(self, didUpdateConnection: false)
            return
        }

        guard let services = peripheral.services else {
            print("[Bluetooth] 找不到 Service")
            delegate?.bluetoothManager(self, didUpdateConnection: false)
            return
        }

        guard let service = services.first(where: { $0.uuid == serviceUUID }) else {
            print("[Bluetooth] 找不到目標 Service: \(serviceUUID.uuidString)")
            delegate?.bluetoothManager(self, didUpdateConnection: false)
            return
        }

        print("[Bluetooth] 找到目標 Service: \(service.uuid.uuidString)")
        peripheral.discoverCharacteristics([ioCharacteristicUUID], for: service)
    }

    /// 探索特徵值回呼，驗證讀寫與通知屬性並自動訂閱 Notify
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            print("[Bluetooth] Characteristic 探索失敗: \(error.localizedDescription)")
            delegate?.bluetoothManager(self, didUpdateConnection: false)
            return
        }

        guard let characteristics = service.characteristics else {
            print("[Bluetooth] 找不到 Characteristic")
            delegate?.bluetoothManager(self, didUpdateConnection: false)
            return
        }

        guard let characteristic = characteristics.first(where: {
            $0.uuid == ioCharacteristicUUID
        }) else {
            print("[Bluetooth] ERROR: 找不到 9001 Characteristic")
            delegate?.bluetoothManager(self, didUpdateConnection: false)
            return
        }

        print(
            "[Bluetooth] 發現 Characteristic: " +
            "\(characteristic.uuid.uuidString), properties=\(characteristic.properties)"
        )

        ioCharacteristic = characteristic
        writeReady = characteristic.properties.contains(.write)
            || characteristic.properties.contains(.writeWithoutResponse)

        if !writeReady {
            print("[Bluetooth] ERROR: 9001 不支援 Write")
        } else {
            print("[Bluetooth] 9001 Write 已就緒")
        }

        if characteristic.properties.contains(.notify) {
            print("[Bluetooth] 訂閱數據特徵值 Notify: \(characteristic.uuid.uuidString)")
            peripheral.setNotifyValue(true, for: characteristic)
        } else {
            notifyReady = false
            print("[Bluetooth] ERROR: 9001 不支援 Notify")
            updateReadyState()
        }
    }

    /// 特徵值通知訂閱狀態更新回呼
    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == ioCharacteristicUUID else {
            return
        }

        if let error = error {
            notifyReady = false
            print("[Bluetooth] Notify 訂閱失敗: \(error.localizedDescription)")
            updateReadyState()
            return
        }

        notifyReady = characteristic.isNotifying
        print("[Bluetooth] Notify 狀態: \(characteristic.isNotifying)")
        updateReadyState()
    }

    /// 接收周邊設備傳輸之二進位數據更新（包含 IMU 取樣點與電池狀態），解析後派送至委派對象
    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("[Bluetooth] BLE Notify 接收失敗: \(error.localizedDescription)")
            return
        }

        guard characteristic.uuid == ioCharacteristicUUID else {
            return
        }

        guard let data = characteristic.value, !data.isEmpty else {
            return
        }

        let type = data[0]

        switch type {
        case TremorDataPoint.bleType:
            let points = TremorDataPoint.parseBatch(from: data)

            guard !points.isEmpty else {
                print(
                    "[Bluetooth] IMU 封包格式錯誤：收到 \(data.count) bytes，" +
                    "預期 1 + N*16 bytes。"
                )
                return
            }

            delegate?.bluetoothManager(self, didReceivePoints: points)

        case BatteryStatus.bleType:
            guard let battery = BatteryStatus.parse(from: data) else {
                print(
                    "[Bluetooth] Battery 封包格式錯誤：收到 \(data.count) bytes，" +
                    "預期 5 bytes。"
                )
                return
            }

            delegate?.bluetoothManager(self, didUpdateBattery: battery)

        default:
            print(String(format: "[Bluetooth] 未知的 BLE 封包類型: 0x%02X", type))
        }
    }

    /// 特徵值寫入成功或失敗之回呼確認
    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == ioCharacteristicUUID else {
            return
        }

        if let error = error {
            print("[Bluetooth] BLE 寫入失敗: \(error.localizedDescription)")
            return
        }

        print("[Bluetooth] BLE 寫入成功: \(characteristic.uuid.uuidString)")

        if let command = lastSentCommand {
            print(
                String(
                    format: "[Bluetooth] Last command = %02X %02X %02X",
                    command.commandId,
                    UInt8((command.value >> 8) & 0xFF),
                    UInt8(command.value & 0xFF)
                )
            )
        }
    }
}
