import Accelerate
import Foundation

/// 負責處理手部震顫訊號分析、PSD 功率譜密度計算
public class TremorAnalyzer {
    
    /// 採樣點數（4 秒視窗長度）
    private let N = 400

    /// 採樣頻率 (Hz)
    private let fs = 100.0

    /// 頻率解析度 (Hz/bin)，即 fs / N
    private let df = 0.25

    /// 預先計算之 Hann Window 權重陣列
    private var window: [Double]

    /// Hann Window 平方和，用於 PSD 能量正規化計算
    private var sumW2: Double = 0

    /// 初始化震顫分析器，預先計算 Hann 視窗函數權重與能量正規化係數
    public init() {
        window = [Double](repeating: 0, count: N)
        for i in 0..<N {
            window[i] = 0.5 * (1.0 - cos(2.0 * .pi * Double(i) / Double(N - 1)))
        }
        sumW2 = window.reduce(0) { $0 + $1 * $1 }
    }

    /// 分析單一 4 秒（400 筆採樣點）視窗資料之震顫特徵
    /// - Parameter data: 400 筆陀螺儀與感測器狀態資料陣列
    /// - Returns: 震顫分析結果模型，包含資料有效性、主要頻率、震顫強度及可靠度判定
    public func analyze(data: [TremorDataPoint]) -> TremorAnalysisResult {
        // 資料筆數與有效性前置驗證
        guard data.count == N else {
            return TremorAnalysisResult(
                dataValid: false,
                frequencyReliable: false,
                dominantFrequencyHz: nil,
                tremorStrengthRmsDps: 0,
                candidateBin: nil
            )
        }

        guard data.allSatisfy({ $0.sensorValid == 1 }) else {
            return TremorAnalysisResult(
                dataValid: false,
                frequencyReliable: false,
                dominantFrequencyHz: nil,
                tremorStrengthRmsDps: 0,
                candidateBin: nil
            )
        }

        // 檢查序號連續性與採樣時間間隔 (8ms ~ 12ms 之間)
        for i in 1..<N {
            if data[i].sequence != data[i - 1].sequence + 1 {
                return TremorAnalysisResult(
                    dataValid: false,
                    frequencyReliable: false,
                    dominantFrequencyHz: nil,
                    tremorStrengthRmsDps: 0,
                    candidateBin: nil
                )
            }
            let tickDiff = data[i].sampleTickMs &- data[i - 1].sampleTickMs
            if tickDiff < 8 || tickDiff > 12 {
                return TremorAnalysisResult(
                    dataValid: false,
                    frequencyReliable: false,
                    dominantFrequencyHz: nil,
                    tremorStrengthRmsDps: 0,
                    candidateBin: nil
                )
            }
        }

        // 逐軸計算單邊功率譜密度 (One-sided PSD)
        let gyroX = data.map { $0.gyroXDps }
        let gyroY = data.map { $0.gyroYDps }
        let gyroZ = data.map { $0.gyroZDps }

        let psdX = calculatePSD(signal: gyroX)
        let psdY = calculatePSD(signal: gyroY)
        let psdZ = calculatePSD(signal: gyroZ)

        // 三軸 PSD 相同頻率 Bin 能量向量疊加
        var psdSum = [Double](repeating: 0, count: psdX.count)
        for k in 0..<psdSum.count {
            psdSum[k] = psdX[k] + psdY[k] + psdZ[k]
        }

        // 計算 3-7 Hz (Bins 12-28) 震顫特徵頻段之主要頻率與功率
        var maxPsd: Double = -1
        var candidateBin = -1
        var power3To7: Double = 0

        for k in 12...28 {
            power3To7 += psdSum[k]
            if psdSum[k] > maxPsd {
                maxPsd = psdSum[k]
                candidateBin = k
            }
        }
        power3To7 *= df
        let candidateFrequencyHz = Double(candidateBin) * df

        // 計算 4-6 Hz (Bins 16-24) 典型震顫強度 (RMS)
        var power4To6: Double = 0
        for k in 16...24 {
            power4To6 += psdSum[k]
        }
        power4To6 *= df
        let tremorStrengthRmsDps = sqrt(power4To6)

        // 計算整體頻譜總功率 (Total Power)
        var totalPower: Double = 0
        for k in 0..<psdSum.count {
            totalPower += psdSum[k]
        }
        totalPower *= df

        // 防呆門檻與特徵比值計算
        let vectorRms = tremorStrengthRmsDps
        let tremorBandFraction = totalPower > 0 ? (power3To7 / totalPower) : 0
        let peakConcentration = power3To7 > 0 ? ((maxPsd * df) / power3To7) : 0

        // 設定浮點數容差 (Epsilon) 吸收底層硬體與跨平台運算微小誤差
        let epsilon = 1e-4
        let frequencyReliable =
            (vectorRms >= 0.20 - epsilon)
            && (tremorBandFraction >= 0.30 - epsilon)
            && (peakConcentration >= 0.45 - epsilon)

        return TremorAnalysisResult(
            dataValid: true,
            frequencyReliable: frequencyReliable,
            dominantFrequencyHz: frequencyReliable ? candidateFrequencyHz : nil,
            tremorStrengthRmsDps: tremorStrengthRmsDps,
            candidateBin: candidateBin
        )
    }

