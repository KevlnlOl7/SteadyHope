import Combine
import SwiftData
import SwiftUI

@MainActor
final class DailyViewModel: ObservableObject {
    let loginVM: LoginViewModel

    /// 每日留言資料存取 Repository 層實例
    private let dailyRepo = DailyRepository()

    /// 使用者資訊與身分判斷
    var currentUserRole: String {
        loginVM.userData?.userName ?? "用戶"
    }
    var isPatient: Bool {
        loginVM.userData?.role == 0
    }

    /// 心情選項清單
    let moods = ["開心", "平靜", "疲憊", "不舒服"]

    /// 留言清單與查詢狀態
    @Published var notes: [Daily] = []
    @Published var isLoadingData = false
    @Published var selectedDate = Date()
    @Published var selectedMood: UUID? = nil
    @Published var selectedDetailNote: Daily? = nil

    /// 新增便利貼暫存狀態
    @Published var showAddNoteSheet = false
    @Published var newNoteText = ""
    @Published var sheetSelectedMoodName: String? = nil
    @Published var isCaregiverOnly: Bool = false
    @Published var noteColor: Color = Color(
        red: 1.0,
        green: 0.94,
        blue: 0.8
    )

    /// 編輯便利貼暫存狀態
    @Published var editingNote: Daily? = nil
    @Published var editNoteText: String = ""
    @Published var editSelectedMoodName: String? = nil
    @Published var editIsCaregiverOnly: Bool = false
    @Published var editNoteColor: Color = Color(
        red: 1.0,
        green: 0.94,
        blue: 0.8
    )

    /// 初始化 ViewModel 並注入登入狀態管理器
    /// - Parameter loginVM: 登入狀態與使用者資料的 ViewModel
    init(loginVM: LoginViewModel) {
        self.loginVM = loginVM
    }

    /// 送出與儲存校驗：病患文字與心情二擇一，照護者留言文字必填
    var canSendNote: Bool {
        let trimmed = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        return isPatient ? (!trimmed.isEmpty || sheetSelectedMoodName != nil) : !trimmed.isEmpty
    }

    var canSaveEditedNote: Bool {
        let trimmed = editNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        return isPatient ? (!trimmed.isEmpty || editSelectedMoodName != nil) : !trimmed.isEmpty
    }

    /// 今日所有填寫心情的便利貼紀錄，並依時間由舊至新排序
    var todaysDailiesWithMood: [Daily] {
        let calendar = Calendar.current
        return notes.filter {
            calendar.isDateInToday($0.date) && $0.moodName != nil
        }.sorted(by: { $0.date < $1.date })
    }

    /// 處理手動輸入新增留言時的字數與換行限制
    /// - Parameter newValue: 新輸入的文字內容
    func handleNoteTextChange(_ newValue: String) {
        let cleaned = cleanExcessiveNewlines(newValue)
        let limited = limitLinesAndLength(text: cleaned, maxCharacters: 100, maxLines: 5)
        if limited != newValue {
            newNoteText = limited
        }
    }

    /// 處理手動編輯既有留言時的字數與換行限制
    /// - Parameter newValue: 新輸入的文字內容
    func handleEditTextChange(_ newValue: String) {
        let cleaned = cleanExcessiveNewlines(newValue)
        let limited = limitLinesAndLength(text: cleaned, maxCharacters: 100, maxLines: 5)
        if limited != newValue {
            editNoteText = limited
        }
    }

    /// 從遠端伺服器拉取最新便利貼資料，寫入本機 SwiftData 並更新畫面
    /// - Parameters:
    ///   - modelContext: SwiftData 資料庫操作上下文
    ///   - isSilent: 是否採用靜默載入（不觸發全螢幕載入轉圈圈動畫）
    @MainActor
    func loadAllNotes(modelContext: ModelContext, isSilent: Bool = false) async {
        if !isSilent {
            self.isLoadingData = true
        }

        defer {
            if !isSilent {
                Task { @MainActor in
                    self.isLoadingData = false
                }
            }
        }

        do {
            let remoteNotes = try await dailyRepo.fetchAllDailies()

            let descriptor = FetchDescriptor<Daily>()
            if let oldNotes = try? modelContext.fetch(descriptor) {
                for note in oldNotes {
                    modelContext.delete(note)
                }
            }

            for note in remoteNotes {
                modelContext.insert(note)
            }

            try? modelContext.save()
            self.notes = remoteNotes

        } catch {
            let errorMsg = error.localizedDescription
            print("載入便利貼失敗: \(errorMsg)")

            if errorMsg.contains("401") || errorMsg.contains("已在其他裝置登入") || errorMsg.contains("登入已失效") {
                self.notes = []
                isLoadingData = false
                return
            }

            let descriptor = FetchDescriptor<Daily>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            if let cachedNotes = try? modelContext.fetch(descriptor) {
                self.notes = cachedNotes
            }
        }
        isLoadingData = false
    }

    /// 發送新便利貼（優先寫入本機與更新 UI，隨後同步至伺服器）
    /// - Parameter modelContext: SwiftData 資料庫操作上下文
    @MainActor
    func sendNote(modelContext: ModelContext) async {
        guard canSendNote else { return }

        let trimmedContent = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)

        let newDaily = Daily(
            content: trimmedContent,
            date: Date(),
            colorHex: noteColor.toHex() ?? "#FFF0CC",
            sender: currentUserRole,
            moodName: sheetSelectedMoodName,
            isCaregiverOnly: isCaregiverOnly
        )

