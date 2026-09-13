import Accelerate
import Foundation

/// 負責處理手部震顫訊號分析、PSD 功率譜密度計算
public final class TremorAnalyzer: @unchecked Sendable {
    /// 固定系統取樣頻率（單位：Hz）
    public static let sampleRate: Double = 100.0
    /// 進行離散傅立葉轉換分析之固定採樣視窗大小（筆數）
    public static let windowSize: Int = 400
    /// 傅立葉轉換後之頻率解析度（單位：Hz）
    public static let frequencyResolution: Double = sampleRate / Double(windowSize)

    /// 預先計算並快取之漢寧窗（Hann Window）係數陣列
    private let hannWindow: [Float]
    /// 漢寧窗平方和，用於後續頻譜能量之正規化與補償
    private let windowPower: Float

    /// 初始化震顫分析器，預先計算 Hann Window 係數以減少即時運算開銷
    public init() {
        let n = Self.windowSize
        var window = [Float](repeating: 0.0, count: n)
        var sumSquare: Float = 0.0

        for i in 0..<n {
            let value = Float(0.5 * (1.0 - cos(2.0 * Double.pi * Double(i) / Double(n - 1))))
            window[i] = value
            sumSquare += value * value
        }

        self.hannWindow = window
        self.windowPower = sumSquare
    }

    /// 針對一組 400 筆之原始三軸陀螺儀感測資料進行資料品質驗證與震顫特徵分析
    /// - Parameter data: 包含序列號、時間戳記與三軸角速度之 TremorDataPoint 陣列
    /// - Returns: 分析後之震顫特徵結果 TremorAnalysisResult 物件
    public func analyze(data: [TremorDataPoint]) -> TremorAnalysisResult {
        guard data.count == Self.windowSize else {
            return makeInvalidResult()
        }

        var previousSequence = data[0].sequence
        var previousTick = data[0].sampleTickMs

        for index in 0..<data.count {
            let point = data[index]

            guard point.sensorValid == 1 else {
                return makeInvalidResult()
            }

            guard point.gyroXDps.isFinite,
                  point.gyroYDps.isFinite,
                  point.gyroZDps.isFinite else {
                return makeInvalidResult()
            }

            if index > 0 {
                let expectedSequence = previousSequence &+ 1

                guard point.sequence == expectedSequence else {
                    return makeInvalidResult()
                }

                let tickDelta = point.sampleTickMs &- previousTick

                guard tickDelta >= 8, tickDelta <= 12 else {
                    return makeInvalidResult()
                }
            }

            previousSequence = point.sequence
            previousTick = point.sampleTickMs
        }

        let x = data.map { Float($0.gyroXDps) }
        let y = data.map { Float($0.gyroYDps) }
        let z = data.map { Float($0.gyroZDps) }

        return analyzeSignals(x: x, y: y, z: z)
    }