    /// 計算單一軸向訊號之單邊功率譜密度 (One-sided PSD)
    /// - Parameter signal: 單軸角速度訊號數值陣列（長度為 N）
    /// - Returns: 長度為 (N/2 + 1) 之 PSD 能量陣列，單位為 (deg/s)^2/Hz
    public func calculatePSD(signal: [Double]) -> [Double] {
        // 去除訊號平均值（DC 偏置消除）
        var mean: Double = 0
        vDSP_meanvD(signal, 1, &mean, vDSP_Length(N))

        var zeroMean = [Double](repeating: 0, count: N)
        var negMean = -mean
        vDSP_vsaddD(signal, 1, &negMean, &zeroMean, 1, vDSP_Length(N))

        // 套用 Hann 視窗函數以抑制頻譜洩漏
        var windowed = [Double](repeating: 0, count: N)
        vDSP_vmulD(zeroMean, 1, window, 1, &windowed, 1, vDSP_Length(N))

        // 執行精確離散傅立葉轉換 (DFT)，避免零填充以保持演算法頻率對齊
        var realOut = [Double](repeating: 0, count: N / 2 + 1)
        var imagOut = [Double](repeating: 0, count: N / 2 + 1)
        let angleBase = -2.0 * Double.pi / Double(N)

        for k in 0...(N / 2) {
            var sumReal = 0.0
            var sumImag = 0.0
            let kAngle = angleBase * Double(k)
            for n in 0..<N {
                let theta = kAngle * Double(n)
                let wn = windowed[n]
                sumReal += wn * cos(theta)
                sumImag += wn * sin(theta)
            }
            realOut[k] = sumReal
            imagOut[k] = sumImag
        }

        // 轉換為 One-sided PSD 格式，單位：(deg/s)^2/Hz
        var psd = [Double](repeating: 0, count: N / 2 + 1)
        let scaling = fs * sumW2

        // DC 分量 (0 Hz) 與 Nyquist 分量 (fs/2) 保持原值，不乘 2
        let realDC = realOut[0]
        let imagDC = imagOut[0]
        psd[0] = (realDC * realDC + imagDC * imagDC) / scaling

        let nyqIdx = N / 2
        let realNyq = realOut[nyqIdx]
        let imagNyq = imagOut[nyqIdx]
        psd[nyqIdx] = (realNyq * realNyq + imagNyq * imagNyq) / scaling

        // 內部頻率 Bin 能量翻倍補償單邊頻譜
        for k in 1..<nyqIdx {
            let mag2 = (realOut[k] * realOut[k] + imagOut[k] * imagOut[k])
            psd[k] = (mag2 / scaling) * 2.0
        }

        return psd
    }
}
