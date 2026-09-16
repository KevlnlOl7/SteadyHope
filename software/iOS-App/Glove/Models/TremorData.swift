import Foundation

/// 藍牙低功耗 (BLE) 感測手套傳輸之單筆震顫原始資料點模型
public struct TremorDataPoint: Sendable {
    /// BLE 封包協定型別識別碼（0x01）
    public static let bleType: UInt8 = 0x01
    /// 單筆原始感測數據佔用之位元組大小（16 位元組）
    public static let sampleSize = 16

    /// 封包傳輸遞增流水號，用於檢查封包連續性與掉包狀況
    public var sequence: UInt32
    /// 硬體內部採樣時鐘時間戳記（單位：毫秒 ms）
    public var sampleTickMs: UInt32
    /// X 軸陀螺儀角速度數值（單位：度/秒 dps）
    public var gyroXDps: Double
    /// Y 軸陀螺儀角速度數值（單位：度/秒 dps）
    public var gyroYDps: Double
    /// Z 軸陀螺儀角速度數值（單位：度/秒 dps）
    public var gyroZDps: Double
    /// 感測器硬體狀態有效旗標（1 為正常，0 為異常或飽和）
    public var sensorValid: UInt8
    /// 震顫抑制馬達當前運轉狀態（1 為啟動介入，0 為關閉待命）
    public var motorEnabled: UInt8
    /// 系統接收或解析時對應之絕對時間戳記
    public var recordedAt: Date?

    /// 初始化單筆震顫原始資料點
    /// - Parameters:
    ///   - sequence: 封包流水號
    ///   - sampleTickMs: 硬體時鐘毫秒數
    ///   - gyroXDps: X 軸角速度 (dps)
    ///   - gyroYDps: Y 軸角速度 (dps)
    ///   - gyroZDps: Z 軸角速度 (dps)
    ///   - sensorValid: 感測器狀態旗標
    ///   - motorEnabled: 馬達狀態旗標
    ///   - recordedAt: 系統絕對時間
    public init(
        sequence: UInt32,
        sampleTickMs: UInt32,
        gyroXDps: Double,
        gyroYDps: Double,
        gyroZDps: Double,
        sensorValid: UInt8,
        motorEnabled: UInt8,
        recordedAt: Date? = nil
    ) {
        self.sequence = sequence
        self.sampleTickMs = sampleTickMs
        self.gyroXDps = gyroXDps
        self.gyroYDps = gyroYDps
        self.gyroZDps = gyroZDps
        self.sensorValid = sensorValid
        self.motorEnabled = motorEnabled
        self.recordedAt = recordedAt
    }

    /// 解析來自 BLE 特徵值之批次二進位原始封包
    /// - Parameter data: 藍牙接收到的原始資料封包
    /// - Returns: 解析完成之 TremorDataPoint 資料點陣列
    public static func parseBatch(from data: Data) -> [TremorDataPoint] {
        guard data.count >= 1 + sampleSize else { return [] }
        guard data[0] == bleType else { return [] }

        let payloadCount = data.count - 1
        guard payloadCount % sampleSize == 0 else { return [] }

        let sampleCount = payloadCount / sampleSize
        guard sampleCount > 0 else { return [] }

        var results: [TremorDataPoint] = []
        results.reserveCapacity(sampleCount)

        for i in 0..<sampleCount {
            let offset = 1 + i * sampleSize

            let sequence = readUInt32LE(data, at: offset + 0)
            let tick = readUInt32LE(data, at: offset + 4)
            let gxRaw = readInt16LE(data, at: offset + 8)
            let gyRaw = readInt16LE(data, at: offset + 10)
            let gzRaw = readInt16LE(data, at: offset + 12)
            let valid = data[offset + 14]
            let motor = data[offset + 15]

            results.append(
                TremorDataPoint(
                    sequence: sequence,
                    sampleTickMs: tick,
                    gyroXDps: Double(gxRaw) / 16.0,
                    gyroYDps: Double(gyRaw) / 16.0,
                    gyroZDps: Double(gzRaw) / 16.0,
                    sensorValid: valid,
                    motorEnabled: motor
                )
            )
        }

        return results
    }

    /// 從二進位資料指定位移處依 Little Endian 格式讀取 16 位元無號整數 (UInt16)
    /// - Parameters:
    ///   - data: 原始二進位資料
    ///   - offset: 讀取之起始位移索引
    /// - Returns: 組合完成之 UInt16 數值
    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1]) << 8
        return b0 | b1
    }

    /// 從二進位資料指定位移處依 Little Endian 格式讀取 16 位元有號整數 (Int16)
    /// - Parameters:
    ///   - data: 原始二進位資料
    ///   - offset: 讀取之起始位移索引
    /// - Returns: 轉換完成之 Int16 數值
    private static func readInt16LE(_ data: Data, at offset: Int) -> Int16 {
        return Int16(bitPattern: readUInt16LE(data, at: offset))
    }

    /// 從二進位資料指定位移處依 Little Endian 格式讀取 32 位元無號整數 (UInt32)
    /// - Parameters:
    ///   - data: 原始二進位資料
    ///   - offset: 讀取之起始位移索引
    /// - Returns: 組合完成之 UInt32 數值
    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}

/// 震顫訊號數位訊號處理與頻譜分析判定結果資料模型
public struct TremorAnalysisResult: Sendable {
    /// 訊號資料品質是否有效且符合運算標準
    public var dataValid: Bool
    /// 主頻率計算結果是否具備足夠顯著性與可信度
    public var frequencyReliable: Bool
    /// 檢測出之主要震顫頻率數值（單位：Hz），若無法可靠判定則為 nil
    public var dominantFrequencyHz: Double?
    /// 震顫分析頻帶內之震顫強度均方根值（單位：度/秒 dps）
    public var tremorStrengthRmsDps: Double
    /// 全頻帶三軸向量合成之均方根值（單位：度/秒 dps）
    public var vectorRmsDps: Double
    /// 典型震顫頻帶能量佔全頻譜能量之比例
    public var tremorBandFraction: Double
    /// 頻譜主峰值之能量集中度指標
    public var peakConcentration: Double
    /// 離散傅立葉轉換頻譜中最大能量候選頻點索引值
    public var candidateBin: Int?

    /// 初始化震顫訊號演算法分析判定結果
    /// - Parameters:
    ///   - dataValid: 資料是否有效
    ///   - frequencyReliable: 頻率是否可信
    ///   - dominantFrequencyHz: 主頻率數值 (Hz)
    ///   - tremorStrengthRmsDps: 震顫強度 RMS (dps)
    ///   - vectorRmsDps: 全頻帶向量 RMS (dps)
    ///   - tremorBandFraction: 震顫頻帶能量佔比
    ///   - peakConcentration: 峰值能量集中度
    ///   - candidateBin: 最大候選頻點索引
    public init(
        dataValid: Bool,
        frequencyReliable: Bool,
        dominantFrequencyHz: Double? = nil,
        tremorStrengthRmsDps: Double,
        vectorRmsDps: Double = 0.0,
        tremorBandFraction: Double = 0.0,
        peakConcentration: Double = 0.0,
        candidateBin: Int? = nil
    ) {
        self.dataValid = dataValid
        self.frequencyReliable = frequencyReliable
        self.dominantFrequencyHz = dominantFrequencyHz
        self.tremorStrengthRmsDps = tremorStrengthRmsDps
        self.vectorRmsDps = vectorRmsDps
        self.tremorBandFraction = tremorBandFraction
        self.peakConcentration = peakConcentration
        self.candidateBin = candidateBin
    }
}