    /// 針對三軸獨立之 Float 浮點數陣列進行向量合成、功率譜密度轉換與特徵萃取
    /// - Parameters:
    ///   - x: X 軸角速度訊號陣列
    ///   - y: Y 軸角速度訊號陣列
    ///   - z: Z 軸角速度訊號陣列
    /// - Returns: 整合後之震顫特徵結果 TremorAnalysisResult 物件
    public func analyzeSignals(x: [Float], y: [Float], z: [Float]) -> TremorAnalysisResult {
        let n = Self.windowSize

        guard x.count == n, y.count == n, z.count == n else {
            return makeInvalidResult()
        }

        var meanX: Float = 0.0
        var meanY: Float = 0.0
        var meanZ: Float = 0.0

        vDSP_meanv(x, 1, &meanX, vDSP_Length(n))
        vDSP_meanv(y, 1, &meanY, vDSP_Length(n))
        vDSP_meanv(z, 1, &meanZ, vDSP_Length(n))

        var negMeanX = -meanX
        var negMeanY = -meanY
        var negMeanZ = -meanZ

        var centeredX = [Float](repeating: 0.0, count: n)
        var centeredY = [Float](repeating: 0.0, count: n)
        var centeredZ = [Float](repeating: 0.0, count: n)

        vDSP_vsadd(x, 1, &negMeanX, &centeredX, 1, vDSP_Length(n))
        vDSP_vsadd(y, 1, &negMeanY, &centeredY, 1, vDSP_Length(n))
        vDSP_vsadd(z, 1, &negMeanZ, &centeredZ, 1, vDSP_Length(n))

        var sumSquareX: Float = 0.0
        var sumSquareY: Float = 0.0
        var sumSquareZ: Float = 0.0

        vDSP_svesq(centeredX, 1, &sumSquareX, vDSP_Length(n))
        vDSP_svesq(centeredY, 1, &sumSquareY, vDSP_Length(n))
        vDSP_svesq(centeredZ, 1, &sumSquareZ, vDSP_Length(n))

        let vectorRms = Double(sqrt((sumSquareX + sumSquareY + sumSquareZ) / Float(n)))

        let psdX = calculateOneSidedPSD(centered: centeredX)
        let psdY = calculateOneSidedPSD(centered: centeredY)
        let psdZ = calculateOneSidedPSD(centered: centeredZ)

        let numBins = n / 2 + 1
        var psdSum = [Double](repeating: 0.0, count: numBins)

        for k in 0..<numBins {
            psdSum[k] = Double(psdX[k]) + Double(psdY[k]) + Double(psdZ[k])
        }

        let df = Self.frequencyResolution

        var peakIndex = 12
        var maximumPower = -Double.infinity

        for k in 12...28 {
            if psdSum[k] > maximumPower {
                maximumPower = psdSum[k]
                peakIndex = k
            }
        }

        let candidateHz = Double(peakIndex) * df

        var power4To6: Double = 0.0
        for k in 16...24 {
            power4To6 += psdSum[k] * df
        }

        let tremorStrengthRms = sqrt(max(power4To6, 0.0))

        var power0_5To15: Double = 0.0
        for k in 2...60 {
            power0_5To15 += psdSum[k] * df
        }

        var power3To7: Double = 0.0
        for k in 12...28 {
            power3To7 += psdSum[k] * df
        }

        let peakStart = max(0, peakIndex - 2)
        let peakEnd = min(numBins - 1, peakIndex + 2)
        var peakPower: Double = 0.0

        if peakStart <= peakEnd {
            for k in peakStart...peakEnd {
                peakPower += psdSum[k] * df
            }
        }

        let tremorBandFraction = power3To7 / (power0_5To15 + 1e-12)
        let peakConcentration = peakPower / (power3To7 + 1e-12)

        let isReliable = vectorRms >= 0.20 && tremorBandFraction >= 0.30 && peakConcentration >= 0.45

        #if DEBUG
        print("""
        [TremorAnalyzer]
        candidate frequency: \(candidateHz) Hz
        FFT bin: \(peakIndex)
        df: \(df) Hz
        vector RMS: \(vectorRms) deg/s
        4–6 Hz RMS: \(tremorStrengthRms) deg/s
        3–7 / 0.5–15 fraction: \(tremorBandFraction)
        peak concentration: \(peakConcentration)
        frequency reliable: \(isReliable)
        """)

        let xPower = psdX[16...24].reduce(0, +)
        let yPower = psdY[16...24].reduce(0, +)
        let zPower = psdZ[16...24].reduce(0, +)

        print("X 4–6 Hz power: \(Double(xPower) * df)")
        print("Y 4–6 Hz power: \(Double(yPower) * df)")
        print("Z 4–6 Hz power: \(Double(zPower) * df)")
        #endif

        return TremorAnalysisResult(
            dataValid: true,
            frequencyReliable: isReliable,
            dominantFrequencyHz: isReliable ? candidateHz : nil,
            tremorStrengthRmsDps: tremorStrengthRms,
            vectorRmsDps: vectorRms,
            tremorBandFraction: tremorBandFraction,
            peakConcentration: peakConcentration,
            candidateBin: peakIndex
        )
    }

    /// 對去平均後之單軸 Float 訊號進行漢寧窗運算與單側功率譜密度轉換
    /// - Parameter centered: 去平均處理後之角速度資料陣列
    /// - Returns: 正規化後之 One-sided PSD 能量陣列
    public func calculateOneSidedPSD(centered: [Float]) -> [Float] {
        let n = Self.windowSize

        guard centered.count == n else {
            return []
        }

        let halfN = n / 2
        let numBins = halfN + 1

        var windowed = [Float](repeating: 0.0, count: n)

        for i in 0..<n {
            windowed[i] = centered[i] * hannWindow[i]
        }

        var psd = [Float](repeating: 0.0, count: numBins)
        let scaleNorm = 1.0 / (Float(Self.sampleRate) * windowPower)

        for k in 0..<numBins {
            var realSum: Float = 0.0
            var imagSum: Float = 0.0
            let angleIncrement = -2.0 * Float.pi * Float(k) / Float(n)

            for index in 0..<n {
                let angle = angleIncrement * Float(index)
                let value = windowed[index]

                realSum += value * cos(angle)
                imagSum += value * sin(angle)
            }

            let magnitudeSquared = realSum * realSum + imagSum * imagSum
            var power = magnitudeSquared * scaleNorm

            if k > 0 && k < halfN {
                power *= 2.0
            }

            psd[k] = power
        }

        return psd
    }

    /// 提供外部舊有模組相容使用，將 Double 陣列轉為 Float 並執行 PSD 分析
    /// - Parameter signal: 欲分析之原始 Double 角速度資料陣列
    /// - Returns: 運算後之 Double 功率譜密度能量陣列
    public func calculatePSD(signal: [Double]) -> [Double] {
        guard signal.count == Self.windowSize else {
            return []
        }

        let floatSignal = signal.map { Float($0) }
        var mean: Float = 0.0

        vDSP_meanv(floatSignal, 1, &mean, vDSP_Length(floatSignal.count))

        var negativeMean = -mean
        var centered = [Float](repeating: 0.0, count: floatSignal.count)

        vDSP_vsadd(floatSignal, 1, &negativeMean, &centered, 1, vDSP_Length(floatSignal.count))

        return calculateOneSidedPSD(centered: centered).map { Double($0) }
    }

    /// 構造並回傳一組表示資料異常且不可信之空特徵分析結果物件
    /// - Returns: 各項數據皆為零或 nil 之 TremorAnalysisResult 實體
    private func makeInvalidResult() -> TremorAnalysisResult {
        TremorAnalysisResult(
            dataValid: false,
            frequencyReliable: false,
            dominantFrequencyHz: nil,
            tremorStrengthRmsDps: 0.0,
            vectorRmsDps: 0.0,
            tremorBandFraction: 0.0,
            peakConcentration: 0.0
        )
    }
}
