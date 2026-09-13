import Combine
import CoreBluetooth
import Foundation
import SwiftUI

@MainActor
final class BluetoothViewModel: NSObject, ObservableObject {

    static let shared = BluetoothViewModel()

    /// 藍牙硬體連線與權限狀態
    @Published var isConnected: Bool = false
    @Published var isScanning: Bool = false
    @Published var isBluetoothPoweredOn: Bool = true
    @Published var isBluetoothUnauthorized: Bool = false
    @Published var statusMessage: String = "未連線"

    /// 裝置電量與硬體致動狀態
    @Published var batteryLevel: Int = 0
    @Published var isMotorEnabled: Bool = false
    @Published var isAutomaticSuppressionEnabled = false

    /// 即時震顫分析數據
    @Published var dominantFrequencyText: String = "--"
    @Published var tremorStrengthRms: Double = 0.0

    /// 長度調整控制與常數設定
    @Published var initialCableLengthMm = 400.0
    @Published var initialTakeUpCm = 0.0
    @Published var lengthOffsetMm: Double = 0.0
    static let initialCableHomeMm = 400.0
    static let initialTakeUpDefaultCm = 0.0
    static let initialTakeUpMinCm = 0.0
    static let initialTakeUpMaxCm = 14.0
    static let initialCableLengthDefaultMm = initialCableHomeMm
    static let initialCableLengthMinMm = initialCableHomeMm - (initialTakeUpMaxCm * 10.0)
    static let initialCableLengthMaxMm = initialCableHomeMm
    static let maxLengthAdjustmentMm: Int = 50
    static let maxLengthAdjustmentCm: Double = 5.0

    /// 資料管線、核心管理器與非同步工作實體
    let pipeline = TremorPipeline()
    let bluetoothManager = BluetoothManager()
    private var scanTimeoutTask: Task<Void, Never>?

    /// 私有化建構子，配置分析管線回呼並自動評估藍牙狀態
    private override init() {
        super.init()

        // 綁定資料中心分析管線
        DataViewModel.shared.bindPipeline(pipeline)

        // 指定底層藍牙事件委派
        bluetoothManager.delegate = self

        // 監聽管線發出之相對長度調整命令並轉發至硬體
        pipeline.onSendLengthAdjustment = { [weak self] offset in
            self?.bluetoothManager.sendLengthAdjustment(offset)
        }

        // 監聽管線發出之手動絕對長度命令並轉發至硬體
        pipeline.onSendManualLengthInput = { [weak self] offset in
            self?.bluetoothManager.sendManualLengthInput(offset)
        }

        setupPipelineCallbacks()

        // 若藍牙已啟用且尚未連線，則自動啟動掃描
        if bluetoothManager.isBluetoothEnabled && !isConnected {
            startScan()
        }
    }

    /// 設定分析管線與 UI 狀態連動之即時回呼機制
    private func setupPipelineCallbacks() {
        pipeline.onLiveAnalysisUpdated = { [weak self] result, points in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let lastPoint = points.last {
                    self.isMotorEnabled = lastPoint.motorEnabled == 1
                }

                if result.dataValid {
                    self.tremorStrengthRms = result.tremorStrengthRmsDps

                    if result.frequencyReliable, let frequency = result.dominantFrequencyHz {
                        self.dominantFrequencyText = String(format: "%.2f Hz", frequency)
                    } else {
                        self.dominantFrequencyText = "--"
                    }
                } else {
                    self.dominantFrequencyText = "--"
                    self.tremorStrengthRms = 0.0
                }
            }
        }

