import XCTest

@testable import Glove

/// 震顫分析器單元測試套件，負責驗證訊號頻率辨識、功率譜密度 (PSD) 計算與動作防呆門檻
final class TremorAnalyzerTests: XCTestCase {

    /// 震顫分析器待測實例
    var analyzer: TremorAnalyzer!

    override func setUp() {
        super.setUp()
        analyzer = TremorAnalyzer()
    }

    override func tearDown() {
        analyzer = nil
        super.tearDown()
    }

    // MARK: - 5Hz 標準震顫訊號測試

    /// 驗證標準 5Hz 合成震顫訊號之主要頻率、FFT Bin、各軸功率與 RMS 強度
    func testTremor5HzValidation() throws {
        var mockData = [TremorDataPoint]()
        let fs = 100.0

        for i in 0..<400 {
            let t = Double(i) / fs

            let xTerm1 = 10.0 * sin(2.0 * Double.pi * 5.0 * t)
            let xTerm2 = 0.20 * sin(2.0 * Double.pi * 11.0 * t)
            let gyroX = xTerm1 + xTerm2

            let yTerm1 = 6.0 * sin(2.0 * Double.pi * 5.0 * t + 0.8)
            let yTerm2 = 0.15 * sin(2.0 * Double.pi * 13.0 * t)
            let gyroY = yTerm1 + yTerm2

            let zTerm1 = 3.0 * sin(2.0 * Double.pi * 5.0 * t + 1.6)
            let zTerm2 = 1.0 * sin(2.0 * Double.pi * 2.0 * t)
            let gyroZ = zTerm1 + zTerm2

            mockData.append(
                TremorDataPoint(
                    sequence: UInt32(i),
                    sampleTickMs: UInt32(Double(i) * 10.0),
                    gyroXDps: gyroX,
                    gyroYDps: gyroY,
                    gyroZDps: gyroZ,
                    sensorValid: 1,
                    motorEnabled: 0
                )
            )
        }

        let result = analyzer.analyze(data: mockData)

        XCTAssertTrue(result.dataValid, "資料應判定為有效")
        XCTAssertTrue(result.frequencyReliable, "標準 5Hz 資料應判定為可靠頻率")
        XCTAssertEqual(result.candidateBin, 20, "FFT Bin 應精準對齊 Bin 20 (5.00 Hz)")

        if let domFreq = result.dominantFrequencyHz {
            XCTAssertEqual(domFreq, 5.0, accuracy: 0.001, "主要頻率應為 5.00 Hz")
        } else {
            XCTFail("主要頻率不應為 nil")
        }

        let expectedRms = 8.5147
        let rmsTolerance = expectedRms * 0.005
        XCTAssertEqual(
            result.tremorStrengthRmsDps,
            expectedRms,
            accuracy: rmsTolerance,
            "整體 4-6Hz RMS 強度應約為 8.5147 deg/s"
        )

        // 驗證 X 軸單獨 PSD 與 4-6Hz 區間功率
        let gyroX = mockData.map { $0.gyroXDps }
        let psdX = analyzer.calculatePSD(signal: gyroX)
        let powerX = psdX[16...24].reduce(0, +) * 0.25
        XCTAssertEqual(
            powerX,
            50.0000,
            accuracy: 50.0000 * 0.005,
            "X 軸 4-6Hz 區間功率應約為 50.0 (deg/s)^2"
        )

        // 驗證 Y 軸單獨 PSD 與 4-6Hz 區間功率
        let gyroY = mockData.map { $0.gyroYDps }
        let psdY = analyzer.calculatePSD(signal: gyroY)
        let powerY = psdY[16...24].reduce(0, +) * 0.25
        XCTAssertEqual(
            powerY,
            18.0000,
            accuracy: 18.0000 * 0.005,
            "Y 軸 4-6Hz 區間功率應約為 18.0 (deg/s)^2"
        )

        // 驗證 Z 軸單獨 PSD 與 4-6Hz 區間功率
        let gyroZ = mockData.map { $0.gyroZDps }
        let psdZ = analyzer.calculatePSD(signal: gyroZ)
        let powerZ = psdZ[16...24].reduce(0, +) * 0.25
        XCTAssertEqual(
            powerZ,
            4.5000,
            accuracy: 4.5000 * 0.005,
            "Z 軸 4-6Hz 區間功率應約為 4.5 (deg/s)^2"
        )
    }

    // MARK: - 雜訊與飄動干擾測試

