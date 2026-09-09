import Combine
import Foundation
import UIKit

@MainActor
final class DataViewModel: ObservableObject {
    static let shared = DataViewModel()

    /// 震顫頻譜演算法分析器實體
    let analyzer = TremorAnalyzer()

    /// 後端震顫資料儲存庫協定實體
    private let repository: TremorRepositoryProtocol

    /// 當前量測會話之 UUID 字串識別碼
    var currentSessionId: String = UUID().uuidString

    /// 提供使用者挑選之情境標籤預設選項清單
    let activityOptions = ["休息", "吃飯", "喝水", "寫字", "走路", "服藥後"]

    /// 首頁看板主要震顫頻率格式化顯示文字
    @Published var dominantFrequencyText: String = "--"

    /// 首頁看板震顫強度 RMS 格式化顯示文字
    @Published var tremorStrengthText: String = "0.00"

    /// 硬體連線與管線資料運作狀態文字
    @Published var statusText: String = "資料正常"

    /// 最近一次顯著震顫事件日期標籤
    @Published var lastVibrationDate: String = "--"

    /// 最近一次顯著震顫事件時間標籤
    @Published var lastVibrationTime: String = "--:--"

    /// 保存當前選定日期之 RMS 走勢取樣點陣列（歷史資料為 5 秒一點，即時 BLE 為 0.5 秒一點）
    @Published var rmsTrendHistory: [RMSTrendPoint] = []

    /// 圖表手勢點選命中之單一數據點，變更時連動更新看板顯示
    @Published var selectedPoint: RMSTrendPoint? {
        didSet {
            updateDashboard()
        }
    }

    /// 當前選定之情境活動標籤
    @Published var selectedActivityTag: String = "休息"

    /// 顯著震顫事件模型陣列
    @Published var tremorEvents: [TremorEvent] = []

    /// 於列表視圖中展開詳細卡片之事件 UUID
    @Published var expandedEventID: UUID? = nil

    /// 圖表與列表檢視之篩選目標日期，變更時自動重設選取點並非同步載入當日歷史紀錄
    @Published var selectedFilterDate: Date = Date() {
        didSet {
            let date = selectedFilterDate
            Task { [weak self] in
                guard let self else { return }
                self.selectedPoint = nil
                self.expandedEventID = nil
                await self.loadTremorHistory(for: date)
            }
        }
    }

    /// 上一次捕捉顯著震顫事件之冷卻時間戳記
    private var lastCapturedTime: Date?

    /// 標記是否已完成藍牙管線閉包綁定
    private var isPipelineBound: Bool = false

    /// 原始資料上傳佇列暫存緩衝區
    private var rawUploadBuffer: [TremorDataPoint] = []

    /// 原始資料批次上傳之起始基準時間
    private var rawUploadBufferBaseDate: Date? = nil

    /// 原始資料達到此門檻點數時觸發上傳流程（固定為 400 筆）
    private let uploadBatchThreshold = 400

    /// 硬體取樣時序間隔（以 50 Hz 計算，即每筆取樣間隔 20 毫秒）
    private let rawSampleInterval: TimeInterval = 0.02

    /// 台北標準時區實體
    private let taipeiTimeZone = TimeZone(identifier: "Asia/Taipei") ?? .current

    /// 預設台北時區之日曆實體
    private let calendar: Calendar = {
        var c = Calendar.current
        c.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return c
    }()

    /// 初始化 DataViewModel 實體
    /// - Parameter repository: 震顫資料儲存庫實體，若未傳入則預設使用內建之 TremorRepository
    init(repository: TremorRepositoryProtocol? = nil) {
        if let repo = repository {
            self.repository = repo
        } else {
            self.repository = TremorRepository(
                tokenProvider: {
                    AuthManager.shared.getToken()
                }
            )
        }
    }

    /// RMS 走勢圖表渲染用之單一數據點模型
    struct RMSTrendPoint: Identifiable {
        /// 數據點唯一識別碼
        let id = UUID()

        /// 取樣計算時間戳記
        let timestamp: Date

