import Foundation

/// 藍牙低功耗 (BLE) 感測手套傳輸之單筆震顫原始資料點
public struct TremorDataPoint {
    
    /// 藍牙封包類型標頭辨識碼 (0x01 代表震顫資料)
    public static let bleType: UInt8 = 0x01

    /// 單筆取樣點資料位元組大小 (固定為 16 位元組)
    public static let sampleSize = 16

    /// 採樣封包序號
    public var sequence: UInt32

    /// 採樣硬體時間戳記 (毫秒)
    public var sampleTickMs: UInt32

    /// X 軸角速度 (deg/s)
    public var gyroXDps: Double

    /// Y 軸角速度 (deg/s)
    public var gyroYDps: Double

    /// Z 軸角速度 (deg/s)
    public var gyroZDps: Double

    /// 感測器狀態有效性旗標 (1 代表有效，0 代表異常)
    public var sensorValid: UInt8

    /// 馬達致動狀態旗標 (1 代表啟動，0 代表關閉)
    public var motorEnabled: UInt8

    /// 初始化震顫原始資料點
    /// - Parameters:
    ///   - sequence: 採樣封包序號
    ///   - sampleTickMs: 採樣硬體時間戳記 (毫秒)
    ///   - gyroXDps: X 軸角速度 (deg/s)
    ///   - gyroYDps: Y 軸角速度 (deg/s)
    ///   - gyroZDps: Z 軸角速度 (deg/s)
    ///   - sensorValid: 感測器狀態有效性旗標
    ///   - motorEnabled: 馬達致動狀態旗標
    public init(
        sequence: UInt32,
        sampleTickMs: UInt32,
        gyroXDps: Double,
        gyroYDps: Double,
        gyroZDps: Double,
        sensorValid: UInt8,
        motorEnabled: UInt8
    ) {
        self.sequence = sequence
        self.sampleTickMs = sampleTickMs
        self.gyroXDps = gyroXDps
        self.gyroYDps = gyroYDps
        self.gyroZDps = gyroZDps
        self.sensorValid = sensorValid
        self.motorEnabled = motorEnabled
    }

    /// 解析 ESP32 傳遞之完整 BLE IMU Notify 批次二進位封包
    /// - Parameter data: 接收到的原始二進位資料 (包含 Byte 0 之型態標頭 0x01)
    /// - Returns: 解析完成之 TremorDataPoint 物件陣列，若長度或格式不合則回傳空陣列
    public static func parseBatch(from data: Data) -> [TremorDataPoint] {
        guard data.count >= 1 + sampleSize else {
            return []
        }

        guard data[0] == bleType else {
            return []
        }

        let payloadCount = data.count - 1
        guard payloadCount % sampleSize == 0 else {
            return []
        }

        let sampleCount = payloadCount / sampleSize
        guard sampleCount > 0 else {
            return []
        }

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
                    // 硬體規範：原始感測數值除以 16 轉換為實際角速度 (deg/s)
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

/// 震顫訊號演算法分析判定結果
public struct TremorAnalysisResult {
    
    /// 輸入資料完整性與時序是否有效
    public var dataValid: Bool

    /// 頻率辨識是否符合防呆門檻且具備可靠度
    public var frequencyReliable: Bool

    /// 辨識出之主要震顫頻率 (Hz)
    public var dominantFrequencyHz: Double?

    /// 典型震顫頻段 (4-6 Hz) 之向量均方根強度 (RMS, deg/s)
    public var tremorStrengthRmsDps: Double

    /// FFT 頻譜中能量最高之候選頻率 Bin 索引
    public var candidateBin: Int?

    /// 初始化震顫演算法分析結果
    /// - Parameters:
    ///   - dataValid: 輸入資料完整性與時序是否有效
    ///   - frequencyReliable: 頻率辨識是否符合防呆門檻且具備可靠度
    ///   - dominantFrequencyHz: 辨識出之主要震顫頻率 (Hz)
    ///   - tremorStrengthRmsDps: 典型震顫頻段之均方根強度 (RMS, deg/s)
    ///   - candidateBin: FFT 頻譜中能量最高之候選頻率 Bin 索引
    public init(
        dataValid: Bool,
        frequencyReliable: Bool,
        dominantFrequencyHz: Double? = nil,
        tremorStrengthRmsDps: Double,
        candidateBin: Int? = nil
    ) {
        self.dataValid = dataValid
        self.frequencyReliable = frequencyReliable
        self.dominantFrequencyHz = dominantFrequencyHz
        self.tremorStrengthRmsDps = tremorStrengthRmsDps
        self.candidateBin = candidateBin
    }
}
