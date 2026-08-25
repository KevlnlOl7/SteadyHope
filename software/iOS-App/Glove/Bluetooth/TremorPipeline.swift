import CoreBluetooth
import Foundation

/// 負責串接藍牙即時數據串流、滑動視窗緩衝區管理與定時觸發震顫分析之處理管線
public class TremorPipeline {
    
    /// 藍牙連線與通訊管理員實例
    public let bluetoothManager = BluetoothManager()

    /// 震顫訊號演算法分析器實例
    private let analyzer = TremorAnalyzer()

    /// 訊號取樣滑動視窗緩衝區（固定上限為 400 筆，對應 4 秒資料）
    private var buffer: [TremorDataPoint] = []

    /// 新進取樣點累計計數器（每累積 50 筆觸發一次分析）
    private var newSampleCounter = 0

    /// 視窗長度常數（400 筆資料點）
    private let windowSize = 400

    /// 分析觸發步長常數（50 筆資料點，約 0.5 秒）
    private let stepSize = 50

    /// 震顫分析結果更新回呼閉包
    public var onAnalysisUpdated: ((TremorAnalysisResult) -> Void)?

    /// 藍牙連線狀態變更回呼閉包
    public var onConnectionChanged: ((Bool) -> Void)?

    /// 初始化震顫處理管線，並設定自身為藍牙事件委派對象
    public init() {
        bluetoothManager.delegate = self
    }
}

// MARK: - BluetoothManagerDelegate

extension TremorPipeline: BluetoothManagerDelegate {
    /// 接收藍牙傳入之批次震顫資料點，維護滑動視窗並於每滿指定步長時觸發演算法分析
    /// - Parameters:
    ///   - manager: 發送事件之 BluetoothManager 實例
    ///   - points: 剛接收並解析完成之 TremorDataPoint 陣列
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didReceivePoints points: [TremorDataPoint]
    ) {
        buffer.append(contentsOf: points)
        newSampleCounter += points.count

        if buffer.count > windowSize {
            buffer.removeFirst(buffer.count - windowSize)
        }

        guard buffer.count == windowSize else { return }

        // 每累積 50 筆新資料（0.5 秒）觸發一次演算法計算
        if newSampleCounter >= stepSize {
            newSampleCounter = 0

            let result = analyzer.analyze(data: buffer)
            DispatchQueue.main.async { [weak self] in
                self?.onAnalysisUpdated?(result)
            }
        }
    }

    /// 監聽藍牙硬體狀態變更，若藍牙非可用狀態則重置緩衝區
    /// - Parameters:
    ///   - manager: 發送事件之 BluetoothManager 實例
    ///   - state: 最新之 CBManagerState 狀態
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateState state: CBManagerState
    ) {
        if state != .poweredOn {
            buffer.removeAll()
            newSampleCounter = 0
        }
    }

    /// 監聽藍牙連線狀態變更，若斷線則清空緩衝區並派發狀態更新事件
    /// - Parameters:
    ///   - manager: 發送事件之 BluetoothManager 實例
    ///   - isConnected: 是否已成功連線
    public func bluetoothManager(
        _ manager: BluetoothManager,
        didUpdateConnection isConnected: Bool
    ) {
        if !isConnected {
            buffer.removeAll()
            newSampleCounter = 0
        }
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChanged?(isConnected)
        }
    }
}
