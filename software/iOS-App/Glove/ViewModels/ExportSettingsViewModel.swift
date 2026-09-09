import Combine
import Foundation
import SwiftUI

final class ExportSettingsViewModel: ObservableObject {
    let loginVM: LoginViewModel
    let medVM: MedicationViewModel
    let dataVM: DataViewModel
    let symptomVM: SymptomViewModel
    let vitalsVM: HealthVitalsViewModel
    private let aiRepository = AIChatRepository()

    /// 匯出報告之起訖日期設定
    @Published var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @Published var endDate = Date()

    /// 匯出設定當前操作步驟
    @Published var currentStep = 1

    /// 報告類別、主題與自訂欄位選取設定
    @Published var customCategoryText: String = ""
    @Published var selectedReportTypes: Set<String> = []
    @Published var customReportFields: [ConsultationCustomField] = []
    @Published var selectedCategories: Set<String> = []
    @Published var expandedCategories: Set<String> = []

    /// 診間溝通卡片各欄位文字內容
    @Published var preparationBeforeVisit = ""
    @Published var patientStatusDescription = ""
    @Published var comparisonWithLastVisit = ""
    @Published var otherMedicationsOrNotes = ""
    @Published var questionsForDoctor = ""

    /// AI 摘要生成狀態控制旗標
    @Published var hasGeneratedSummary = false
    @Published var isGeneratingSummary = false

    /// PDF 產生與預覽相關狀態旗標及資料
    @Published var generatedPDFData: Data? = nil
    @Published var showPreviewSheet = false
    @Published var isGeneratingPDF = false
    @Published var includeMoodNotes: Bool = false

    /// 錯誤提示相關狀態旗標與訊息
    @Published var showErrorAlert = false
    @Published var errorMessage = ""

    /// 首頁就診準備事項儲存於 UserDefaults 之鍵名常數
    static let homePreparationKey = "home_visit_preparation_note"

    /// 可供選取的報告類型清單
    var reportTypeOptions: [String] {
        ReportConfig.reportTypeOptions
    }

    /// 預設健康評估類別項目清單
    var categoryOptions: [CategoryItem] {
        ReportConfig.defaultCategories
    }

    /// 判斷使用者是否已完成有效欄位選取
    var hasValidSelection: Bool {
        !selectedReportTypes.isEmpty || customReportFields.contains {
            !$0.title.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// 初始化匯出設定檢視模型，注入相依的各個業務邏輯 ViewModel
    init(
        loginVM: LoginViewModel,
        medVM: MedicationViewModel,
        dataVM: DataViewModel,
        symptomVM: SymptomViewModel,
        vitalsVM: HealthVitalsViewModel
    ) {
        self.loginVM = loginVM
        self.medVM = medVM
        self.dataVM = dataVM
        self.symptomVM = symptomVM
        self.vitalsVM = vitalsVM
    }

    /// 新增一筆空的自訂回診溝通欄位項目
    func addCustomReportField() {
        customReportFields.append(ConsultationCustomField())
    }

    /// 依據指定索引集合移除特定的自訂溝通欄位項目
    /// - Parameter offsets: 欲移除項目之索引集合
    func removeCustomReportField(at offsets: IndexSet) {
        customReportFields.remove(atOffsets: offsets)
    }

    /// 若使用者選取了「看病前準備」，將該準備事項文字快取至本機 UserDefaults
    func savePreparationToHome() {
        guard selectedReportTypes.contains("看病前準備") else { return }
        let trimmed = preparationBeforeVisit.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: Self.homePreparationKey)
    }

    /// 向 AI 後端伺服器發送非同步請求以產生診間溝通摘要建議
    @MainActor
    func requestAISummaryAsync() async {
        isGeneratingSummary = true

        let customFieldsDTO = customReportFields
            .filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { CustomReportFieldDTO(title: $0.title, content: $0.content) }

        let payload = GenerateConsultationSummaryRequestDTO(
            startDate: startDate,
            endDate: endDate,
            selectedReportTypes: Array(selectedReportTypes),
            selectedCategories: Array(selectedCategories),
            customCategoryText: customCategoryText.isEmpty ? nil : customCategoryText,
            includeMoodNotes: includeMoodNotes,
            customFields: customFieldsDTO.isEmpty ? nil : customFieldsDTO
        )

        do {
            let result = try await aiRepository.generateConsultationSummary(payload: payload)
            preparationBeforeVisit = result.preparationBeforeVisit
            patientStatusDescription = result.patientStatusDescription
            comparisonWithLastVisit = result.comparisonWithLastVisit
            otherMedicationsOrNotes = result.otherMedicationsOrNotes
            questionsForDoctor = result.questionsForDoctor

            for summaryField in result.customFieldsSummary {
                if let index = customReportFields.firstIndex(where: { $0.title == summaryField.title }) {
                    customReportFields[index].content = summaryField.content
                }
            }
            hasGeneratedSummary = true
        } catch {
            AppLog.error("AI 摘要生成失敗: \(error.localizedDescription)")
            errorMessage = "AI 摘要生成失敗：\(error.localizedDescription)"
            showErrorAlert = true
        }

        isGeneratingSummary = false
    }

    /// 對傳入字串進行 HTML 特殊跳脫字元轉換，防止排版錯位與 XSS
    /// - Parameter value: 原始字串
    /// - Returns: 跳脫處理後的安全字串
    private func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// 建立指定日期格式且固定時區為台北的 DateFormatter
    /// - Parameter format: 日期格式字串
    /// - Returns: 設定完成的 DateFormatter
    private func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        formatter.dateFormat = format
        return formatter
    }