        pipeline.onMotorEnabledChanged = { [weak self] enabled in
            Task { @MainActor [weak self] in
                self?.isMotorEnabled = enabled
            }
        }
    }

    /// 啟動藍牙搜尋與配對手套裝置
    func startScan() {
        if bluetoothManager.isBluetoothUnauthorized {
            isBluetoothUnauthorized = true
            isBluetoothPoweredOn = false
            statusMessage = "請先允許藍牙權限"
            openSettings()
            return
        }

        guard bluetoothManager.isBluetoothEnabled else {
            isBluetoothPoweredOn = false
            isBluetoothUnauthorized = false
            isConnected = false
            isScanning = false
            statusMessage = "手機藍牙未開啟"
            pipeline.resetPipeline()
            bluetoothManager.triggerSystemPowerAlert()
            return
        }

        guard !isConnected else {
            statusMessage = "手套已連線"
            return
        }

        AppLog.debug("啟動掃描...")
        isBluetoothPoweredOn = true
        isBluetoothUnauthorized = false
        isScanning = true
        statusMessage = "搜尋手套中..."

        bluetoothManager.startScanning()

        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)

            guard let self, !Task.isCancelled else { return }

            if !self.isConnected {
                AppLog.error("掃描逾時未連線。")
                self.isScanning = false
                self.statusMessage = "搜尋失敗，請確認手套已開機"
                self.bluetoothManager.stopScanning()
            }
        }
    }

    /// 中斷當前藍牙連線並重設相關運作狀態
    func disconnect() {
        scanTimeoutTask?.cancel()
        isScanning = false
        isMotorEnabled = false
        isAutomaticSuppressionEnabled = false
        isConnected = false
        statusMessage = "未連線"

        pipeline.resetPipeline()
        DataViewModel.shared.currentSessionId = UUID().uuidString

        bluetoothManager.disconnect()
    }

    /// 開啟系統設定頁面引導使用者開啟藍牙權限
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    /// 提交滑桿所選取之長度微調相對命令至硬體端，送出後自動將滑桿數值歸零
    func commitSliderLengthAdjustment() {
        guard isConnected else {
            AppLog.error("略過 Slider 指令：手套尚未連線完成。")
            lengthOffsetMm = 0.0
            return
        }

        let clampedCm = min(
            max(lengthOffsetMm, -Self.maxLengthAdjustmentCm),
            Self.maxLengthAdjustmentCm
        )
        let offsetMm = Int(round(clampedCm * 10.0))

        if offsetMm != 0 {
            bluetoothManager.sendLengthAdjustment(offsetMm)
        }

        // 送出後立即歸零，避免下一次調整時數值重複累加
        lengthOffsetMm = 0.0
    }

    /// 提交手動文字輸入之相對長度調整量（單位：公分），轉換為整數公釐後透過藍牙發送
    /// - Parameter offsetCm: 使用者輸入之位移量（公分）
    func sendManualLengthInputCm(_ offsetCm: Double) {
        guard isConnected else {
            AppLog.error("略過手動指令：手套尚未連線完成。")
            return
        }

        let clampedCm = min(
            max(offsetCm, -Self.maxLengthAdjustmentCm),
            Self.maxLengthAdjustmentCm
        )
        let offsetMm = Int(round(clampedCm * 10.0))

        if offsetMm != 0 {
            bluetoothManager.sendManualLengthInput(offsetMm)
        }
    }

    /// 設定初次穿戴時的初始預拉緊長度基準
    /// - Parameter takeUpCm: 預收緊長度（單位：公分 cm）
    func sendInitialTakeUpCm(_ takeUpCm: Double) {
        guard isConnected else {
            AppLog.error("略過初始收緊指令：手套尚未連線完成。")
            return
        }

        let clampedCm = min(
            max(takeUpCm, Self.initialTakeUpMinCm),
            Self.initialTakeUpMaxCm
        )
        let roundedTakeUpMm = Int(round(clampedCm * 10.0))
        let baselineMm = Int(Self.initialCableHomeMm) - roundedTakeUpMm

        initialTakeUpCm = Double(roundedTakeUpMm) / 10.0
        initialCableLengthMm = Double(baselineMm)

        bluetoothManager.sendBaselineLength(magnitudeMm: baselineMm)
    }

    /// 依據目標纜繩絕對長度發送初始基準校正設定
    /// - Parameter lengthMm: 目標纜繩長度（單位：毫米 mm）
    func sendInitialCableLengthMm(_ lengthMm: Double) {
        let clamped = min(
            max(lengthMm, Self.initialCableLengthMinMm),
            Self.initialCableLengthMaxMm
        )
        let takeUpCm = (Self.initialCableHomeMm - clamped) / 10.0
        sendInitialTakeUpCm(takeUpCm)
    }

    /// 設定智慧手套是否開啟全自動即時震顫抑制模式
    /// - Parameter enabled: true 為開啟自動抑制，false 為關閉
    func setAutomaticSuppression(_ enabled: Bool) {
        guard isConnected else {
            AppLog.error("略過模式切換：手套尚未連線完成。")
            isAutomaticSuppressionEnabled = false
            return
        }

        isAutomaticSuppressionEnabled = enabled
        bluetoothManager.sendAutomaticMode(enabled)
    }
}