    /// 驗證含環境雜訊之 5Hz 資料能否正確計算候選特徵，並經由集中度門檻判定為不可靠頻率
    func testTremorNoisy5HzValidation() throws {
        guard
            let url = Bundle(for: type(of: self)).url(
                forResource: "tremor_noisy_5hz",
                withExtension: "csv"
            )
        else {
            XCTFail("找不到測試資源檔案: tremor_noisy_5hz.csv")
            return
        }

        let mockData = try parseCSVToTremorData(from: url)
        let result = analyzer.analyze(data: mockData)

        XCTAssertTrue(result.dataValid, "資料筆數與時序應判定為有效")
        XCTAssertFalse(result.frequencyReliable, "峰值集中度不足之雜訊資料應被防呆機制判定為不可靠")
        XCTAssertNil(result.dominantFrequencyHz, "頻率不可靠時主要頻率輸出應為 nil")
        XCTAssertEqual(result.candidateBin, 19, "FFT 候選 Bin 應為 Bin 19 (4.75 Hz)")

        let expectedRms = 5.7901
        let rmsTolerance = expectedRms * 0.005
        XCTAssertEqual(
            result.tremorStrengthRmsDps,
            expectedRms,
            accuracy: rmsTolerance,
            "RMS 強度計算應約為 5.7901 deg/s"
        )
    }

    // MARK: - 2Hz 日常動作排除測試

    /// 驗證 2Hz 大動作訊號是否能被震顫頻段防呆機制阻擋
    func testGating2HzValidation() throws {
        guard
            let url = Bundle(for: type(of: self)).url(
                forResource: "gating_02hz",
                withExtension: "csv"
            )
        else {
            XCTFail("找不到測試資源檔案: gating_02hz.csv")
            return
        }

        let allData = try parseCSVToTremorData(from: url)
        let startIndex =
            allData.firstIndex(where: { $0.sequence == 100 }) ?? 100
        var mockData = Array(allData[startIndex..<(startIndex + 400)])

        XCTAssertEqual(mockData.count, 400, "測試輸入必須為 400 筆資料")

        for i in 0..<mockData.count {
            mockData[i].gyroYDps = 0.0
            mockData[i].gyroZDps = 0.0
        }

        let result = analyzer.analyze(data: mockData)

        XCTAssertTrue(result.dataValid, "資料筆數與時序應判定為有效")
        XCTAssertFalse(result.frequencyReliable, "2Hz 非典型震顫訊號應判定為不可靠頻率")
        XCTAssertNil(result.dominantFrequencyHz, "不可靠頻率之主要頻率輸出應為 nil")
    }

    // MARK: - 測試資料解析工具

    /// 解析 CSV 檔案內容為 TremorDataPoint 陣列
    /// - Parameter url: CSV 檔案之本地 URL 路徑
    /// - Returns: 解析後之 TremorDataPoint 陣列
    /// - Throws: 讀取檔案或字串轉換失敗時拋出錯誤
    private func parseCSVToTremorData(from url: URL) throws -> [TremorDataPoint] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let rows = content.components(separatedBy: .newlines).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var dataPoints = [TremorDataPoint]()

        for row in rows.dropFirst() {
            let columns = row.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard columns.count >= 5 else { continue }

            let sequence = UInt32(columns[0]) ?? 0
            let sampleTickMs = UInt32(Double(columns[1]) ?? 0.0)

            var gyroXDps: Double = 0.0
            var gyroYDps: Double = 0.0
            var gyroZDps: Double = 0.0
            var sensorValid: UInt8 = 1
            var motorEnabled: UInt8 = 0

            if columns.count >= 7 {
                gyroXDps = Double(columns[2]) ?? 0.0
                gyroYDps = Double(columns[3]) ?? 0.0
                gyroZDps = Double(columns[4]) ?? 0.0
                sensorValid = UInt8(columns[5]) ?? 1
                motorEnabled = UInt8(columns[6]) ?? 0
            } else {
                gyroXDps = Double(columns[3]) ?? 0.0
            }

            dataPoints.append(
                TremorDataPoint(
                    sequence: sequence,
                    sampleTickMs: sampleTickMs,
                    gyroXDps: gyroXDps,
                    gyroYDps: gyroYDps,
                    gyroZDps: gyroZDps,
                    sensorValid: sensorValid,
                    motorEnabled: motorEnabled
                )
            )
        }

        return dataPoints
    }
}