        /// 格式化時間文字標籤（例如：HH:mm:ss）
        let timeLabel: String

        /// 4-6 Hz 核心頻段之均方根震顫強度數值（單位：deg/s）
        let rmsValue: Double

        /// 事件發生期間抑震馬達是否處於致動狀態
        let isMotorActive: Bool

        /// 400 筆分析視窗原始慣性測量數據點陣列
        let rawWindowData: [TremorDataPoint]

        /// 使用者自訂情境標籤
        var userTag: String = ""

        /// 使用者附加之佐證照片陣列
        var selectedImages: [UIImage] = []

        /// 標記此資料點是否已儲存歸檔
        var isSaved: Bool = false
    }

    /// 功率譜密度（PSD）圖表渲染用之單一頻率能量點模型
    struct PSDPoint: Identifiable {
        /// 頻率點唯一識別碼
        let id = UUID()

        /// 頻率座標（單位：Hz）
        let frequencyHz: Double

        /// 該頻率點之功率能量密度（單位：(deg/s)^2/Hz）
        let power: Double
    }

    /// 取得當前即時或選取點之均方根震顫強度（RMS）
    var currentRMS: Double {
        if let selectedPoint {
            return selectedPoint.rmsValue
        }
        return rmsTrendHistory.last?.rmsValue ?? (Double(tremorStrengthText) ?? 0.0)
    }

    /// 依據選定篩選日期過濾後之顯著震顫事件陣列
    var filteredEvents: [TremorEvent] {
        tremorEvents.filter { calendar.isDate($0.timestamp, inSameDayAs: selectedFilterDate) }
    }

    /// 計算非今日且未填寫情境標籤之歷史顯著震顫事件總數
    var pastUnlabeledCount: Int {
        tremorEvents.filter { event in
            !calendar.isDateInToday(event.timestamp) &&
            (event.userTag.isEmpty || event.userTag == "未標記")
        }.count
    }

    /// 依據走勢歷程動態計算圖表 Y 軸之安全上限值
    /// - Parameter history: 欲計算之 RMS 走勢資料點陣列
    /// - Returns: 圖表 Y 軸顯示之上限數值
    func calculateSafeMaxY(from history: [RMSTrendPoint]) -> Double {
        let values = history.map(\.rmsValue).filter { $0.isFinite && !$0.isNaN }
        return max(0.5, (values.max() ?? 0.5) * 1.2)
    }

    /// 截取指定時間點前後特定秒數區間內之 RMS 歷程資料點
    /// - Parameters:
    ///   - targetDate: 目標時間點
    ///   - seconds: 前後截取之時間半徑（秒），預設為 3 秒
    /// - Returns: 截取範圍內之走勢數據點陣列
    func getHistory(surrounding targetDate: Date, seconds: TimeInterval = 3) -> [RMSTrendPoint] {
        rmsTrendHistory.filter {
            abs($0.timestamp.timeIntervalSince(targetDate)) <= seconds
        }
    }

    /// 從後端非同步載入歷史顯著分析事件，並與本地走勢原始取樣比對補齊視窗資料
    /// - Parameter matchedHistory: 提供比對原始取樣視窗之走勢點陣列，預設為空陣列
    func loadAnalysisEvents(matchedHistory: [RMSTrendPoint] = []) async {
        do {
            let records = try await repository.fetchAnalysisHistory()
            var seenIDs = Set<UUID>()
            var uniqueEvents: [TremorEvent] = []

            for record in records.sorted(by: { $0.recordedAt > $1.recordedAt }) {
                guard seenIDs.insert(record.id).inserted else { continue }

                let date = record.recordedAt
                let rawTag = record.activityTag.trimmingCharacters(in: .whitespacesAndNewlines)
                let tag = rawTag.isEmpty ? "未標記" : rawTag
                let matchedRaw = matchedHistory.min {
                    abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
                }?.rawWindowData ?? []

                uniqueEvents.append(
                    TremorEvent(
                        id: record.id,
                        timestamp: date,
                        timeLabel: date.toString(format: "yyyy-MM-dd HH:mm:ss"),
                        rmsValue: record.tremorStrengthRmsDps ?? 0.0,
                        dominantFrequency: record.dominantFrequencyHz ?? 0.0,
                        rawWindowData: matchedRaw,
                        isMotorActive: record.motorOnFraction > 0.0,
                        userTag: tag,
                        isSaved: true
                    )
                )
            }

            tremorEvents = uniqueEvents

            if let latestEvent = tremorEvents.first {
                updateLastVibrationTime(from: latestEvent.timestamp)
            } else {
                lastVibrationDate = "--"
                lastVibrationTime = "--:--"
            }
        } catch {
            AppLog.error("載入高震顫事件失敗: \(error.localizedDescription)")
            tremorEvents = []
            lastVibrationDate = "--"
            lastVibrationTime = "--:--"
        }
    }