extension BluetoothViewModel: BluetoothManagerDelegate {

    /// 接收手套硬體端回傳之電池狀態推播更新
    /// - Parameters:
    ///   - manager: 發送回呼之藍牙管理器實體
    ///   - battery: 包含電量百分比之 BatteryStatus 物件
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateBattery battery: BatteryStatus
    ) {
        Task { @MainActor in
            self.batteryLevel = Int(battery.percent)
        }
    }

    /// 接收手套硬體端連續串流傳入之原始三軸震顫資料點
    /// - Parameters:
    ///   - manager: 發送回呼之藍牙管理器實體
    ///   - points: 最新解析出之 TremorDataPoint 感測訊號陣列
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didReceivePoints points: [TremorDataPoint]
    ) {
        if !isConnected {
            scanTimeoutTask?.cancel()
            isConnected = true
            isScanning = false
            statusMessage = "手套已連線"

            // 初次收到有效數據點時建立全新工作階段識別碼
            DataViewModel.shared.currentSessionId = UUID().uuidString
        }

        pipeline.bluetoothManager(manager, didReceivePoints: points)
    }

    /// 監聽系統底層 CoreBluetooth 狀態改變並同步處理 UI 提示與連線狀態
    /// - Parameters:
    ///   - manager: 發送回呼之藍牙管理器實體
    ///   - state: 系統最新之 CBManagerState 狀態
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateState state: CBManagerState
    ) {
        Task { @MainActor in
            switch state {
            case .poweredOn:
                isBluetoothPoweredOn = true
                isBluetoothUnauthorized = false
                if !isConnected && !isScanning {
                    startScan()
                }

            case .unauthorized:
                isBluetoothPoweredOn = false
                isBluetoothUnauthorized = true
                isConnected = false
                isScanning = false
                statusMessage = "未取得藍牙權限"
                scanTimeoutTask?.cancel()
                pipeline.resetPipeline()
                DataViewModel.shared.currentSessionId = UUID().uuidString

            case .poweredOff:
                isBluetoothPoweredOn = false
                isBluetoothUnauthorized = false
                isConnected = false
                isScanning = false
                statusMessage = "手機藍牙未開啟"
                scanTimeoutTask?.cancel()
                pipeline.resetPipeline()
                DataViewModel.shared.currentSessionId = UUID().uuidString

            default:
                isBluetoothPoweredOn = false
                isConnected = false
                isScanning = false
                statusMessage = "藍牙準備中..."
                pipeline.resetPipeline()
                DataViewModel.shared.currentSessionId = UUID().uuidString
            }
        }
    }

    /// 監聽手套藍牙連線或中斷連線事件回呼
    /// - Parameters:
    ///   - manager: 發送回呼之藍牙管理器實體
    ///   - connected: 裝置當前是否處於連線狀態
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateConnection connected: Bool
    ) {
        Task { @MainActor in
            scanTimeoutTask?.cancel()
            isConnected = connected
            isScanning = false
            statusMessage = connected ? "手套已連線" : "已斷開連線"

            if !connected {
                dominantFrequencyText = "--"
                tremorStrengthRms = 0.0
                isMotorEnabled = false
                isAutomaticSuppressionEnabled = false

                // 斷線時重設管線以防歷史資料污染下一個工作階段
                pipeline.resetPipeline()
                DataViewModel.shared.currentSessionId = UUID().uuidString
            } else {
                // 重新連線時建立全新工作階段識別碼並恢復預設設定
                DataViewModel.shared.currentSessionId = UUID().uuidString
                isAutomaticSuppressionEnabled = false
                bluetoothManager.sendAutomaticMode(false)
            }

            lengthOffsetMm = 0.0
        }
    }
}
