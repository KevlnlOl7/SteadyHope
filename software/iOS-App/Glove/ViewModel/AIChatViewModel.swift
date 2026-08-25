import Combine
import Foundation
import SwiftUI

class AIChatViewModel: ObservableObject {
    
    /// 全域單例存取點
    static let shared = AIChatViewModel()

    /// 對話歷史紀錄清單
    @Published var messages: [ChatMessage] = [
        ChatMessage(
            text: "您好呀！我是小安 \n今天身體感覺怎麼樣呢？不論是想聊聊、問問題，我都隨時在這裡陪您喔！",
            isUser: false,
            timestamp: Date()
        )
    ]

    /// 輸入框文字內容
    @Published var inputText: String = ""

    /// 是否正在等待 AI 生成回答
    @Published var isLoading: Bool = false

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

    /// 當前非同步請求 Task 實例
    private var currentTask: Task<Void, Never>? = nil

    /// 對話資料 Repository 實例
    private let chatRepo = AiChatRepository()

    /// 所有擁有對話紀錄之日期集合
    var availableDates: Set<Date> {
        let dates = messages.map {
            Calendar.current.startOfDay(for: $0.timestamp)
        }
        return Set(dates)
    }

    /// 可供月曆選擇之日期區間範圍
    var selectableDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let oldestDate =
            messages.map { calendar.startOfDay(for: $0.timestamp) }.min()
            ?? today
        return oldestDate...today
    }

    /// 檢查指定日期是否有對話紀錄
    /// - Parameter date: 欲檢查之日期
    /// - Returns: 布林值
    func hasMessages(on date: Date) -> Bool {
        let targetDay = Calendar.current.startOfDay(for: date)
        return availableDates.contains(targetDay)
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

    /// 切換至上一筆搜尋結果
    func previousMatch() {
        guard !matchedMessages.isEmpty else { return }
        if currentSearchIndex > 0 {
            currentSearchIndex -= 1
        } else {
            currentSearchIndex = matchedMessages.count - 1
        }
    }

    /// 切換至下一筆搜尋結果
    func nextMatch() {
        guard !matchedMessages.isEmpty else { return }
        if currentSearchIndex < matchedMessages.count - 1 {
            currentSearchIndex += 1
        } else {
            currentSearchIndex = 0
        }
    }

    /// 經過日期篩選後之對話訊息清單
    var filteredMessages: [ChatMessage] {
        messages.filter { message in
            // 只有選擇日期時才過濾訊息，搜尋關鍵字時不剔除任何對話
            if let targetDate = selectedDate {
                return Calendar.current.isDate(
                    message.timestamp,
                    inSameDayAs: targetDate
                )
            }
            return true
        }
    }

    /// 依據日期分類分組後之訊息清單
    var groupedMessages: [DateGroupedMessages] {
        let dictionary = Dictionary(grouping: filteredMessages) { message in
            Calendar.current.startOfDay(for: message.timestamp)
        }

        return dictionary.map {
            DateGroupedMessages(date: $0.key, messages: $0.value)
        }
        .sorted { $0.date < $1.date }
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

        currentTask = Task {
            do {
                let reply = try await chatRepo.sendMessage(trimmedText)
                if Task.isCancelled { return }

                await MainActor.run {
                    let aiMessage = ChatMessage(
                        text: reply,
                        isUser: false,
                        timestamp: Date()
                    )
                    messages.append(aiMessage)
                    isLoading = false
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    isLoading = false
                    errorMessage = "網路好像有點小狀況，請稍後再試試看喔！"
                }
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