    /// 依據後端取回之時序原始取樣點，重建選定日期 24 小時之連續走勢資料
    func loadRawDataTrend() async {
        do {
            let timedRawPoints = try await repository.fetchTimedRawDataHistory()
            let sorted = timedRawPoints.sorted { $0.timestamp < $1.timestamp }
            let startOfDay = calendar.startOfDay(for: selectedFilterDate)
            let endOfDay = startOfDay.addingTimeInterval(24 * 60 * 60)

            let dayPoints = sorted.filter {
                $0.timestamp >= startOfDay && $0.timestamp < endOfDay
            }

            var computedHistory = buildHistoricalTrend(from: dayPoints)

            if computedHistory.isEmpty {
                computedHistory = buildFallbackTrendFromEvents()
            }

            if calendar.isDateInToday(selectedFilterDate), let historicalLatest = computedHistory.last?.timestamp {
                let livePoints = rmsTrendHistory.filter { $0.timestamp > historicalLatest }
                computedHistory.append(contentsOf: livePoints)
            }

            rmsTrendHistory = deduplicateTrendPoints(computedHistory)
                .sorted { $0.timestamp < $1.timestamp }

            await backfillEventRawWindowData()
            selectedPoint = nil
            updateDashboard()
        } catch {
            AppLog.error("載入原始走勢失敗: \(error.localizedDescription)")
            if rmsTrendHistory.isEmpty {
                rmsTrendHistory = buildFallbackTrendFromEvents()
            }
        }
    }

    /// 將連續原始數據依滑動視窗計算為歷史走勢點陣列
    /// - Parameter points: 帶有時間戳記之原始資料點陣列
    /// - Returns: 計算完成之 RMSTrendPoint 走勢點陣列
    private func buildHistoricalTrend(from points: [TremorTimedRawPoint]) -> [RMSTrendPoint] {
        guard points.count >= 400 else { return [] }

        let windowSize = 400
        let strideSize = 500
        var result: [RMSTrendPoint] = []
        result.reserveCapacity(points.count / strideSize + 2)

        var startIndex = 0
        while startIndex + windowSize <= points.count {
            let window = Array(points[startIndex..<(startIndex + windowSize)])
            let resultValue = analyzer.analyze(data: window.map(\.point))
            let timestamp = points[startIndex + windowSize - 1].timestamp
            let isMotor = window.suffix(50).contains { $0.point.motorEnabled == 1 }

            if resultValue.tremorStrengthRmsDps.isFinite {
                result.append(
                    RMSTrendPoint(
                        timestamp: timestamp,
                        timeLabel: timestamp.toString(format: "HH:mm:ss"),
                        rmsValue: resultValue.tremorStrengthRmsDps,
                        isMotorActive: isMotor,
                        rawWindowData: window.map(\.point)
                    )
                )
            }

            startIndex += strideSize
        }

        let tailStart = max(0, points.count - windowSize)
        if result.last?.timestamp != points[tailStart + windowSize - 1].timestamp {
            let window = Array(points[tailStart..<points.count])
            let resultValue = analyzer.analyze(data: window.map(\.point))
            let timestamp = points.last!.timestamp
            let isMotor = window.suffix(50).contains { $0.point.motorEnabled == 1 }

            if resultValue.tremorStrengthRmsDps.isFinite {
                result.append(
                    RMSTrendPoint(
                        timestamp: timestamp,
                        timeLabel: timestamp.toString(format: "HH:mm:ss"),
                        rmsValue: resultValue.tremorStrengthRmsDps,
                        isMotorActive: isMotor,
                        rawWindowData: window.map(\.point)
                    )
                )
            }
        }

        return result.sorted { $0.timestamp < $1.timestamp }
    }

