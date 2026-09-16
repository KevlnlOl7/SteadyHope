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

    /// 上次儲存分析快照之時間戳記，用於限制後端同步頻率
    private var lastAnalysisRecordTime: Date?

    /// 標記是否已綁定硬體資料流管線
    private var isPipelineBound = false

    /// 累積待批次上傳之原始感測數據點緩衝區
    private var rawUploadBuffer: [TremorDataPoint] = []

    /// 觸發原始數據批次上傳之資料筆數門檻值
    private let uploadBatchThreshold = 400

    /// 100 Hz 取樣率下之單筆原始採樣間隔時間（秒）
    private let rawSampleInterval: TimeInterval = 0.01

    /// 台北標準時區實體
    private let taipeiTimeZone = TimeZone(identifier: "Asia/Taipei") ?? .current

    /// 綁定台北時區之日曆實體
    private let calendar: Calendar = {
        var c = Calendar.current
        c.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return c
    }()

    /// 初始化震顫資料檢視模型並注入儲存庫
    /// - Parameter repository: 符合 TremorRepositoryProtocol 之資料儲存庫實體
    init(repository: TremorRepositoryProtocol? = nil) {
        if let repository {
            self.repository = repository
        } else {
            self.repository = TremorRepository(tokenProvider: {
                AuthManager.shared.getToken()
            })
        }
    }

    /// RMS 連續強度走勢圖中之單一資料點模型
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

    /// 截取指定時間點周圍之走勢數據點，提供事件卡片繪製局部走勢，並加入單點防呆避免圖表空白
    /// - Parameters:
    ///   - targetDate: 目標基準時間
    ///   - seconds: 欲向前與向後涵蓋之秒數範圍
    /// - Returns: 符合範圍之時間排序走勢點陣列
    func getHistory(
        surrounding targetDate: Date,
        seconds: TimeInterval = 10
    ) -> [RMSTrendPoint] {
        let matched = rmsTrendHistory.filter {
            abs($0.timestamp.timeIntervalSince(targetDate)) <= seconds
        }

        if !matched.isEmpty {
            return matched.sorted { $0.timestamp < $1.timestamp }
        }

        if let event = tremorEvents.first(where: { abs($0.timestamp.timeIntervalSince(targetDate)) <= 1.0 }) {
            return [
                RMSTrendPoint(
                    timestamp: event.timestamp,
                    timeLabel: event.timeLabel,
                    rmsValue: event.rmsValue,
                    isMotorActive: event.isMotorActive,
                    rawWindowData: event.rawWindowData,
                    userTag: event.userTag,
                    selectedImages: event.selectedImages,
                    isSaved: event.isSaved
                )
            ]
        }

        return []
    }

    /// 從伺服器載入歷史震顫分析紀錄並結合鄰近原始波形建構事件模型
    /// - Parameter matchedHistory: 可供比對之本機 RMS 走勢快取點陣列
    func loadAnalysisEvents(matchedHistory: [RMSTrendPoint] = []) async {
        do {
            let records = try await repository.fetchAnalysisHistory()
            var seenIDs = Set<UUID>()
            var analysisRecords: [TremorEvent] = []

            for record in records.sorted(by: { $0.recordedAt > $1.recordedAt }) {
                guard seenIDs.insert(record.id).inserted else {
                    continue
                }

                let date = record.recordedAt
                let rawTag = record.activityTag.trimmingCharacters(in: .whitespacesAndNewlines)
                let tag = rawTag.isEmpty ? "未標記" : rawTag

                let matchedRaw = matchedHistory.min {
                    abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
                }?
                .rawWindowData ?? []

                guard record.dataValid else {
                    continue
                }

                analysisRecords.append(
                    TremorEvent(
                        id: record.id,
                        timestamp: date,
                        timeLabel: date.toString(format: "yyyy-MM-dd HH:mm:ss"),
                        rmsValue: record.tremorStrengthRmsDps ?? 0.0,
                        dominantFrequency: record.frequencyReliable ? (record.dominantFrequencyHz ?? 0.0) : 0.0,
                        rawWindowData: matchedRaw,
                        isMotorActive: (record.motorOnFraction > 0.0),
                        userTag: tag,
                        isSaved: true
                    )
                )
            }

            tremorEvents = analysisRecords
            lastVibrationDate = "--"
            lastVibrationTime = "--:--"

        } catch {
            AppLog.error("載入分析紀錄失敗: \(error.localizedDescription)")
            tremorEvents = []
            lastVibrationDate = "--"
            lastVibrationTime = "--:--"
        }
    }

    /// 從遠端伺服器載入指定日期的原始感測時序訊號並重建全天連續 RMS 走勢線
    func loadRawDataTrend() async {
        do {
            let timedRawPoints = try await repository.fetchTimedRawDataHistory()
            let sorted = timedRawPoints.sorted { $0.timestamp < $1.timestamp }

            let startOfDay = calendar.startOfDay(for: selectedFilterDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
                ?? startOfDay.addingTimeInterval(24 * 60 * 60)

            let dayPoints = sorted.filter {
                $0.timestamp >= startOfDay && $0.timestamp < endOfDay
            }

            var computedHistory = buildHistoricalTrend(from: dayPoints)

            if computedHistory.isEmpty {
                computedHistory = buildFallbackTrendFromEvents()
            }

            if calendar.isDateInToday(selectedFilterDate),
               let latest = computedHistory.last?.timestamp {
                let livePoints = rmsTrendHistory.filter { $0.timestamp > latest }
                computedHistory.append(contentsOf: livePoints)
            }

            rmsTrendHistory = deduplicateTrendPoints(computedHistory).sorted {
                $0.timestamp < $1.timestamp
            }

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

    /// 根據連續原始資料點陣列以滑動視窗計算歷史 RMS 走勢點
    /// - Parameter points: 帶有時間戳記之原始感測資料陣列
    /// - Returns: 計算產生之 RMS 走勢點陣列
    private func buildHistoricalTrend(from points: [TremorTimedRawPoint]) -> [RMSTrendPoint] {
        let windowSize = 400
        let strideSize = 50

        guard points.count >= windowSize else {
            return []
        }

        var result: [RMSTrendPoint] = []
        result.reserveCapacity(max(points.count / strideSize, 1))

        var startIndex = 0

        while startIndex + windowSize <= points.count {
            let endIndex = startIndex + windowSize
            let window = Array(points[startIndex..<endIndex])
            let rawWindow = window.map(\.point)
            let resultValue = analyzer.analyze(data: rawWindow)

            let timestamp = window.last?.timestamp ?? points[endIndex - 1].timestamp

            guard resultValue.dataValid,
                  resultValue.tremorStrengthRmsDps.isFinite,
                  !resultValue.tremorStrengthRmsDps.isNaN else {
                startIndex += strideSize
                continue
            }

            let latest50 = rawWindow.suffix(50)
            let motorActive = latest50.contains { $0.motorEnabled == 1 }

            result.append(
                RMSTrendPoint(
                    timestamp: timestamp,
                    timeLabel: timestamp.toString(format: "HH:mm:ss"),
                    rmsValue: resultValue.tremorStrengthRmsDps,
                    isMotorActive: motorActive,
                    rawWindowData: rawWindow
                )
            )

            startIndex += strideSize
        }

        let tailStart = points.count - windowSize
        if tailStart >= 0 {
            let tailTimestamp = points.last!.timestamp
            let alreadyExists = result.contains { $0.timestamp == tailTimestamp }

            if !alreadyExists {
                let window = Array(points[tailStart..<points.count])
                let rawWindow = window.map(\.point)
                let resultValue = analyzer.analyze(data: rawWindow)

                if resultValue.dataValid,
                   resultValue.tremorStrengthRmsDps.isFinite,
                   !resultValue.tremorStrengthRmsDps.isNaN {
                    let latest50 = rawWindow.suffix(50)
                    let motorActive = latest50.contains { $0.motorEnabled == 1 }

                    result.append(
                        RMSTrendPoint(
                            timestamp: tailTimestamp,
                            timeLabel: tailTimestamp.toString(format: "HH:mm:ss"),
                            rmsValue: resultValue.tremorStrengthRmsDps,
                            isMotorActive: motorActive,
                            rawWindowData: rawWindow
                        )
                    )
                }
            }
        }

        return result.sorted { $0.timestamp < $1.timestamp }
    }

    /// 當缺乏密集原始訊號時，從事件快照資料建構備援之走勢點陣列
    /// - Returns: 備援之 RMS 走勢點陣列
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

    /// 對走勢點進行 0.5 秒時間窗口去重，避免相同時間點過度密集繪製
    /// - Parameter points: 待處理之走勢點陣列
    /// - Returns: 去重後之走勢點陣列
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

    /// 從連續走勢快取中回補事件紀錄缺失之原始視窗訊號
    private func backfillEventRawWindowData() async {
        guard !tremorEvents.isEmpty, !rmsTrendHistory.isEmpty else {
            return
        }

        tremorEvents = tremorEvents.map { event in
            guard event.rawWindowData.isEmpty else {
                return event
            }

            let matched = rmsTrendHistory.min {
                abs($0.timestamp.timeIntervalSince(event.timestamp)) < abs($1.timestamp.timeIntervalSince(event.timestamp))
            }?
            .rawWindowData ?? []

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

    /// 載入當前選定篩選日期之完整震顫歷史紀錄與走勢資料
    func loadTremorHistory() async {
        await loadTremorHistory(for: selectedFilterDate)
    }

    /// 依指定日期依序載入分析事件與原始數據走勢
    /// - Parameter date: 查詢目標日期實體
    private func loadTremorHistory(for date: Date) async {
        selectedPoint = nil
        await loadAnalysisEvents(matchedHistory: rmsTrendHistory)

        guard calendar.isDate(date, inSameDayAs: selectedFilterDate) else {
            return
        }

        await loadRawDataTrend()
    }

    /// 綁定藍牙數據流管線，接管即時資料更新、批次上傳與即時分析排程
    /// - Parameter pipeline: 藍牙端傳入之 TremorPipeline 實體
    func bindPipeline(_ pipeline: TremorPipeline) {
        guard !isPipelineBound else {
            return
        }

        isPipelineBound = true

        pipeline.onStatusChanged = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.statusText = status
            }
        }

        pipeline.onNewRawBatchAppended = { [weak self] newPoints in
            Task { @MainActor [weak self] in
                guard let self, !newPoints.isEmpty else { return }

                self.rawUploadBuffer.append(contentsOf: newPoints)

                while self.rawUploadBuffer.count >= self.uploadBatchThreshold {
                    let batch = Array(self.rawUploadBuffer.prefix(self.uploadBatchThreshold))
                    self.rawUploadBuffer.removeFirst(self.uploadBatchThreshold)

                    let sessionId = self.currentSessionId
                    let baseDate = batch.first?.recordedAt ?? Date()
                    let repository = self.repository

                    Task {
                        do {
                            try await repository.syncRawData(
                                sessionId: sessionId,
                                rawPoints: batch,
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
                guard !window400Data.isEmpty else { return }
                
                let sampleTime = window400Data.last?.recordedAt ?? Date()
                let timeStr = sampleTime.toString(format: "HH:mm:ss")
                
                let latest50 = Array(window400Data.suffix(50))
                let motorFraction: Double?
                let isMotorActive: Bool
                
                if latest50.count == 50,
                   latest50.allSatisfy({ $0.motorEnabled == 0 || $0.motorEnabled == 1 }) {
                    let activeCount = latest50.filter { $0.motorEnabled == 1 }.count
                    motorFraction = Double(activeCount) / 50.0
                    isMotorActive = activeCount > 0
                } else {
                    motorFraction = nil
                    isMotorActive = false
                }
                
                if self.selectedPoint == nil {
                    if result.dataValid {
                        self.tremorStrengthText = String(format: "%.2f", result.tremorStrengthRmsDps)
                        
                        if result.frequencyReliable,
                           let frequency = result.dominantFrequencyHz,
                           frequency.isFinite {
                            self.dominantFrequencyText = String(format: "%.2f Hz", frequency)
                        } else {
                            self.dominantFrequencyText = "--"
                        }
                    } else {
                        self.tremorStrengthText = "資料不足"
                        self.dominantFrequencyText = "--"
                    }
                }
                
                if result.dataValid {
                    var liveCalendar = Calendar.current
                    liveCalendar.timeZone = self.taipeiTimeZone
                    
                    if liveCalendar.isDateInToday(self.selectedFilterDate) {
                        let newPoint = RMSTrendPoint(
                            timestamp: sampleTime,
                            timeLabel: timeStr,
                            rmsValue: result.tremorStrengthRmsDps,
                            isMotorActive: isMotorActive,
                            rawWindowData: window400Data
                        )
                        
                        if let lastTime = self.rmsTrendHistory.last?.timestamp {
                            if sampleTime.timeIntervalSince(lastTime) > 0 {
                                self.rmsTrendHistory.append(newPoint)
                            }
                        } else {
                            self.rmsTrendHistory.append(newPoint)
                        }
                        
                        let maxLivePoints = 24 * 60 * 60 * 2
                        if self.rmsTrendHistory.count > maxLivePoints {
                            self.rmsTrendHistory.removeFirst(self.rmsTrendHistory.count - maxLivePoints)
                        }
                    }
                }
                
                guard result.dataValid else { return }
                
                let now = Date()
                let shouldSave = self.lastAnalysisRecordTime == nil
                || now.timeIntervalSince(self.lastAnalysisRecordTime!) >= 3.0
                
                guard shouldSave else { return }
                self.lastAnalysisRecordTime = now
                
                let sessionId = self.currentSessionId
                let analysisRecord = TremorAnalysisRecordDTO(
                    id: UUID(),
                    sessionId: sessionId,
                    recordedAt: sampleTime,
                    dominantFrequencyHz: result.frequencyReliable ? result.dominantFrequencyHz : nil,
                    tremorStrengthRmsDps: result.dataValid ? result.tremorStrengthRmsDps : nil,
                    motorOnFraction: motorFraction ?? 0.0,
                    dataValid: true,
                    frequencyReliable: result.frequencyReliable,
                    activityTag: self.selectedActivityTag,
                    note: nil
                )
                
                // 同步加入本機事件清單，確保即時量測時圖表立即出現橘點與更新下方列表
                let liveEvent = TremorEvent(
                    id: analysisRecord.id,
                    timestamp: sampleTime,
                    timeLabel: timeStr,
                    rmsValue: result.tremorStrengthRmsDps,
                    dominantFrequency: result.frequencyReliable ? (result.dominantFrequencyHz ?? 0.0) : 0.0,
                    rawWindowData: window400Data,
                    isMotorActive: isMotorActive,
                    motorOnFraction: motorFraction,
                    userTag: self.selectedActivityTag,
                    isSaved: true
                )
                self.tremorEvents.insert(liveEvent, at: 0)
                
                let repository = self.repository
                Task {
                    do {
                        try await repository.syncAnalysisResult(record: analysisRecord)
                    } catch {
                        AppLog.error("分析紀錄上傳失敗: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// 儲存特定事件之活動情境標籤與照片並同步至後端資料庫
    /// - Parameter event: 包含最新標籤資訊之 TremorEvent 實體
    /// - Returns: 同步成功回傳 true，發生錯誤回傳 false
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
            AppLog.error("分析紀錄標記失敗: \(error.localizedDescription)")
            return false
        }
    }

    /// 依據當前選定點或最新資料更新儀表板顯示數值與頻率文字
    private func updateDashboard() {
        guard let targetPoint = selectedPoint ?? rmsTrendHistory.last else {
            dominantFrequencyText = "--"
            tremorStrengthText = "0.00"
            return
        }

        guard targetPoint.rmsValue.isFinite, !targetPoint.rmsValue.isNaN else {
            dominantFrequencyText = "--"
            tremorStrengthText = "資料不足"
            return
        }

        tremorStrengthText = String(format: "%.2f", targetPoint.rmsValue)

        if !targetPoint.rawWindowData.isEmpty {
            let result = analyzer.analyze(data: targetPoint.rawWindowData)
            if result.frequencyReliable, let frequency = result.dominantFrequencyHz {
                dominantFrequencyText = String(format: "%.2f Hz", frequency)
            } else {
                dominantFrequencyText = "--"
            }
        } else {
            dominantFrequencyText = "--"
        }
    }

    /// 計算特定 400 筆感測視窗之功率譜密度（PSD）離散點陣列
    /// - Parameter windowData: 包含 400 筆三軸角速度之原始數據陣列
    /// - Returns: 0 至 15 Hz 區間之頻譜能量點陣列
    func calculatePSDData(from windowData: [TremorDataPoint]) -> [PSDPoint] {
        guard windowData.count == 400 else {
            return []
        }

        let gyroX = windowData.map { $0.gyroXDps }
        let gyroY = windowData.map { $0.gyroYDps }
        let gyroZ = windowData.map { $0.gyroZDps }

        let psdX = analyzer.calculatePSD(signal: gyroX)
        let psdY = analyzer.calculatePSD(signal: gyroY)
        let psdZ = analyzer.calculatePSD(signal: gyroZ)

        guard psdX.count >= 61, psdY.count >= 61, psdZ.count >= 61 else {
            return []
        }

        var points: [PSDPoint] = []
        let df = 0.25

        for k in 0...60 {
            let totalPower = psdX[k] + psdY[k] + psdZ[k]

            guard totalPower.isFinite, !totalPower.isNaN else {
                continue
            }

            points.append(
                PSDPoint(
                    frequencyHz: Double(k) * df,
                    power: totalPower
                )
            )
        }

        return points
    }

    /// 提供舊版本畫面呼叫之相容性介面，重設最後震顫時間字串
    /// - Parameter date: 觸發震顫之日期物件
    public func updateLastVibrationTime(from date: Date) {
        lastVibrationDate = "--"
        lastVibrationTime = "--:--"
    }
}
