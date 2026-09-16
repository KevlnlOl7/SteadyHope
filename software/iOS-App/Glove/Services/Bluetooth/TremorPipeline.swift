import CoreBluetooth
import Foundation

/// 負責處理即時感測器數據串流緩衝、滑動視窗特徵分析、時序錨點對齊與藍牙委派事件轉發之管線管理類別
final class TremorPipeline {

    /// 手機與裝置時序錨點，用於對齊硬體毫秒時鐘與絕對 UTC 時間
    struct SessionAnchor: Sendable {
        let sessionId: String
        let sessionStartUtcMs: Int64
        let sessionStartSampleTickMs: UInt32
        let timezoneIdentifier: String

        /// 初始化時序錨點
        /// - Parameters:
        ///   - sessionId: 工作階段唯一識別碼，預設自動生成 UUID
        ///   - firstValidTick: 第一筆有效資料之硬體毫秒時鐘
        init(sessionId: String = UUID().uuidString, firstValidTick: UInt32) {
            self.sessionId = sessionId
            self.sessionStartUtcMs = Int64(Date().timeIntervalSince1970 * 1000.0)
            self.sessionStartSampleTickMs = firstValidTick
            self.timezoneIdentifier = TimeZone.current.identifier
        }

        /// 根據硬體採樣毫秒時鐘計算對應之絕對 Date 實體
        /// - Parameter tick: 硬體採樣毫秒時鐘
        /// - Returns: 對應的絕對時間
        func date(for tick: UInt32) -> Date {
            let delta: UInt64
            if tick >= sessionStartSampleTickMs {
                delta = UInt64(tick - sessionStartSampleTickMs)
            } else {
                delta = UInt64(UInt32.max) - UInt64(sessionStartSampleTickMs) + UInt64(tick) + 1
            }
            let utcMs = sessionStartUtcMs + Int64(delta)
            return Date(timeIntervalSince1970: Double(utcMs) / 1000.0)
        }
    }

    /// 原始感測數據點緩衝陣列
    private var rawBuffer: [TremorDataPoint] = []
    /// 震顫特徵與頻譜分析器實體
    private let analyzer = TremorAnalyzer()

    /// 分析視窗大小（筆數）
    private let windowSize = 400
    /// 每次滑動分析之步進大小（筆數）
    private let strideSize = 50
    /// 自上次分析以來累積的新增資料筆數
    private var accumulatedSinceLastAnalysis = 0
    /// 上一次回報之馬達運轉狀態
    private var lastMotorEnabled: UInt8?

    /// 當前作用中之時序錨點
    private(set) var currentAnchor: SessionAnchor?

    /// 分析結果更新時觸發之閉包
    var onAnalysisUpdated: ((TremorAnalysisResult, [TremorDataPoint]) -> Void)?
    /// 即時分析結果更新時觸發之閉包
    var onLiveAnalysisUpdated: ((TremorAnalysisResult, [TremorDataPoint]) -> Void)?
    /// 批次新原始數據加入時觸發之閉包
    var onNewRawBatchAppended: (([TremorDataPoint]) -> Void)?

    /// 電池狀態更新時觸發之閉包
    var onBatteryUpdated: ((BatteryStatus) -> Void)?
    /// 馬達運轉狀態改變時觸發之閉包
    var onMotorEnabledChanged: ((Bool) -> Void)?
    /// 系統狀態文字改變時觸發之閉包
    var onStatusChanged: ((String) -> Void)?
    /// 藍牙連線硬體狀態改變時觸發之閉包
    var onBluetoothStateChanged: ((CBManagerState) -> Void)?
    /// 藍牙連線中斷狀態改變時觸發之閉包
    var onConnectionChanged: ((Bool) -> Void)?

    /// 發送相對長度微調指令時觸發之閉包
    var onSendLengthAdjustment: ((Int) -> Void)?
    /// 發送手動絕對長度指令時觸發之閉包
    var onSendManualLengthInput: ((Int) -> Void)?