    /// 當缺乏連續原始訊號時，以已記錄之震顫事件建構替代用走勢資料
    /// - Returns: 以事件為基準之 RMSTrendPoint 陣列
    private func buildFallbackTrendFromEvents() -> [RMSTrendPoint] {
        filteredEvents.map {
            RMSTrendPoint(
                timestamp: $0.timestamp,
                timeLabel: $0.timestamp.toString(format: "HH:mm:ss"),
                rmsValue: $0.rmsValue,
                isMotorActive: $0.isMotorActive,
                rawWindowData: $0.rawWindowData,
                userTag: $0.userTag,
                selectedImages: $0.selectedImages,
                isSaved: $0.isSaved
            )
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    /// 過濾走勢陣列中時間戳記過於接近之重複點
    /// - Parameter points: 待去重之 RMSTrendPoint 陣列
    /// - Returns: 去除重複後之 RMSTrendPoint 陣列
    private func deduplicateTrendPoints(_ points: [RMSTrendPoint]) -> [RMSTrendPoint] {
        var result: [RMSTrendPoint] = []
        var seenBuckets = Set<Int64>()

        for point in points.sorted(by: { $0.timestamp < $1.timestamp }) {
            let bucket = Int64((point.timestamp.timeIntervalSince1970 * 2.0).rounded(.toNearestOrAwayFromZero))
            if seenBuckets.insert(bucket).inserted {
                result.append(point)
            }
        }
        return result
    }

    /// 從走勢紀錄中尋找最接近之分析視窗原始取樣，回填至缺少 rawWindowData 之震顫事件中
    private func backfillEventRawWindowData() async {
        guard !tremorEvents.isEmpty, !rmsTrendHistory.isEmpty else { return }

        tremorEvents = tremorEvents.map { event in
            guard event.rawWindowData.isEmpty else { return event }
            let matched = rmsTrendHistory.min {
                abs($0.timestamp.timeIntervalSince(event.timestamp)) <
                abs($1.timestamp.timeIntervalSince(event.timestamp))
            }?.rawWindowData ?? []

            return TremorEvent(
                id: event.id,
                timestamp: event.timestamp,
                timeLabel: event.timeLabel,
                rmsValue: event.rmsValue,
                dominantFrequency: event.dominantFrequency,
                rawWindowData: matched,
                isMotorActive: event.isMotorActive,
                userTag: event.userTag,
                selectedImages: event.selectedImages,
                isSaved: event.isSaved
            )
        }
    }

    /// 對外統一載入震顫歷史資料之進入點（針對當前選定篩選日期執行）
    func loadTremorHistory() async {
        await loadTremorHistory(for: selectedFilterDate)
    }

    /// 載入特定日期之震顫分析事件與走勢紀錄
    /// - Parameter date: 欲載入資料之目標日期
    private func loadTremorHistory(for date: Date) async {
        selectedPoint = nil
        await loadAnalysisEvents(matchedHistory: rmsTrendHistory)
        guard calendar.isDate(date, inSameDayAs: selectedFilterDate) else { return }
        await loadRawDataTrend()
    }

    /// 綁定藍牙數據管線之各項事件回呼閉包
    /// - Parameter pipeline: 藍牙資料串流管線實體
    func bindPipeline(_ pipeline: TremorPipeline) {
        guard !isPipelineBound else { return }
        isPipelineBound = true

        pipeline.onStatusChanged = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.statusText = status
            }
        }

        pipeline.onNewRawBatchAppended = { [weak self] new50Points in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !new50Points.isEmpty else { return }

                if self.rawUploadBuffer.isEmpty {
                    let batchReceivedAt = Date()
                    let firstSampleOffset = Double(max(new50Points.count - 1, 0)) * self.rawSampleInterval
                    self.rawUploadBufferBaseDate = batchReceivedAt.addingTimeInterval(-firstSampleOffset)
                }

                self.rawUploadBuffer.append(contentsOf: new50Points)

                while self.rawUploadBuffer.count >= self.uploadBatchThreshold {
                    let batchToUpload = Array(self.rawUploadBuffer.prefix(self.uploadBatchThreshold))
                    self.rawUploadBuffer.removeFirst(self.uploadBatchThreshold)

                    let baseDate = self.rawUploadBufferBaseDate
                        ?? Date().addingTimeInterval(-Double(max(batchToUpload.count - 1, 0)) * self.rawSampleInterval)

                    if self.rawUploadBuffer.isEmpty {
                        self.rawUploadBufferBaseDate = nil
                    } else {
                        self.rawUploadBufferBaseDate = baseDate.addingTimeInterval(
                            Double(batchToUpload.count) * self.rawSampleInterval
                        )
                    }

                    Task {
                        do {
                            try await self.repository.syncRawData(
                                sessionId: self.currentSessionId,
                                rawPoints: batchToUpload,
                                baseDate: baseDate
                            )
                        } catch {
                            AppLog.error("原始震顫數據批次上傳失敗: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }

        pipeline.onAnalysisUpdated = { [weak self] result, window400Data in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let now = Date()
                let rms = result.tremorStrengthRmsDps
                let timeStr = now.toString(format: "HH:mm:ss")
                let isMotor = window400Data.suffix(50).contains(where: { $0.motorEnabled == 1 })

                AppLog.debug("收到分析點 - RMS: \(rms), Freq: \(result.dominantFrequencyHz ?? 0)")

                if self.selectedPoint == nil {
                    if result.dataValid {
                        self.tremorStrengthText = String(format: "%.2f", rms)

                        if result.frequencyReliable,
                           let freq = result.dominantFrequencyHz,
                           freq.isFinite {
                            self.dominantFrequencyText = String(format: "%.2f Hz", freq)
                        } else {
                            self.dominantFrequencyText = "--"
                        }
                    } else {
                        self.tremorStrengthText = "0.00"
                        self.dominantFrequencyText = "資料不足"
                    }
                }

                if result.dataValid {
                    var calendar = Calendar.current
                    calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current

                    if calendar.isDateInToday(self.selectedFilterDate) {
                        let newPoint = RMSTrendPoint(
                            timestamp: now,
                            timeLabel: timeStr,
                            rmsValue: rms,
                            isMotorActive: isMotor,
                            rawWindowData: window400Data
                        )

                        if let lastTime = self.rmsTrendHistory.last?.timestamp {
                            if now.timeIntervalSince(lastTime) > 0 {
                                self.rmsTrendHistory.append(newPoint)
                            }
                        } else {
                            self.rmsTrendHistory.append(newPoint)
                        }

                        let maxLiveTrendPoints = 24 * 60 * 60 * 2
                        if self.rmsTrendHistory.count > maxLiveTrendPoints {
                            self.rmsTrendHistory.removeFirst(self.rmsTrendHistory.count - maxLiveTrendPoints)
                        }
                    }
                }

                if result.dataValid {
                    let isCooldownPassed = self.lastCapturedTime == nil || now.timeIntervalSince(self.lastCapturedTime!) > 3.0

                    if isCooldownPassed {
                        self.lastCapturedTime = now

                        var newEvent = TremorEvent(
                            id: UUID(),
                            timestamp: now,
                            timeLabel: timeStr,
                            rmsValue: rms,
                            dominantFrequency: result.dominantFrequencyHz ?? 0.0,
                            rawWindowData: window400Data,
                            isMotorActive: isMotor
                        )
                        newEvent.userTag = "未標記"
                        newEvent.isSaved = true

                        self.tremorEvents.insert(newEvent, at: 0)
                        self.updateLastVibrationTime(from: now)

                        Task { [weak self, currentSessionId = self.currentSessionId] in
                            do {
                                try await self?.repository.syncEventAsAnalysisRecord(
                                    event: newEvent,
                                    sessionId: currentSessionId
                                )
                            } catch {
                                AppLog.error("BLE 上傳失敗: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
        }
    }

    /// 儲存指定震顫事件的情境標籤與附加照片至伺服器並更新本地狀態
    /// - Parameter event: 欲歸檔之震顫事件模型
    /// - Returns: 若同步儲存成功則回傳 true，失敗則回傳 false
    func saveTremorEvent(_ event: TremorEvent) async -> Bool {
        guard let index = tremorEvents.firstIndex(where: { $0.id == event.id }) else {
            return false
        }

        var eventToSave = event
        let trimmedTag = event.userTag.trimmingCharacters(in: .whitespacesAndNewlines)
        eventToSave.userTag = trimmedTag.isEmpty ? "未標記" : trimmedTag

        do {
            try await repository.syncEventAsAnalysisRecord(
                event: eventToSave,
                sessionId: currentSessionId
            )
            tremorEvents[index].isSaved = true
            tremorEvents[index].userTag = eventToSave.userTag
            tremorEvents[index].selectedImages = eventToSave.selectedImages
            return true
        } catch {
            AppLog.error("震顫事件標記失敗: \(error.localizedDescription)")
            return false
        }
    }

    /// 依據當前選取點或最新數據點更新首頁儀表板之強度與頻率文字
    private func updateDashboard() {
        guard let targetPoint = selectedPoint ?? rmsTrendHistory.last else {
            self.dominantFrequencyText = "--"
            self.tremorStrengthText = "0.00"
            return
        }

        self.tremorStrengthText = String(format: "%.2f", targetPoint.rmsValue)

        if !targetPoint.rawWindowData.isEmpty {
            let res = analyzer.analyze(data: targetPoint.rawWindowData)
            if res.frequencyReliable, let freq = res.dominantFrequencyHz {
                self.dominantFrequencyText = String(format: "%.2f Hz", freq)
            } else {
                self.dominantFrequencyText = "--"
            }
        } else {
            self.dominantFrequencyText = "--"
        }
    }

    /// 將 400 筆原始三軸角速度數據點轉換為頻譜密度分析點陣列
    /// - Parameter windowData: 400 筆原始取樣資料點
    /// - Returns: 計算完成之 PSDPoint 陣列
    func calculatePSDData(from windowData: [TremorDataPoint]) -> [PSDPoint] {
        guard windowData.count == 400 else { return [] }

        let gyroX = windowData.map { $0.gyroXDps }
        let gyroY = windowData.map { $0.gyroYDps }
        let gyroZ = windowData.map { $0.gyroZDps }

        let psdX = analyzer.calculatePSD(signal: gyroX)
        let psdY = analyzer.calculatePSD(signal: gyroY)
        let psdZ = analyzer.calculatePSD(signal: gyroZ)

        var points = [PSDPoint]()
        let df = 0.25
        let maxBin = min(60, psdX.count)

        for k in 0..<maxBin {
            let totalPower = psdX[k] + psdY[k] + psdZ[k]
            points.append(PSDPoint(frequencyHz: Double(k) * df, power: totalPower))
        }
        return points
    }

    /// 依據事件時間戳記更新最後震顫發作之日期與時間文字標籤
    /// - Parameter date: 事件時間戳記
    public func updateLastVibrationTime(from date: Date) {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current

        if calendar.isDateInToday(date) {
            self.lastVibrationDate = "今天"
        } else if calendar.isDateInYesterday(date) {
            self.lastVibrationDate = "昨天"
        } else {
            self.lastVibrationDate = date.toString(format: "yyyy/MM/dd")
        }
        self.lastVibrationTime = date.toString(format: "HH:mm")
    }
}