    /// 取得設定台北時區的 Calendar 實體
    private var reportCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return calendar
    }

    /// 產生 RMS 連續折線圖 SVG 字串
    /// - Parameters:
    ///   - startStr: 開始日期字串
    ///   - endStr: 結束日期字串
    ///   - filterStart: 篩選起始時間
    ///   - filterEnd: 篩選結束時間
    /// - Returns: 繪製完成的 SVG 程式碼
    private func generateRMSTrendSVG(
        startStr: String,
        endStr: String,
        filterStart: Date,
        filterEnd: Date
    ) -> String {
        let calendar = reportCalendar

        let width: Double = 700
        let height: Double = 170
        let paddingLeft: Double = 48
        let paddingRight: Double = 32
        let paddingTop: Double = 24
        let paddingBottom: Double = 32
        let plotWidth = width - paddingLeft - paddingRight
        let plotHeight = height - paddingTop - paddingBottom

        let startTime = filterStart.timeIntervalSince1970
        let endTime = filterEnd.timeIntervalSince1970
        let timeSpan = max(endTime - startTime, 1)

        let rawPoints = dataVM.rmsTrendHistory
            .filter {
                $0.timestamp >= filterStart &&
                $0.timestamp <= filterEnd &&
                $0.rmsValue.isFinite &&
                !$0.rmsValue.isNaN
            }
            .sorted { $0.timestamp < $1.timestamp }

        guard !rawPoints.isEmpty else {
            return """
            <svg xmlns="http://www.w3.org/2000/svg" width="100%" height="\(height)" viewBox="0 0 \(width) \(height)">
                <text x="\(width / 2)" y="\(height / 2)" font-size="11" fill="#a0aec0" text-anchor="middle">
                    此期間內沒有 RMS 連續走勢資料
                </text>
            </svg>
            """
        }

        struct PlotSample {
            let timestamp: Date
            let rms: Double
        }

        func timeBasedDownsample(points: [PlotSample], maxBuckets: Int) -> [PlotSample] {
            guard points.count > maxBuckets,
                  let first = points.first,
                  let last = points.last else {
                return points
            }

            let totalDuration = max(last.timestamp.timeIntervalSince(first.timestamp), 0.001)
            let bucketDuration = max(totalDuration / Double(maxBuckets), 0.001)
            var buckets: [[PlotSample]] = Array(repeating: [], count: maxBuckets)

            for point in points {
                let offset = point.timestamp.timeIntervalSince(first.timestamp)
                let rawIndex = Int(floor(offset / bucketDuration))
                let index = min(max(rawIndex, 0), maxBuckets - 1)
                buckets[index].append(point)
            }

            var result: [PlotSample] = []
            result.reserveCapacity(maxBuckets * 4)

            for bucket in buckets {
                guard !bucket.isEmpty else { continue }
                if let firstPoint = bucket.first { result.append(firstPoint) }
                if let minimum = bucket.min(by: { $0.rms < $1.rms }) { result.append(minimum) }
                if let maximum = bucket.max(by: { $0.rms < $1.rms }) { result.append(maximum) }
                if let lastPoint = bucket.last { result.append(lastPoint) }
            }

            result.sort { $0.timestamp < $1.timestamp }

            var unique: [PlotSample] = []
            unique.reserveCapacity(result.count)

            for sample in result {
                if let last = unique.last,
                   abs(last.timestamp.timeIntervalSince(sample.timestamp)) < 0.0001,
                   abs(last.rms - sample.rms) < 0.000001 {
                    continue
                }
                unique.append(sample)
            }

            return unique
        }

        let sourceSamples: [PlotSample] = rawPoints.map { PlotSample(timestamp: $0.timestamp, rms: $0.rmsValue) }
        let plotData = timeBasedDownsample(points: sourceSamples, maxBuckets: 900)

        let maximumRMS = plotData.map { $0.rms }.max() ?? 0
        let minimumRMS = plotData.map { $0.rms }.min() ?? 0
        let maxRMS = max(maximumRMS * 1.15, 0.5)
        let minRMS = min(0, minimumRMS)

        func xPosition(for date: Date) -> Double {
            let timestamp = date.timeIntervalSince1970
            let ratio = (timestamp - startTime) / timeSpan
            return paddingLeft + ratio * plotWidth
        }

        func yPosition(for rms: Double) -> Double {
            let safeValue = min(max(rms, minRMS), maxRMS)
            let normalized = (safeValue - minRMS) / max(maxRMS - minRMS, 0.001)
            return (height - paddingBottom) - normalized * plotHeight
        }

        let gapBreakThreshold: TimeInterval = 5 * 60
        var segments: [[PlotSample]] = []
        var currentSegment: [PlotSample] = []

        for point in plotData {
            if let previous = currentSegment.last {
                let gap = point.timestamp.timeIntervalSince(previous.timestamp)
                if gap > gapBreakThreshold {
                    if !currentSegment.isEmpty {
                        segments.append(currentSegment)
                    }
                    currentSegment = [point]
                    continue
                }
            }
            currentSegment.append(point)
        }
        if !currentSegment.isEmpty {
            segments.append(currentSegment)
        }

        var polylineSVG = ""
        for segment in segments {
            guard segment.count >= 2 else {
                if let point = segment.first {
                    let x = xPosition(for: point.timestamp)
                    let y = yPosition(for: point.rms)
                    polylineSVG += "<circle cx='\(x)' cy='\(y)' r='1.8' fill='#3182ce' />"
                }
                continue
            }

            let pointsString = segment
                .map { "\(String(format: "%.2f", xPosition(for: $0.timestamp))),\(String(format: "%.2f", yPosition(for: $0.rms)))" }
                .joined(separator: " ")

            polylineSVG += """
            <polyline points='\(pointsString)' fill='none' stroke='#3182ce' stroke-width='2' stroke-linecap='round' stroke-linejoin='round' vector-effect='non-scaling-stroke' />
            """
        }

        let yTicks: [Double] = [0, maxRMS * 0.25, maxRMS * 0.5, maxRMS * 0.75, maxRMS]
        var yAxisSVG = ""
        for tick in yTicks {
            let y = yPosition(for: tick)
            yAxisSVG += """
            <line x1='\(paddingLeft)' y1='\(y)' x2='\(width - paddingRight)' y2='\(y)' stroke='#edf2f7' stroke-width='1' />
            <text x='\(paddingLeft - 7)' y='\(y + 3)' font-size='8' fill='#a0aec0' text-anchor='end'>\(String(format: "%.1f", tick))</text>
            """
        }

        let threshold = 0.20
        let thresholdY = yPosition(for: threshold)
        let thresholdSVG = """
        <line x1='\(paddingLeft)' y1='\(thresholdY)' x2='\(width - paddingRight)' y2='\(thresholdY)' stroke='#e53e3e' stroke-width='1.2' stroke-dasharray='4,3' stroke-opacity='0.75' />
        <text x='\(width - paddingRight - 4)' y='\(thresholdY - 4)' font-size='8' fill='#e53e3e' text-anchor='end'>警戒線 0.20</text>
        """

        var xAxisSVG = ""
        let isSingleDay = calendar.isDate(startDate, inSameDayAs: endDate)

        if isSingleDay {
            let baseDay = calendar.startOfDay(for: startDate)
            if calendar.isDateInToday(endDate) {
                let currentHour = calendar.component(.hour, from: filterEnd)
                var hourTicks = Array(stride(from: 0, through: currentHour, by: 4))
                if !hourTicks.contains(currentHour) {
                    hourTicks.append(currentHour)
                }

                for hour in hourTicks {
                    let tickDate = baseDay.addingTimeInterval(Double(hour) * 3600)
                    guard tickDate >= filterStart, tickDate <= filterEnd else { continue }
                    let x = xPosition(for: tickDate)
                    xAxisSVG += """
                    <line x1='\(x)' y1='\(height - paddingBottom)' x2='\(x)' y2='\(height - paddingBottom + 4)' stroke='#cbd5e0' stroke-width='1' />
                    <text x='\(x)' y='\(height - 8)' font-size='8' fill='#a0aec0' text-anchor='middle'>\(String(format: "%02d:00", hour))</text>
                    """
                }

                let nowX = xPosition(for: filterEnd)
                xAxisSVG += """
                <line x1='\(nowX)' y1='\(paddingTop)' x2='\(nowX)' y2='\(height - paddingBottom)' stroke='#3182ce' stroke-width='1' stroke-dasharray='3,3' stroke-opacity='0.45' />
                <text x='\(nowX - 3)' y='\(paddingTop - 7)' font-size='8' fill='#3182ce' text-anchor='end'>現在</text>
                """
            } else {
                let hourTicks = [0, 4, 8, 12, 16, 20, 24]
                for hour in hourTicks {
                    let tickDate = baseDay.addingTimeInterval(Double(hour) * 3600)
                    guard tickDate >= filterStart, tickDate <= filterEnd else { continue }
                    let x = xPosition(for: tickDate)
                    xAxisSVG += """
                    <line x1='\(x)' y1='\(height - paddingBottom)' x2='\(x)' y2='\(height - paddingBottom + 4)' stroke='#cbd5e0' stroke-width='1' />
                    <text x='\(x)' y='\(height - 8)' font-size='8' fill='#a0aec0' text-anchor='middle'>\(String(format: "%02d:00", hour))</text>
                    """
                }
            }
        } else {
            xAxisSVG += """
            <text x='\(paddingLeft)' y='\(height - 8)' font-size='8.5' fill='#a0aec0' text-anchor='start'>\(htmlEscape(startStr))</text>
            <text x='\(width - paddingRight)' y='\(height - 8)' font-size='8.5' fill='#a0aec0' text-anchor='end'>\(htmlEscape(endStr))</text>
            """
        }

        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="100%" height="\(height)" viewBox="0 0 \(width) \(height)" preserveAspectRatio="none">
            \(yAxisSVG)
            \(thresholdSVG)
            <line x1='\(paddingLeft)' y1='\(height - paddingBottom)' x2='\(width - paddingRight)' y2='\(height - paddingBottom)' stroke='#cbd5e0' stroke-width='1' />
            \(polylineSVG)
            \(xAxisSVG)
            <text x='\(paddingLeft - 8)' y='\(paddingTop - 8)' font-size='8.5' font-weight='bold' fill='#718096' text-anchor='end'>deg/s</text>
        </svg>
        """
    }

    /// 產生每小時主要震動頻率分布直方圖 SVG 字串
    /// - Parameters:
    ///   - startStr: 開始日期字串
    ///   - endStr: 結束日期字串
    ///   - filterStart: 篩選起始時間
    ///   - filterEnd: 篩選結束時間
    /// - Returns: 繪製完成的 SVG 程式碼
    private func generatePSDSVG(
        startStr: String,
        endStr: String,
        filterStart: Date,
        filterEnd: Date
    ) -> String {
        let analyzer = TremorAnalyzer()

        struct HourlyAggregate {
            let hourDate: Date
            var maxRMS: Double = 0.0
            var dominantFrequency: Double = 0.0
            var averageRMS: Double = 0.0
            private var totalRMS: Double = 0.0
            private var sampleCount: Int = 0

            init(hourDate: Date) {
                self.hourDate = hourDate
            }

            mutating func append(rms: Double, frequency: Double?, isReliable: Bool) {
                guard rms.isFinite, !rms.isNaN else { return }
                totalRMS += rms
                sampleCount += 1
                averageRMS = totalRMS / Double(sampleCount)

                if rms > maxRMS {
                    maxRMS = rms
                    if let frequency, frequency > 0 {
                        dominantFrequency = frequency
                    }
                }

                if dominantFrequency <= 0, isReliable, let frequency, frequency > 0 {
                    dominantFrequency = frequency
                }
            }
        }

        let calendar = reportCalendar
        var hourlyMap: [Date: HourlyAggregate] = [:]

        for point in dataVM.rmsTrendHistory where point.timestamp >= filterStart && point.timestamp <= filterEnd {
            guard point.rmsValue.isFinite, !point.rmsValue.isNaN else { continue }
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: point.timestamp)
            guard let hourBucket = calendar.date(from: components) else { continue }

            var frequency: Double? = nil
            var reliable = false

            if !point.rawWindowData.isEmpty {
                let result = analyzer.analyze(data: point.rawWindowData)
                frequency = result.dominantFrequencyHz
                reliable = result.frequencyReliable
            }

            hourlyMap[hourBucket, default: HourlyAggregate(hourDate: hourBucket)]
                .append(rms: point.rmsValue, frequency: frequency, isReliable: reliable)
        }

        for event in dataVM.tremorEvents where event.timestamp >= filterStart && event.timestamp <= filterEnd {
            guard event.rmsValue.isFinite, !event.rmsValue.isNaN else { continue }
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: event.timestamp)
            guard let hourBucket = calendar.date(from: components) else { continue }

            let frequency: Double? = event.dominantFrequency > 0 ? event.dominantFrequency : nil

            hourlyMap[hourBucket, default: HourlyAggregate(hourDate: hourBucket)]
                .append(rms: event.rmsValue, frequency: frequency, isReliable: frequency != nil)
        }

        let width: Double = 700
        let height: Double = 170
        let paddingLeft: Double = 48
        let paddingRight: Double = 32
        let paddingTop: Double = 24
        let paddingBottom: Double = 32
        let plotWidth = width - paddingLeft - paddingRight
        let plotHeight = height - paddingTop - paddingBottom

        let maxFreq: Double = 15.0
        let startTime = filterStart.timeIntervalSince1970
        let endTime = filterEnd.timeIntervalSince1970
        let timeSpan = max(endTime - startTime, 1)

        let isSingleDay = calendar.isDate(startDate, inSameDayAs: endDate)
        let aggregates = hourlyMap.values
            .filter { $0.hourDate >= filterStart && $0.hourDate <= filterEnd }
            .sorted { $0.hourDate < $1.hourDate }

        func xPosition(for date: Date) -> Double {
            let timestamp = date.timeIntervalSince1970
            return paddingLeft + ((timestamp - startTime) / timeSpan) * plotWidth
        }

        func yPosition(for frequency: Double) -> Double {
            let safe = min(max(frequency, 0), maxFreq)
            return (height - paddingBottom) - (safe / maxFreq) * plotHeight
        }

        let y3 = yPosition(for: 3)
        let y7 = yPosition(for: 7)
        let bandY = min(y3, y7)
        let bandHeight = abs(y3 - y7)
        let bandSVG = """
        <rect x='\(paddingLeft)' y='\(bandY)' width='\(plotWidth)' height='\(bandHeight)' fill='#9f7aea' fill-opacity='0.12' rx='3' />
        <text x='\(width - paddingRight - 8)' y='\(bandY + bandHeight / 2 + 3)' fill='#805ad5' opacity='0.55' font-size='9' font-weight='bold' text-anchor='end'>典型震顫頻帶 3–7 Hz</text>
        """

        var barsSVG = ""
        let calculatedBarWidth = aggregates.count <= 24 ? 18.0 : max(4.0, min(14.0, plotWidth / Double(max(aggregates.count * 2, 1))))

        for aggregate in aggregates {
            let x = xPosition(for: aggregate.hourDate)

            if aggregate.dominantFrequency <= 0 {
                let y = height - paddingBottom - 4
                barsSVG += """
                <circle cx='\(x)' cy='\(y)' r='3' fill='#ffffff' stroke='#a0aec0' stroke-width='1.4'>
                    <title>\(aggregate.hourDate.toString(format: "MM/dd HH:00"))&#10;此時段有 RMS 資料，但未取得可靠的主要震動頻率。</title>
                </circle>
                """
                continue
            }

            let freq = min(aggregate.dominantFrequency, maxFreq)
            let barHeight = (freq / maxFreq) * plotHeight
            let y = (height - paddingBottom) - barHeight
            let isTremorBand = freq >= 3 && freq <= 7
            let barColor = isTremorBand ? "#805ad5" : "#cbd5e0"
            let opacity = min(1.0, max(0.4, aggregate.averageRMS / 0.5))

            barsSVG += """
            <rect x='\(x - calculatedBarWidth / 2)' y='\(y)' width='\(calculatedBarWidth)' height='\(max(barHeight, 1.5))' fill='\(barColor)' fill-opacity='\(String(format: "%.2f", opacity))' rx='2'>
                <title>\(aggregate.hourDate.toString(format: "MM/dd HH:00"))&#10;主要頻率: \(String(format: "%.1f", freq)) Hz&#10;平均 RMS: \(String(format: "%.2f", aggregate.averageRMS)) deg/s&#10;最大 RMS: \(String(format: "%.2f", aggregate.maxRMS)) deg/s</title>
            </rect>
            """
        }

        let yTicks: [Double] = [0, 3, 7, 10, 15]
        var yAxisSVG = ""
        for tick in yTicks {
            let y = yPosition(for: tick)
            let highlight = tick == 3 || tick == 7
            let color = highlight ? "#6b46c1" : "#a0aec0"
            let weight = highlight ? "bold" : "normal"
            yAxisSVG += """
            <line x1='\(paddingLeft)' y1='\(y)' x2='\(width - paddingRight)' y2='\(y)' stroke='#edf2f7' stroke-width='1' />
            <text x='\(paddingLeft - 7)' y='\(y + 3)' font-size='8' font-weight='\(weight)' fill='\(color)' text-anchor='end'>\(Int(tick))</text>
            """
        }

        var xAxisSVG = ""
        if isSingleDay {
            let baseDay = calendar.startOfDay(for: startDate)
            if calendar.isDateInToday(endDate) {
                let currentHour = calendar.component(.hour, from: filterEnd)
                var hourTicks = Array(stride(from: 0, through: currentHour, by: 4))
                if !hourTicks.contains(currentHour) {
                    hourTicks.append(currentHour)
                }

                for hour in hourTicks {
                    let tickDate = baseDay.addingTimeInterval(Double(hour) * 3600)
                    guard tickDate >= filterStart, tickDate <= filterEnd else { continue }
                    let x = xPosition(for: tickDate)
                    xAxisSVG += """
                    <line x1='\(x)' y1='\(height - paddingBottom)' x2='\(x)' y2='\(height - paddingBottom + 4)' stroke='#cbd5e0' stroke-width='1' />
                    <text x='\(x)' y='\(height - 8)' font-size='8' fill='#a0aec0' text-anchor='middle'>\(String(format: "%02d:00", hour))</text>
                    """
                }

                let nowX = xPosition(for: filterEnd)
                xAxisSVG += """
                <line x1='\(nowX)' y1='\(paddingTop)' x2='\(nowX)' y2='\(height - paddingBottom)' stroke='#805ad5' stroke-width='1' stroke-dasharray='3,3' stroke-opacity='0.45' />
                <text x='\(nowX - 3)' y='\(paddingTop - 7)' font-size='8' fill='#805ad5' text-anchor='end'>現在</text>
                """
            } else {
                let hourTicks = [0, 4, 8, 12, 16, 20, 24]
                for hour in hourTicks {
                    let tickDate = baseDay.addingTimeInterval(Double(hour) * 3600)
                    guard tickDate >= filterStart, tickDate <= filterEnd else { continue }
                    let x = xPosition(for: tickDate)
                    xAxisSVG += """
                    <line x1='\(x)' y1='\(height - paddingBottom)' x2='\(x)' y2='\(height - paddingBottom + 4)' stroke='#cbd5e0' stroke-width='1' />
                    <text x='\(x)' y='\(height - 8)' font-size='8' fill='#a0aec0' text-anchor='middle'>\(String(format: "%02d:00", hour))</text>
                    """
                }
            }
        } else {
            xAxisSVG += """
            <text x='\(paddingLeft)' y='\(height - 8)' font-size='8.5' fill='#a0aec0' text-anchor='start'>\(htmlEscape(startStr))</text>
            <text x='\(width - paddingRight)' y='\(height - 8)' font-size='8.5' fill='#a0aec0' text-anchor='end'>\(htmlEscape(endStr))</text>
            """
        }

        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="100%" height="\(height)" viewBox="0 0 \(width) \(height)" preserveAspectRatio="none">
            \(bandSVG)
            \(yAxisSVG)
            <line x1='\(paddingLeft)' y1='\(height - paddingBottom)' x2='\(width - paddingRight)' y2='\(height - paddingBottom)' stroke='#cbd5e0' stroke-width='1' />
            \(barsSVG)
            \(xAxisSVG)
            <text x='\(paddingLeft - 8)' y='\(paddingTop - 8)' font-size='8.5' font-weight='bold' fill='#718096' text-anchor='end'>Hz</text>
        </svg>
        """
    }

    /// 整合各項健康數據、動態圖表與診間備註，渲染 HTML 模板並產生 PDF 二進位資料
    @MainActor
    func preparePDFForPreviewAsync() async {
        isGeneratingPDF = true
        savePreparationToHome()

        let calendar = reportCalendar
        let filterStart = calendar.startOfDay(for: startDate)
        let filterEnd: Date

        if calendar.isDateInToday(endDate) {
            filterEnd = min(endDate, Date())
        } else {
            filterEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
        }

        async let loadMeds: () = medVM.loadAllRecords()
        async let loadSymptoms: () = symptomVM.loadSymptoms(for: "", isSilent: true)
        async let loadTremor: () = dataVM.loadTremorHistory()
        async let loadVitals: () = vitalsVM.loadVitals()
        async let fetchAssessments = (try? AssessmentRepository.shared.fetchAssessment(dateString: nil)) ?? []
        
        let (_, _, _, _, allAssessments) = await (loadMeds, loadSymptoms, loadTremor, loadVitals, fetchAssessments)

        let formatter = makeDateFormatter("yyyy-MM-dd")
        let timeFormatter = makeDateFormatter("yyyy-MM-dd HH:mm")
        let eventTimeFormatter = makeDateFormatter("yyyy-MM-dd HH:mm:ss")

        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: endDate)
        let userName = htmlEscape(loginVM.partnerName)
        let userBirth: String

        if let birthday = loginVM.userData?.birthday {
            userBirth = formatter.string(from: birthday)
        } else {
            userBirth = "未設定生日"
        }

        let filteredMeds = medVM.medicationList
            .filter { $0.date >= filterStart && $0.date <= filterEnd }
            .sorted { $0.date < $1.date }

        var medicationRowsHTML = ""
        if filteredMeds.isEmpty {
            medicationRowsHTML = "<tr><td colspan='3' style='text-align:center; color:#a0aec0;'>此期間內無用藥紀錄</td></tr>"
        } else {
            for med in filteredMeds {
                medicationRowsHTML += """
                <tr>
                    <td>\(htmlEscape(timeFormatter.string(from: med.date)))</td>
                    <td>\(htmlEscape(med.name))</td>
                    <td>\(htmlEscape(med.dose))</td>
                </tr>
                """
            }
        }

        let filteredSymptoms = symptomVM.symptomList
            .filter { $0.date >= filterStart && $0.date <= filterEnd }
            .sorted { $0.date < $1.date }

        var symptomRowsHTML = ""
        if filteredSymptoms.isEmpty {
            symptomRowsHTML = "<div style='text-align:center; color:#a0aec0; font-size:12px; padding:12px; width:100%;'>此期間內無表徵與日常症狀紀錄</div>"
        } else {
            for symptom in filteredSymptoms {
                let note = symptom.symptomNote.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayNote = note.isEmpty ? "未填寫症狀文字備註" : note
                let mediaBadge = symptom.isVideo ? "<span class='tag-pill' style='color:#dd6b20;'>附帶影片</span>" : ""

                var imagesHTML = ""
                if !symptom.mediaDataList.isEmpty {
                    imagesHTML += "<div class='symptom-media-grid'>"
                    for data in symptom.mediaDataList {
                        let base64 = data.base64EncodedString()
                        imagesHTML += "<img src='data:image/jpeg;base64,\(base64)' class='symptom-img' />"
                    }
                    imagesHTML += "</div>"
                }

                symptomRowsHTML += """
                <div class="symptom-card">
                    <div class="symptom-header">
                        <span><strong>記錄時間：</strong>\(htmlEscape(timeFormatter.string(from: symptom.date)))</span>
                        \(mediaBadge)
                    </div>
                    <div class="symptom-text">\(htmlEscape(displayNote))</div>
                    \(imagesHTML)
                </div>
                """
            }
        }

        let filteredTremorEvents = dataVM.tremorEvents
            .filter { $0.timestamp >= filterStart && $0.timestamp <= filterEnd }
            .sorted { $0.timestamp < $1.timestamp }

        var tremorEventsRowsHTML = ""
        if filteredTremorEvents.isEmpty {
            tremorEventsRowsHTML = "<tr><td colspan='5' style='text-align:center; color:#a0aec0;'>此期間內未捕捉到顯著高震顫事件</td></tr>"
        } else {
            for event in filteredTremorEvents {
                let badgeClass: String
                let levelText: String

                if event.rmsValue >= 0.50 {
                    badgeClass = "badge-severe"
                    levelText = "劇烈震顫"
                } else if event.rmsValue >= 0.20 {
                    badgeClass = "badge-moderate"
                    levelText = "中度震顫"
                } else {
                    badgeClass = "badge-mild"
                    levelText = "微弱/平穩"
                }

                let tag = event.userTag.trimmingCharacters(in: .whitespacesAndNewlines)
                let tagHTML = tag.isEmpty ? "<span style='color:#a0aec0;'>未標記</span>" : "<span class='tag-pill'>\(htmlEscape(tag))</span>"
                let frequency = event.dominantFrequency > 0 ? String(format: "%.1f Hz", event.dominantFrequency) : "--"

                tremorEventsRowsHTML += """
                <tr>
                    <td>\(htmlEscape(eventTimeFormatter.string(from: event.timestamp)))</td>
                    <td><strong>\(String(format: "%.2f", event.rmsValue))</strong> deg/s</td>
                    <td>\(frequency)</td>
                    <td><span class='badge \(badgeClass)'>\(levelText)</span></td>
                    <td>\(tagHTML)</td>
                </tr>
                """
            }
        }

        let filteredVitals = vitalsVM.vitalsList
            .filter { $0.date >= filterStart && $0.date <= filterEnd }
            .sorted { $0.date < $1.date }

        var vitalsRowsHTML = ""
        if filteredVitals.isEmpty {
            vitalsRowsHTML = "<tr><td colspan='5' style='text-align:center; color:#a0aec0;'>此期間內無生理數據紀錄</td></tr>"
        } else {
            for vital in filteredVitals {
                let bpDisplay: String
                if let sys = vital.systolicBP, let dia = vital.diastolicBP, !sys.isEmpty, !dia.isEmpty {
                    bpDisplay = "\(htmlEscape(sys)) / \(htmlEscape(dia))"
                } else {
                    bpDisplay = htmlEscape(vital.systolicBP ?? vital.diastolicBP ?? "--")
                }

                let sugar = (vital.bloodSugar?.isEmpty == false) ? htmlEscape(vital.bloodSugar!) : "--"
                let temp = (vital.bodyTemp?.isEmpty == false) ? htmlEscape(vital.bodyTemp!) : "--"
                let weight = (vital.bodyWeight?.isEmpty == false) ? htmlEscape(vital.bodyWeight!) : "--"

                vitalsRowsHTML += """
                <tr>
                    <td>\(htmlEscape(timeFormatter.string(from: vital.date)))</td>
                    <td>\(bpDisplay)</td>
                    <td>\(sugar)</td>
                    <td>\(temp)</td>
                    <td>\(weight)</td>
                </tr>
                """
            }
        }
        
        let filteredAssessments = allAssessments
            .filter { $0.date >= filterStart && $0.date <= filterEnd }
            .sorted { $0.date < $1.date }

        var assessmentRowsHTML = ""
        if filteredAssessments.isEmpty {
            assessmentRowsHTML = "<tr><td colspan='3' style='text-align:center; color:#a0aec0;'>此期間內無自我評估量表紀錄</td></tr>"
        } else {
            for record in filteredAssessments {
                let questionCount = record.parsedDetails.count
                let maxPossibleScore = questionCount * 4
                
                assessmentRowsHTML += """
                <tr>
                    <td>\(htmlEscape(formatter.string(from: record.date)))</td>
                    <td><strong>\(record.totalScore)</strong> / \(maxPossibleScore) <br><span style="font-size:10px; color:#718096;">(共 \(questionCount) 題)</span></td>
                    <td>情緒: \(record.moodScore) | 日常: \(record.adlScore) | 動作: \(record.motorScore)</td>
                </tr>
                """
            }
        }

        var consultationBlocksHTML = ""

        if selectedReportTypes.contains("病人狀況描述") {
            let text = patientStatusDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = text.isEmpty ? "無特別備註狀況" : text
            consultationBlocksHTML += """
            <div class="content-block">
                <table class="meta-table" style="margin-bottom:5px;">
                    <tr><td><strong>病人狀況描述（日常動作與症狀）：</strong></td></tr>
                </table>
                <div class="note-box" style="border-left: 4px solid #3182ce;">\(htmlEscape(display))</div>
            </div>
            """
        }

        if selectedReportTypes.contains("上次回診差異") {
            let text = comparisonWithLastVisit.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = text.isEmpty ? "未觀察到明顯變化" : text
            consultationBlocksHTML += """
            <div class="content-block">
                <table class="meta-table" style="margin-bottom:5px;">
                    <tr><td><strong>與上次回診之差異比較（變化趨勢）：</strong></td></tr>
                </table>
                <div class="note-box" style="border-left: 4px solid #805ad5;">\(htmlEscape(display))</div>
            </div>
            """
        }

        if selectedReportTypes.contains("其他科別用藥與特殊補充") {
            let text = otherMedicationsOrNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = text.isEmpty ? "無特別用藥與補充事項" : text
            consultationBlocksHTML += """
            <div class="content-block">
                <table class="meta-table" style="margin-bottom:5px;">
                    <tr><td><strong>其他科別用藥與特殊補充：</strong></td></tr>
                </table>
                <div class="note-box" style="border-left: 4px solid #38a169;">\(htmlEscape(display))</div>
            </div>
            """
        }

        if selectedReportTypes.contains("想問醫生的問題") {
            let text = questionsForDoctor.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = text.isEmpty ? "無特定問題" : text
            consultationBlocksHTML += """
            <div class="content-block">
                <table class="meta-table" style="margin-bottom:5px;">
                    <tr><td><strong>本次想諮詢醫生的核心問題：</strong></td></tr>
                </table>
                <div class="note-box" style="border-left: 4px solid #dd6b20;">\(htmlEscape(display))</div>
            </div>
            """
        }

        for item in customReportFields {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = content.isEmpty ? "無備註說明" : content

            consultationBlocksHTML += """
            <div class="content-block">
                <table class="meta-table" style="margin-bottom:5px;">
                    <tr><td><strong>\(htmlEscape(title))：</strong></td></tr>
                </table>
                <div class="note-box" style="border-left: 4px solid #718096;">\(htmlEscape(display))</div>
            </div>
            """
        }

        let consultationSectionHTML = consultationBlocksHTML.isEmpty ? "" : """
        <div class="section-title">回診核心溝通與主觀觀測</div>
        \(consultationBlocksHTML)
        """

        guard let filepath = Bundle.main.path(forResource: "report_template", ofType: "html"),
              let templateString = try? String(contentsOfFile: filepath, encoding: .utf8) else {
            AppLog.error("找不到報告 HTML 範本檔案 (report_template.html)")
            errorMessage = "找不到報告 HTML 範本檔案。"
            showErrorAlert = true
            isGeneratingPDF = false
            return
        }

        let rmsSVG = generateRMSTrendSVG(
            startStr: startString,
            endStr: endString,
            filterStart: filterStart,
            filterEnd: filterEnd
        )

        let frequencySVG = generatePSDSVG(
            startStr: startString,
            endStr: endString,
            filterStart: filterStart,
            filterEnd: filterEnd
        )

        let htmlContent = templateString
            .replacingOccurrences(of: "{{userName}}", with: userName)
            .replacingOccurrences(of: "{{userBirth}}", with: htmlEscape(userBirth))
            .replacingOccurrences(of: "{{startString}}", with: htmlEscape(startString))
            .replacingOccurrences(of: "{{endString}}", with: htmlEscape(endString))
            .replacingOccurrences(of: "{{rmsTrendSVG}}", with: rmsSVG)
            .replacingOccurrences(of: "{{psdDetailSVG}}", with: frequencySVG)
            .replacingOccurrences(of: "{{tremorEventsRowsHTML}}", with: tremorEventsRowsHTML)
            .replacingOccurrences(of: "{{symptomRowsHTML}}", with: symptomRowsHTML)
            .replacingOccurrences(of: "{{medicationRowsHTML}}", with: medicationRowsHTML)
            .replacingOccurrences(of: "{{vitalsRowsHTML}}", with: vitalsRowsHTML)
            .replacingOccurrences(of: "{{assessmentRowsHTML}}", with: assessmentRowsHTML)
            .replacingOccurrences(of: "{{consultationSectionHTML}}", with: consultationSectionHTML)

        PDFDataGenerator.shared.generatePDFData(from: htmlContent) { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isGeneratingPDF = false

                if let pdfData = data {
                    self.generatedPDFData = pdfData
                    self.showPreviewSheet = true
                } else {
                    AppLog.error("PDF 產生失敗")
                    self.errorMessage = "PDF 產生失敗，請稍後再試。"
                    self.showErrorAlert = true
                }
            }
        }
    }
}
