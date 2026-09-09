import CoreBluetooth
import Foundation

/// 負責串接藍牙即時數據串流、滑動視窗緩衝區管理與定時觸發震顫分析之處理管線
final class TremorPipeline {

    /// 原始取樣緩衝區與演算法分析器
    private var rawBuffer: [TremorDataPoint] = []
    private let analyzer = TremorAnalyzer()

    /// 視窗取樣設定與時序控制常數
    private let windowSize = 400
    private let strideSize = 50
    private var accumulatedSinceLastAnalysis = 0
    private var lastMotorEnabled: UInt8?

    /// 震顫數據分析與原始取樣批次產出回呼閉包
    var onAnalysisUpdated: ((TremorAnalysisResult, [TremorDataPoint]) -> Void)?
    var onLiveAnalysisUpdated: ((TremorAnalysisResult, [TremorDataPoint]) -> Void)?
    var onNewRawBatchAppended: (([TremorDataPoint]) -> Void)?

    /// 硬體狀態、電量與致動回呼閉包
    var onBatteryUpdated: ((BatteryStatus) -> Void)?
    var onMotorEnabledChanged: ((Bool) -> Void)?
    var onStatusChanged: ((String) -> Void)?
    var onBluetoothStateChanged: ((CBManagerState) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    /// 長度調整控制指令回呼閉包（負值縮短，正值加長）
    var onSendLengthAdjustment: ((Int) -> Void)?
    var onSendManualLengthInput: ((Int) -> Void)?

    /// 接收單筆取樣點並推進視窗緩衝區，於累積滿足步進條件時執行頻譜特徵運算
    /// - Parameter point: 剛接收到的震顫取樣數據點
    func pushRawPoint(_ point: TremorDataPoint) {
        rawBuffer.append(point)
        accumulatedSinceLastAnalysis += 1

        publishMotorStateIfNeeded(point.motorEnabled)

        if rawBuffer.count < windowSize {
            onStatusChanged?("資料累積中 (\(rawBuffer.count)/\(windowSize))")
            return
        }

        if accumulatedSinceLastAnalysis >= strideSize {
            onStatusChanged?("資料正常")

            let windowData = Array(rawBuffer.suffix(windowSize))
            let result = analyzer.analyze(data: windowData)
            onAnalysisUpdated?(result, windowData)
            onLiveAnalysisUpdated?(result, windowData)

            let newBatch = Array(rawBuffer.suffix(accumulatedSinceLastAnalysis))
            onNewRawBatchAppended?(newBatch)

            accumulatedSinceLastAnalysis = 0

            if rawBuffer.count > 1000 {
                rawBuffer.removeFirst(rawBuffer.count - windowSize)
            }
        }
    }

    /// 批次接收並處理多筆連續取樣點
    /// - Parameter points: 批次收到的震顫取樣點陣列
    func pushRawPoints(_ points: [TremorDataPoint]) {
        for point in points {
            pushRawPoint(point)
        }
    }

    /// 檢查並於馬達狀態產生實質變更時觸發狀態廣播
    /// - Parameter rawValue: 原始硬體回傳之致動旗標（0 代表停止，1 代表致動）
    private func publishMotorStateIfNeeded(_ rawValue: UInt8) {
        guard rawValue == 0 || rawValue == 1 else {
            AppLog.error("motor_enabled 非 0/1：\(rawValue)")
            return
        }

        guard lastMotorEnabled != rawValue else {
            return
        }

        lastMotorEnabled = rawValue
        onMotorEnabledChanged?(rawValue == 1)
    }

    /// 轉發滑桿微調指令至底層藍牙管理器
    /// - Parameter offsetMm: 相對線長調整量（單位：公釐）
    public func sendLengthAdjustment(_ offsetMm: Int) {
        AppLog.debug("sendLengthAdjustment: \(offsetMm) mm")

        guard let sender = onSendLengthAdjustment else {
            AppLog.error("onSendLengthAdjustment 尚未綁定到 BluetoothManager")
            return
        }

        sender(offsetMm)
    }

    /// 轉發手動數值輸入微調指令至底層藍牙管理器
    /// - Parameter signedMm: 帶正負號之相對位移量（單位：公釐）
    public func sendManualLengthInput(_ signedMm: Int) {
        AppLog.debug("sendManualLengthInput: \(signedMm) mm")

        guard let sender = onSendManualLengthInput else {
            AppLog.error("onSendManualLengthInput 尚未綁定到 BluetoothManager")
            return
        }

        sender(signedMm)
    }

    /// 重設管線內部緩衝區與時序計數狀態
    public func resetBuffer() {
        rawBuffer.removeAll()
        accumulatedSinceLastAnalysis = 0
        lastMotorEnabled = nil
        onStatusChanged?("資料累積中 (0/\(windowSize))")
    }
}

extension TremorPipeline: BluetoothManagerDelegate {

    /// 處理藍牙手套電量資訊更新通知
    /// - Parameters:
    ///   - manager: 藍牙傳輸管理實體
    ///   - battery: 最新接收之電池狀態結構
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateBattery battery: BatteryStatus
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.onBatteryUpdated?(battery)
        }
    }

    /// 處理藍牙手套接收到的原始取樣點批次資料
    /// - Parameters:
    ///   - manager: 藍牙傳輸管理實體
    ///   - points: 解析完成之震顫取樣點集合
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didReceivePoints points: [TremorDataPoint]
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.pushRawPoints(points)
        }
    }

    /// 處理手機系統藍牙硬體狀態變更事件
    /// - Parameters:
    ///   - manager: 藍牙傳輸管理實體
    ///   - state: 最新之 CoreBluetooth 狀態列舉值
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateState state: CBManagerState
    ) {
        if state != .poweredOn {
            resetBuffer()
        }

        DispatchQueue.main.async { [weak self] in
            self?.onBluetoothStateChanged?(state)
        }
    }

    /// 處理藍牙周邊裝置連線與斷線狀態變更事件
    /// - Parameters:
    ///   - manager: 藍牙傳輸管理實體
    ///   - isConnected: 藍牙連線狀態旗標
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateConnection isConnected: Bool
    ) {
        if !isConnected {
            resetBuffer()
        }

        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChanged?(isConnected)
        }
    }
}
