import Combine
import Foundation
import SwiftUI

@MainActor
final class AIChatViewModel: ObservableObject {

    /// 全域單例存取點
    static let shared = AIChatViewModel()

    /// 對話歷史紀錄清單（預設為空）
    @Published var messages: [ChatMessage] = []

    /// 輸入框文字內容
    @Published var inputText: String = ""

    /// 是否正在等待 AI 生成回答
    @Published var isLoading: Bool = false

    /// 是否正在載入歷史對話紀錄
    @Published var isLoadingHistory: Bool = false

    /// 錯誤訊息文字
    @Published var errorMessage: String? = nil

    /// 搜尋關鍵字（文字變更時自動重置搜尋結果索引）
    @Published var searchText: String = "" {
        didSet {
            currentSearchIndex = 0
        }
    }

    /// 所選取之篩選目標日期
    @Published var selectedDate: Date? = nil

    /// 是否處於搜尋模式
    @Published var isSearching: Bool = false

    /// 當前高亮導覽之搜尋結果索引 (0-based)
    @Published var currentSearchIndex: Int = 0

    /// 當前發送訊息 Task 實例
    private var currentTask: Task<Void, Never>? = nil

    /// 當前載入歷史紀錄 Task 實例
    private var loadHistoryTask: Task<Void, Never>? = nil

    /// 對話資料 Repository 實例
    private let chatRepo = AIChatRepository()

    /// 所有擁有對話紀錄之日期集合（已轉換為該日起始時間）
    var availableDates: Set<Date> {
        let dates = messages.map {
            Calendar.current.startOfDay(for: $0.timestamp)
        }
        return Set(dates)
    }

    /// 可供月曆選擇之日期區間範圍（最舊對話日期至今日）
    var selectableDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let oldestDate =
            messages.map { calendar.startOfDay(for: $0.timestamp) }.min()
            ?? today
        return oldestDate...today
    }

    /// 符合搜尋關鍵字之訊息清單
    var matchedMessages: [ChatMessage] {
        guard
            !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return [] }
        return filteredMessages.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// 當前高亮匹配之訊息 ID
    var currentMatchMessageId: UUID? {
        guard !matchedMessages.isEmpty, currentSearchIndex < matchedMessages.count
        else { return nil }
        return matchedMessages[currentSearchIndex].id
    }

    /// 經過日期篩選後之對話訊息清單
    var filteredMessages: [ChatMessage] {
        messages.filter { message in
            if let targetDate = selectedDate {
                return Calendar.current.isDate(
                    message.timestamp,
                    inSameDayAs: targetDate
                )
            }
            return true
        }
    }

    /// 依據日期分類分組後之訊息清單，並依日期由舊至新排序
    var groupedMessages: [DateGroupedMessages] {
        let dictionary = Dictionary(grouping: filteredMessages) { message in
            Calendar.current.startOfDay(for: message.timestamp)
        }

        return dictionary.map {
            DateGroupedMessages(date: $0.key, messages: $0.value)
        }
        .sorted { $0.date < $1.date }
    }

    /// 檢查指定日期是否有對話紀錄
    /// - Parameter date: 欲檢查之日期
    /// - Returns: 指定日期若存在對話紀錄則回傳 true，否則回傳 false
    func hasMessages(on date: Date) -> Bool {
        let targetDay = Calendar.current.startOfDay(for: date)
        return availableDates.contains(targetDay)
    }

    /// 切換至上一筆搜尋結果（具備循環導覽機制）
    func previousMatch() {
        guard !matchedMessages.isEmpty else { return }
        if currentSearchIndex > 0 {
            currentSearchIndex -= 1
        } else {
            currentSearchIndex = matchedMessages.count - 1
        }
    }

    /// 切換至下一筆搜尋結果（具備循環導覽機制）
    func nextMatch() {
        guard !matchedMessages.isEmpty else { return }
        if currentSearchIndex < matchedMessages.count - 1 {
            currentSearchIndex += 1
        } else {
            currentSearchIndex = 0
        }
    }

    /// 發送使用者輸入之對話內容並發起非同步 AI 回答請求
    func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedText.isEmpty else { return }

        let userMessage = ChatMessage(
            text: trimmedText,
            isUser: true,
            timestamp: Date()
        )
        messages.append(userMessage)

        inputText = ""
        isLoading = true
        errorMessage = nil

        currentTask?.cancel()
        currentTask = Task {
            do {
                let response = try await chatRepo.sendMessage(trimmedText)
                if Task.isCancelled { return }

                let aiMessage = ChatMessage(
                    text: response.reply,
                    isUser: false,
                    timestamp: response.createdAt
                )
                messages.append(aiMessage)
                isLoading = false
            } catch {
                if Task.isCancelled { return }
                isLoading = false
                AppLog.error("AI 發送訊息失敗: \(error.localizedDescription)")
                errorMessage = "網路好像有點小狀況，請稍後再試試看喔！"
            }
        }
    }

    /// 載入歷史對話紀錄清單，並依時間由舊至新排序
    func loadHistory() {
        loadHistoryTask?.cancel()
        isLoadingHistory = true
        errorMessage = nil

        loadHistoryTask = Task {
            do {
                let historyMessages = try await chatRepo.fetchHistory()
                if Task.isCancelled { return }

                // 確保對話紀錄由舊至新排序，符合聊天室由上而下的閱讀順序
                self.messages = historyMessages.sorted { $0.timestamp < $1.timestamp }
                self.isLoadingHistory = false
            } catch {
                if Task.isCancelled { return }
                self.isLoadingHistory = false
                AppLog.error("載入 AI 歷史紀錄失敗: \(error.localizedDescription)")
                self.errorMessage = "載入歷史紀錄失敗，請稍後再試"
            }
        }
    }

    /// 終止目前正在進行的 AI 回答生成 Task
    func stopGeneration() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }

    /// 清除所有搜尋關鍵字與日期篩選狀態
    func clearFilter() {
        searchText = ""
        selectedDate = nil
        currentSearchIndex = 0
    }
}
