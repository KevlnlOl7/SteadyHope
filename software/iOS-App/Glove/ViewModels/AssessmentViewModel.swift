import Combine
import SwiftUI

@MainActor
final class AssessmentViewModel: ObservableObject {
    @Published var selectedAnswers: [Int: AssessmentOption] = [:]

    /// 問卷提交狀態與結果提示控制
    @Published var isSubmitting: Bool = false
    @Published var showSuccessAlert: Bool = false
    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String? = nil

    /// 歷史評估紀錄資料（依日期分組）與載入狀態
    @Published var groupedHistoryRecords: [DailyAssessmentGroup] = []
    @Published var isLoadingHistory: Bool = false

    /// 今日評估是否已填寫狀態
    @Published var hasFilledToday: Bool = false

    /// 存在評估紀錄的所有日期字串集合 (yyyy-MM-dd)
    @Published var availableDateStrings: Set<String> = []

    /// 情緒心理層面指標之加總總分
    var moodScore: Int {
        AssessmentBank.questions
            .filter { $0.section == .mood }
            .compactMap { selectedAnswers[$0.id]?.score }
            .reduce(0, +)
    }

    /// 日常生活活動能力 (ADL) 指標之加總總分
    var adlScore: Int {
        AssessmentBank.questions
            .filter { $0.section == .adl }
            .compactMap { selectedAnswers[$0.id]?.score }
            .reduce(0, +)
    }

    /// 動作功能運動障礙指標之加總總分
    var motorScore: Int {
        AssessmentBank.questions
            .filter { $0.section == .motor }
            .compactMap { selectedAnswers[$0.id]?.score }
            .reduce(0, +)
    }

    /// 整份問卷之綜合累計總分（包含情緒、日常生活與動作功能）
    var totalScore: Int {
        moodScore + adlScore + motorScore
    }

    /// 檢查今日是否已存在評估紀錄
    func checkTodayAssessmentStatus() async {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: Date())

        do {
            let records = try await AssessmentRepository.shared.fetchAssessment(dateString: todayStr)
            self.hasFilledToday = !records.isEmpty
        } catch {
            self.hasFilledToday = false
        }
    }

    /// 載入所有存在紀錄的日期集合，供日曆篩選禁用非紀錄日期
    func fetchAvailableRecordDates() async {
        do {
            let records = try await AssessmentRepository.shared.fetchAssessment(dateString: nil)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dates = records.map { formatter.string(from: $0.date) }
            self.availableDateStrings = Set(dates)
        } catch {
            self.availableDateStrings = []
        }
    }

    /// 彙整已填寫之各項指標答案並向伺服器非同步提交每日健康評估資料
    func submitAssessment() async {
        guard !selectedAnswers.isEmpty else {
            self.errorMessage = "請至少填寫一項評估內容"
            self.showErrorAlert = true
            return
        }

        self.isSubmitting = true

        let detailsDTO: [AssessmentAnswerDetailDTO] =
            AssessmentBank.questions.compactMap { question in
                guard let option = selectedAnswers[question.id] else {
                    return nil
                }
                return AssessmentAnswerDetailDTO(
                    questionId: question.id,
                    section: question.section.rawValue,
                    title: question.title,
                    score: option.score,
                    selectedOptionTitle: option.title
                )
            }

        let payload = CreateDailyAssessmentRequestDTO(
            date: Date(),
            totalScore: self.totalScore,
            moodScore: self.moodScore,
            adlScore: self.adlScore,
            motorScore: self.motorScore,
            details: detailsDTO
        )

        do {
            _ = try await AssessmentRepository.shared.submitAssessment(payload: payload)
            self.showSuccessAlert = true
            self.hasFilledToday = true
            NotificationScheduler.shared.cancelTodayAssessmentReminderIfCompleted()
            await fetchAvailableRecordDates()
        } catch {
            self.errorMessage = error.localizedDescription
            self.showErrorAlert = true
        }

        self.isSubmitting = false
    }

    /// 依據指定單一日期向伺服器拉取當日的評估紀錄
    /// - Parameter date: 欲查詢之目標日期
    func fetchHistory(for date: Date) async {
        self.isLoadingHistory = true

        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"

        let dateString = formatter.string(from: date)

        do {
            let records = try await AssessmentRepository.shared.fetchAssessment(dateString: dateString)
            self.groupedHistoryRecords = self.groupRecords(records)
        } catch {
            self.errorMessage = error.localizedDescription
            self.showErrorAlert = true
            self.groupedHistoryRecords = []
        }

        self.isLoadingHistory = false
    }

    /// 向伺服器拉取全部歷史評估紀錄，並於本機篩選與降冪排序指定起訖區間內之資料
    /// - Parameters:
    ///   - startDate: 區間起始日期
    ///   - endDate: 區間結束日期
    func fetchHistoryRange(from startDate: Date, to endDate: Date) async {
        self.isLoadingHistory = true

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: startDate)

        guard let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) else {
            self.groupedHistoryRecords = []
            self.isLoadingHistory = false
            return
        }

        do {
            let records = try await AssessmentRepository.shared.fetchAssessment(dateString: nil)
            let filteredRecords = records
                .filter { record in
                    record.date >= startOfDay && record.date <= endOfDay
                }
                .sorted { first, second in
                    first.date > second.date
                }
            self.groupedHistoryRecords = self.groupRecords(filteredRecords)
        } catch {
            self.errorMessage = error.localizedDescription
            self.showErrorAlert = true
            self.groupedHistoryRecords = []
        }

        self.isLoadingHistory = false
    }

    /// 清空目前於畫面上暫存呈現之歷史評估紀錄陣列
    func clearHistory() {
        self.groupedHistoryRecords = []
    }

    /// 將回傳的紀錄陣列依照日期進行分組
    private func groupRecords(_ records: [DailyAssessmentResponseDTO]) -> [DailyAssessmentGroup] {
        var dictionary: [String: (dateText: String, records: [DailyAssessmentResponseDTO])] = [:]
        
        let keyFormatter = DateFormatter()
        keyFormatter.dateFormat = "yyyy-MM-dd"
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "yyyy/MM/dd"

        for record in records {
            let key = keyFormatter.string(from: record.date)
            let display = displayFormatter.string(from: record.date)
            
            if dictionary[key] != nil {
                dictionary[key]?.records.append(record)
            } else {
                dictionary[key] = (dateText: display, records: [record])
            }
        }

        return dictionary.keys.sorted(by: >).compactMap { key in
            guard let group = dictionary[key] else { return nil }
            let sortedRecords = group.records.sorted { $0.date > $1.date }
            return DailyAssessmentGroup(
                id: key,
                dateText: group.dateText,
                records: sortedRecords
            )
        }
    }
}