    /// 推入單筆原始感測數據點至緩衝區並視情況觸發滑動視窗分析
    /// - Parameter point: 接收到的 TremorDataPoint 實體
    func pushRawPoint(_ point: TremorDataPoint) {
        var sample = point

        // 收到第一筆有效資料時建立 Session Anchor
        if currentAnchor == nil && point.sensorValid == 1 {
            currentAnchor = SessionAnchor(firstValidTick: point.sampleTickMs)
        }

        if let anchor = currentAnchor {
            sample.recordedAt = anchor.date(for: sample.sampleTickMs)
        } else {
            sample.recordedAt = Date()
        }

        rawBuffer.append(sample)
        accumulatedSinceLastAnalysis += 1

        publishMotorStateIfNeeded(sample.motorEnabled)

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

    /// 批次推入多筆原始感測數據點至緩衝區
    /// - Parameter points: 接收到的 TremorDataPoint 陣列
    func pushRawPoints(_ points: [TremorDataPoint]) {
        for point in points {
            pushRawPoint(point)
        }
    }

    /// 檢查馬達狀態是否有變更，若有則發送狀態通知
    /// - Parameter rawValue: 原始馬達狀態位元組
    private func publishMotorStateIfNeeded(_ rawValue: UInt8) {
        guard rawValue == 0 || rawValue == 1 else { return }
        guard lastMotorEnabled != rawValue else { return }
        lastMotorEnabled = rawValue
        onMotorEnabledChanged?(rawValue == 1)
    }

    /// 發送相對長度調整命令至硬體
    /// - Parameter offsetMm: 偏移量（單位：毫米 mm）
    public func sendLengthAdjustment(_ offsetMm: Int) {
        onSendLengthAdjustment?(offsetMm)
    }

    /// 發送手動絕對長度調整命令至硬體
    /// - Parameter signedMm: 帶正負號之目標長度（單位：毫米 mm）
    public func sendManualLengthInput(_ signedMm: Int) {
        onSendManualLengthInput?(signedMm)
    }

    /// 清空內部分析視窗緩衝區與步進計數
    public func resetBuffer() {
        rawBuffer.removeAll()
        accumulatedSinceLastAnalysis = 0
        lastMotorEnabled = nil
        onStatusChanged?("資料累積中 (0/\(windowSize))")
    }

    /// 藍牙斷線或重開機時，清空分析視窗並重設 Session Anchor
    public func resetPipeline() {
        resetBuffer()
        currentAnchor = nil
    }
}

extension TremorPipeline: BluetoothManagerDelegate {
    /// 接收藍牙端電池狀態更新委派事件
    /// - Parameters:
    ///   - manager: 藍牙管理器實體
    ///   - battery: 電池狀態資料物件
    public func bluetoothManager(_ manager: BluetoothManager, didUpdateBattery battery: BatteryStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.onBatteryUpdated?(battery)
        }
    }

    /// 接收藍牙端傳入之原始數據點委派事件
    /// - Parameters:
    ///   - manager: 藍牙管理器實體
    ///   - points: 接收到的感測資料點陣列
    public func bluetoothManager(_ manager: BluetoothManager, didReceivePoints points: [TremorDataPoint]) {
        DispatchQueue.main.async { [weak self] in
            self?.pushRawPoints(points)
        }
    }

    /// 監聽系統藍牙晶片狀態改變委派事件
    /// - Parameters:
    ///   - manager: 藍牙管理器實體
    ///   - state: 當前系統藍牙狀態
    public func bluetoothManager(_ manager: BluetoothManager, didUpdateState state: CBManagerState) {
        if state != .poweredOn {
            resetPipeline()
        }
        DispatchQueue.main.async { [weak self] in
            self?.onBluetoothStateChanged?(state)
        }
    }

    /// 監聽手套裝置連線或中斷委派事件
    /// - Parameters:
    ///   - manager: 藍牙管理器實體
    ///   - isConnected: 當前是否已建立連線
    public func bluetoothManager(_ manager: BluetoothManager, didUpdateConnection isConnected: Bool) {
        if !isConnected {
            resetPipeline()
        }
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChanged?(isConnected)
        }
    }
}