        modelContext.insert(newDaily)
        try? modelContext.save()

        if !trimmedContent.isEmpty {
            self.notes.insert(newDaily, at: 0)
        } else {
            self.notes.append(newDaily)
        }

        let recordID = newDaily.id
        resetSheetState()

        do {
            try await dailyRepo.syncDailyRecord(
                id: recordID,
                content: newDaily.content,
                date: newDaily.date,
                colorHex: newDaily.colorHex,
                sender: newDaily.sender,
                moodName: newDaily.moodName,
                isCaregiverOnly: newDaily.isCaregiverOnly
            )
        } catch {
            print("同步紀錄至伺服器失敗: \(error.localizedDescription)")
        }
    }

    /// 編輯便利貼：載入目標資料至表單
    /// - Parameter note: 欲修改的 Daily 實體
    func startEditing(_ note: Daily) {
        self.editingNote = note
        self.editNoteText = note.content
        self.editNoteColor = Color(hex: note.colorHex)
        self.editSelectedMoodName = note.moodName
        self.editIsCaregiverOnly = note.isCaregiverOnly ?? false
    }

    /// 儲存編輯內容：更新本機實體與遠端資料庫（若文字清空則移出留言看板）
    /// - Parameter modelContext: SwiftData 資料庫操作上下文
    @MainActor
    func saveEditedNote(modelContext: ModelContext) async {
        guard let note = editingNote, canSaveEditedNote else { return }

        let trimmedContent = editNoteText.trimmingCharacters(in: .whitespacesAndNewlines)

        note.content = trimmedContent
        note.colorHex = editNoteColor.toHex() ?? "#FFF0CC"
        note.moodName = editSelectedMoodName
        note.isCaregiverOnly = editIsCaregiverOnly

        try? modelContext.save()

        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }

        let recordID = note.id
        self.editingNote = nil
        self.selectedDetailNote = nil

        do {
            try await dailyRepo.syncDailyRecord(
                id: recordID,
                content: note.content,
                date: note.date,
                colorHex: note.colorHex,
                sender: note.sender,
                moodName: note.moodName,
                isCaregiverOnly: note.isCaregiverOnly
            )
        } catch {
            print("更新紀錄至伺服器失敗: \(error.localizedDescription)")
        }
    }

    /// 刪除便利貼：移除本機快取與遠端資料
    /// - Parameters:
    ///   - note: 欲刪除的 Daily 實體
    ///   - modelContext: SwiftData 資料庫操作上下文
    @MainActor
    func deleteNote(note: Daily, modelContext: ModelContext) async {
        let noteID = note.id

        notes.removeAll { $0.id == noteID }
        modelContext.delete(note)
        try? modelContext.save()

        do {
            try await dailyRepo.removeDailyRecord(recordID: noteID)
        } catch {
            print("從伺服器刪除便利貼失敗: \(error.localizedDescription)")
        }
    }

    /// 重設新增表單狀態並關閉表單
    func cancelAddingNote() {
        resetSheetState()
    }

    /// 清空新增便利貼表單的所有輸入暫存欄位
    private func resetSheetState() {
        newNoteText = ""
        sheetSelectedMoodName = nil
        showAddNoteSheet = false
    }

    /// 字串格式限制處理（限制最大字數與最大行數）
    /// - Parameters:
    ///   - text: 原始輸入字串
    ///   - maxCharacters: 允許輸入的最大字元數
    ///   - maxLines: 允許輸入的最大行數
    /// - Returns: 符合規範的安全裁剪字串
    private func limitLinesAndLength(
        text: String,
        maxCharacters: Int,
        maxLines: Int
    ) -> String {
        let lines = text.components(separatedBy: "\n")
        if lines.count > maxLines {
            let allowedLines = lines.prefix(maxLines)
            let combinedText = allowedLines.joined(separator: "\n")
            return String(combinedText.prefix(maxCharacters))
        }
        return String(text.prefix(maxCharacters))
    }

    /// 移除過多連續換行符號（將 3 個以上換行壓縮為 2 個）
    /// - Parameter text: 原始輸入字串
    /// - Returns: 整理後的排版字串
    private func cleanExcessiveNewlines(_ text: String) -> String {
        return text.replacingOccurrences(
            of: "(\\n\\s*){3,}",
            with: "\n\n",
            options: .regularExpression
        )
    }

    /// 根據心情中文名稱取得對應的 SF Symbol 圖示名稱
    /// - Parameter name: 心情名稱（開心、平靜、疲憊、不舒服）
    /// - Returns: 對應的 SF Symbol 圖示識別碼字串
    func getMoodIcon(for name: String) -> String {
        switch name {
        case "開心": return "face.smiling"
        case "平靜": return "face.dashed"
        case "疲憊": return "zzz"
        case "不舒服": return "thermometer"
        default: return ""
        }
    }

    /// 根據心情中文名稱取得對應的主題色
    /// - Parameter name: 心情名稱（開心、平靜、疲憊、不舒服）
    /// - Returns: 對應的心情標籤色彩
    func getMoodColor(for name: String) -> Color {
        switch name {
        case "開心": return .orange
        case "平靜": return .green
        case "疲憊": return .blue
        case "不舒服": return .purple
        default: return .gray
        }
    }
}
