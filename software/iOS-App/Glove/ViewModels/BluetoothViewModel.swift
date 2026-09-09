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

    /// 即時震顫分析數據
    @Published var dominantFrequencyText: String = "--"
    @Published var tremorStrengthRms: Double = 0.0

    /// 長度調整控制與常數設定（Slider 當次相對調整量，UI 範圍為 -5 至 +5 cm，送出前轉為 -50 至 +50 mm）
    @Published var lengthOffsetMm: Double = 0.0
    static let maxLengthAdjustmentMm: Int = 50
    static let maxLengthAdjustmentCm: Double = 5.0

    /// 資料管線、核心管理器與非同步工作實體
    let pipeline = TremorPipeline()
    let bluetoothManager = BluetoothManager()
    private var scanTimeoutTask: Task<Void, Never>?

    /// 私有初始化建構子，限制僅能透過單例模式存取
    private override init() {
        super.init()
        DataViewModel.shared.bindPipeline(self.pipeline)
        bluetoothManager.delegate = self

        // 綁定 Slider 相對長度微調回呼（指令標頭：0x02 / 0x03）
        pipeline.onSendLengthAdjustment = { [weak self] offset in
            self?.bluetoothManager.sendLengthAdjustment(offset)
        }

        // 綁定手動輸入相對長度微調回呼（指令標頭：0x04 / 0x05）
        pipeline.onSendManualLengthInput = { [weak self] offset in
            self?.bluetoothManager.sendManualLengthInput(offset)
        }

        setupPipelineCallbacks()

        if bluetoothManager.isBluetoothEnabled && !isConnected {
            self.startScan()
        }
    }

    /// 設定震顫訊號管線之各項即時分析與馬達狀態變更回呼函式
    private func setupPipelineCallbacks() {
        pipeline.onLiveAnalysisUpdated = { [weak self] result, points in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let lastPoint = points.last {
                    self.isMotorEnabled = (lastPoint.motorEnabled == 1)
                }

                if result.dataValid {
                    self.tremorStrengthRms = result.tremorStrengthRmsDps
                    if result.frequencyReliable,
                        let freq = result.dominantFrequencyHz
                    {
                        self.dominantFrequencyText = String(
                            format: "%.2f Hz",
                            freq
                        )
                    } else {
                        self.dominantFrequencyText = "--"
                    }
                } else {
                    self.dominantFrequencyText = "資料不足"
                    self.tremorStrengthRms = 0.0
                }
            }
        }

        // 馬達狀態變更時即時同步狀態，無需等待完整分析視窗累積
        pipeline.onMotorEnabledChanged = { [weak self] enabled in
            Task { @MainActor [weak self] in
                self?.isMotorEnabled = enabled
            }
        }
    }

    /// 啟動藍牙裝置掃描，具備權限檢查、開關判定與逾時防呆機制
    func startScan() {
        if bluetoothManager.isBluetoothUnauthorized {
            self.isBluetoothUnauthorized = true
            self.isBluetoothPoweredOn = false
            self.statusMessage = "請先允許藍牙權限"
            self.openSettings()
            return
        }

        guard bluetoothManager.isBluetoothEnabled else {
            self.isBluetoothPoweredOn = false
            self.isBluetoothUnauthorized = false
            self.isConnected = false
            self.isScanning = false
            self.statusMessage = "手機藍牙未開啟"
            bluetoothManager.triggerSystemPowerAlert()
            return
        }

        guard !isConnected else {
            self.statusMessage = "手套已連線"
            return
        }

        AppLog.debug("啟動掃描...")
        self.isBluetoothPoweredOn = true
        self.isBluetoothUnauthorized = false
        self.isScanning = true
        self.statusMessage = "搜尋手套中..."

        bluetoothManager.startScanning()

        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)
            guard let self = self, !Task.isCancelled else { return }

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
        self.isScanning = false
        self.isMotorEnabled = false
        self.isConnected = false
        self.statusMessage = "未連線"
        bluetoothManager.disconnect()
    }

    /// 引導使用者開啟系統設定頁面以調整藍牙權限
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
    }

    /// 提交滑桿選定之相對長度調整量，將公分（cm）轉為公釐（mm）後透過藍牙發送
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
}

extension BluetoothViewModel: BluetoothManagerDelegate {

    /// 接收藍牙手套電量資訊更新之委派方法
    /// - Parameters:
    ///   - manager: 觸發更新之藍牙管理實體
    ///   - battery: 包含電量百分比與充電狀態之結構
    public func bluetoothManager(_ manager: BluetoothManager, didUpdateBattery battery: BatteryStatus) {
        Task { @MainActor in
            self.batteryLevel = Int(battery.percent)
        }
    }

    /// 接收藍牙手套批次震顫取樣點之委派方法
    /// - Parameters:
    ///   - manager: 觸發更新之藍牙管理實體
    ///   - points: 剛解析完成之震顫取樣點陣列
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didReceivePoints points: [TremorDataPoint]
    ) {
        if !self.isConnected {
            Task { @MainActor in
                self.scanTimeoutTask?.cancel()
                self.isConnected = true
                self.isScanning = false
                self.statusMessage = "手套已連線"
            }
        }
        pipeline.bluetoothManager(manager, didReceivePoints: points)
    }

    /// 接收手機系統藍牙硬體狀態變更之委派方法
    /// - Parameters:
    ///   - manager: 觸發更新之藍牙管理實體
    ///   - state: CoreBluetooth 當前狀態列舉值
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateState state: CBManagerState
    ) {
        Task { @MainActor in
            switch state {
            case .poweredOn:
                self.isBluetoothPoweredOn = true
                self.isBluetoothUnauthorized = false
                if !self.isConnected && !self.isScanning {
                    self.startScan()
                }
            case .unauthorized:
                self.isBluetoothPoweredOn = false
                self.isBluetoothUnauthorized = true
                self.isConnected = false
                self.isScanning = false
                self.statusMessage = "未取得藍牙權限"
                self.scanTimeoutTask?.cancel()
            case .poweredOff:
                self.isBluetoothPoweredOn = false
                self.isBluetoothUnauthorized = false
                self.isConnected = false
                self.isScanning = false
                self.statusMessage = "手機藍牙未開啟"
                self.scanTimeoutTask?.cancel()
            default:
                self.isBluetoothPoweredOn = false
                self.isConnected = false
                self.isScanning = false
                self.statusMessage = "藍牙準備中..."
            }
        }
    }

    /// 接收手套連線或斷開連線狀態變更之委派方法
    /// - Parameters:
    ///   - manager: 觸發更新之藍牙管理實體
    ///   - isConnected: 藍牙連線狀態旗標
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateConnection isConnected: Bool
    ) {
        Task { @MainActor in
            self.scanTimeoutTask?.cancel()
            self.isConnected = isConnected
            self.isScanning = false
            self.statusMessage = isConnected ? "手套已連線" : "已斷開連線"

            if !isConnected {
                self.dominantFrequencyText = "--"
                self.tremorStrengthRms = 0.0
                self.isMotorEnabled = false
            }

            self.lengthOffsetMm = 0.0
        }
    }
}
