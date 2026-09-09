import Combine
import SwiftUI

/// 依日期分組的歷史紀錄結構
struct DailyAssessmentGroup: Identifiable, Equatable {
    let id: String // 日期字串作為識別 (例如 "2026-09-01")
    let dateText: String // 顯示用的日期標題 (例如 "2026/09/01")
    var records: [DailyAssessmentResponseDTO]
}

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

    /// 將回傳的紀錄陣列依照日期（yyyy/MM/dd）進行分組
    private func groupRecords(_ records: [DailyAssessmentResponseDTO]) -> [DailyAssessmentGroup] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.timeZone = TimeZone.current
        
        // 建立分組 Key (yyyy-MM-dd) 與 顯示字串 (yyyy/MM/dd)
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

        // 依照日期由新到舊排序分組
        return dictionary.keys.sorted(by: >).compactMap { key in
            guard let group = dictionary[key] else { return nil }
            // 讓同一天內的紀錄也照時間降冪排序
            let sortedRecords = group.records.sorted { $0.date > $1.date }
            return DailyAssessmentGroup(
                id: key,
                dateText: group.dateText,
                records: sortedRecords
            )
        }
    }
}
