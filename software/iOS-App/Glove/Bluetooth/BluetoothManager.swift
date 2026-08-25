import CoreBluetooth
import Foundation

/// 藍牙連線與資料接收
public protocol BluetoothManagerDelegate: AnyObject {
    
    /// 接收到解析後之震顫資料點陣列時觸發
    /// - Parameters:
    ///   - manager: 發送事件之 BluetoothManager 實例
    ///   - points: 解析後之 TremorDataPoint 陣列
    func bluetoothManager(
        _ manager: BluetoothManager,
        didReceivePoints points: [TremorDataPoint]
    )

    /// 藍牙中心裝置狀態更新時觸發
    /// - Parameters:
    ///   - manager: 發送事件之 BluetoothManager 實例
    ///   - state: 最新之 CBManagerState 狀態
    func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateState state: CBManagerState
    )

    /// 藍牙周邊裝置連線狀態變更時觸發
    /// - Parameters:
    ///   - manager: 發送事件之 BluetoothManager 實例
    ///   - isConnected: 是否已成功連線
    func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateConnection isConnected: Bool
    )
}

/// 負責處理感測手套之藍牙低功耗 (BLE) 掃描、連線、特徵值訂閱與原始資料分派之管理類別
public class BluetoothManager: NSObject {
    /// 藍牙中心管理員實例
    private var centralManager: CBCentralManager!

    /// 當前已連線之周邊裝置實例
    private var connectedPeripheral: CBPeripheral?

    /// 震顫感測手套主要服務 UUID
    private let serviceUUID = CBUUID(
        string: "12345678-1234-1234-1234-123456789000"
    )

    /// 震顫資料特徵值 UUID
    private let dataCharUUID = CBUUID(
        string: "12345678-1234-1234-1234-123456789001"
    )

    /// 藍牙事件委派對象
    public weak var delegate: BluetoothManagerDelegate?

    /// 初始化藍牙管理員，並指定代理與主執行緒佇列
    public override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    /// 開始掃描具備目標服務 UUID 之周邊裝置
    public func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: nil
        )
    }

    /// 停止藍牙掃描
    public func stopScanning() {
        centralManager.stopScan()
    }

    /// 中斷當前周邊裝置連線
    public func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    /// 監聽中心設備藍牙硬體狀態變更
    /// - Parameter central: 觸發事件之中心管理員實例
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        delegate?.bluetoothManager(self, didUpdateState: central.state)
        if central.state == .poweredOn {
            startScanning()
        }
    }

    /// 掃描發現目標周邊設備時建立連線
    /// - Parameters:
    ///   - central: 執行掃描之中心管理員實例
    ///   - peripheral: 掃描發現之周邊設備實例
    ///   - advertisementData: 廣播封包資料字典
    ///   - RSSI: 訊號強度指標數值 (dBm)
    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        connectedPeripheral = peripheral
        connectedPeripheral?.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    /// 成功與周邊設備建立連線後開始搜尋指定服務
    /// - Parameters:
    ///   - central: 中心管理員實例
    ///   - peripheral: 已連線之周邊設備實例
    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        delegate?.bluetoothManager(self, didUpdateConnection: true)
        peripheral.discoverServices([serviceUUID])
    }

    /// 周邊設備連線中斷時清理狀態並重新啟動掃描
    /// - Parameters:
    ///   - central: 中心管理員實例
    ///   - peripheral: 中斷連線之周邊設備實例
    ///   - error: 中斷原因錯誤物件（若正常斷線則為 nil）
    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        connectedPeripheral = nil
        delegate?.bluetoothManager(self, didUpdateConnection: false)
        startScanning()
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    /// 發現周邊設備所提供之服務後搜尋特徵值
    /// - Parameters:
    ///   - peripheral: 周邊設備實例
    ///   - error: 搜尋服務過程之錯誤物件（若成功則為 nil）
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([dataCharUUID], for: service)
        }
    }

    /// 發現指定特徵值後啟用即時數據通知 (Notify)
    /// - Parameters:
    ///   - peripheral: 周邊設備實例
    ///   - service: 特徵值所屬之服務實例
    ///   - error: 搜尋特徵值過程之錯誤物件（若成功則為 nil）
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics
        where characteristic.uuid == dataCharUUID {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    /// 接收周邊設備發送之特徵值二進位數據並進行批次解析分派
    /// - Parameters:
    ///   - peripheral: 發送數據之周邊設備實例
    ///   - characteristic: 數據更新之特徵值實例
    ///   - error: 讀取或通知過程之錯誤物件（若正常則為 nil）
    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }

        let points = TremorDataPoint.parseBatch(from: data)
        if !points.isEmpty {
            delegate?.bluetoothManager(self, didReceivePoints: points)
        }
    }
}
