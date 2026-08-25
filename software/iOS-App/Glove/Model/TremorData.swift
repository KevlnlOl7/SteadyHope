import Foundation

/// 藍牙低功耗 (BLE) 感測手套傳輸之單筆震顫原始資料點
public struct TremorDataPoint {
    
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

    /// 解析硬體端傳輸之二進位 Data 封包（支援單筆 16 Bytes 或多筆批次傳輸）
    /// - Parameter data: 二進位封包資料（長度須為 16 Bytes 之整數倍數）
    /// - Returns: 解析後之 TremorDataPoint 陣列
    public static func parseBatch(from data: Data) -> [TremorDataPoint] {
        let sampleSize = 16
        guard data.count % sampleSize == 0 && !data.isEmpty else { return [] }

        var results: [TremorDataPoint] = []
        let count = data.count / sampleSize

        data.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }

            for i in 0..<count {
                let offset = i * sampleSize
                let seq = baseAddress.load(
                    fromByteOffset: offset + 0,
                    as: UInt32.self
                ).littleEndian
                let tick = baseAddress.load(
                    fromByteOffset: offset + 4,
                    as: UInt32.self
                ).littleEndian
                let gxRaw = baseAddress.load(
                    fromByteOffset: offset + 8,
                    as: Int16.self
                ).littleEndian
                let gyRaw = baseAddress.load(
                    fromByteOffset: offset + 10,
                    as: Int16.self
                ).littleEndian
                let gzRaw = baseAddress.load(
                    fromByteOffset: offset + 12,
                    as: Int16.self
                ).littleEndian
                let valid = baseAddress.load(
                    fromByteOffset: offset + 14,
                    as: UInt8.self
                )
                let motor = baseAddress.load(
                    fromByteOffset: offset + 15,
                    as: UInt8.self
                )

                let point = TremorDataPoint(
                    sequence: seq,
                    sampleTickMs: tick,
                    // 硬體規範：原始感測數值除以 16 轉換為實際角速度 (deg/s)
                    gyroXDps: Double(gxRaw) / 16.0,
                    gyroYDps: Double(gyRaw) / 16.0,
                    gyroZDps: Double(gzRaw) / 16.0,
                    sensorValid: valid,
                    motorEnabled: motor
                )
                results.append(point)
            }
        }
        return results
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
