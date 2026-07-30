import AVFoundation
import Combine
import Speech
import SwiftData
import SwiftUI

class DailyViewModel: ObservableObject {
    let loginVM: LoginViewModel

    /// 每日留言資料存取 Repository 層實例
    private let dailyRepo = DailyRepository()

    /// 當前使用者角色與名稱（動態取得自 loginVM）
    var currentUserRole: String {
        loginVM.userData?.userName ?? "用戶"
    }

    /// 可供選擇的心情選項清單
    let moods = ["開心", "平靜", "疲憊", "不舒服"]

    /// 留言板資料清單（同時同步本機 SwiftData 與伺服器資料）
    @Published var notes: [Daily] = []

    /// 資料載入狀態指示
    @Published var isLoadingData = false

    /// 選擇查詢的目標日期
    @Published var selectedDate = Date()

    /// 選擇查詢的心情識別碼
    @Published var selectedMood: UUID? = nil

    /// 是否顯示新增留言 Sheet 視圖
    @Published var showAddNoteSheet = false

    /// 是否僅限照護者查看狀態
    @Published var isCaregiverOnly: Bool = false

    /// 當前所選取欲檢視詳細資訊或刪除的便利貼模型
    @Published var selectedDetailNote: Daily? = nil

    /// 新增留言時輸入的內文暫存
    @Published var newNoteText = ""

    /// 新增便利貼預設選取的背景顏色
    @Published var noteColor: Color = Color(
        red: 1.0,
        green: 0.94,
        blue: 0.8
    )

    /// 新增便利貼時所選取的心情名稱
    @Published var sheetSelectedMoodName: String? = nil

    /// 語音辨識管理員實例
    @Published var speechRecognizer = SpeechRecognizer()

    /// Combine 訂閱集合
    private var cancellables = Set<AnyCancellable>()

    /// 初始化 DailyViewModel 並訂閱語音轉譯事件
    /// - Parameter loginVM: 使用者登入狀態與權限 ViewModel
    init(loginVM: LoginViewModel) {
        self.loginVM = loginVM

        // 訂閱語音辨識結果，即時更新輸入框內容
        speechRecognizer.$transcript
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self = self, !newValue.isEmpty else { return }
                if self.speechRecognizer.isRecording {
                    let cleaned = self.cleanExcessiveNewlines(newValue)
                    self.newNoteText = self.limitLinesAndLength(
                        text: cleaned,
                        maxCharacters: 100,
                        maxLines: 5
                    )
                }
            }
            .store(in: &cancellables)
    }

    /// 今日所有填寫心情的便利貼紀錄，並依時間由舊至新排序
    var todaysDailiesWithMood: [Daily] {
        notes.filter {
            Calendar.current.isDateInToday($0.date) && $0.moodName != nil
        }.sorted(by: { $0.date < $1.date })
    }

    /// 處理手動輸入留言時的字數與換行限制
    /// - Parameter newValue: 新輸入的文字內容
    func handleNoteTextChange(_ newValue: String) {
        guard !speechRecognizer.isRecording else { return }

        let cleaned = cleanExcessiveNewlines(newValue)
        let limited = limitLinesAndLength(
            text: cleaned,
            maxCharacters: 100,
            maxLines: 5
        )
        if limited != newValue {
            newNoteText = limited
        }
    }

    /// 從遠端伺服器拉取最新便利貼資料，寫入本機 SwiftData 並更新畫面
    /// - Parameters:
    ///   - modelContext: SwiftData 資料庫操作上下文
    ///   - isSilent: 是否採用靜默載入（不觸發全螢幕載入轉圈圈動畫）
    @MainActor
    func loadAllNotes(modelContext: ModelContext, isSilent: Bool = false) async {
        if !isSilent {
            await MainActor.run {
                self.isLoadingData = true
            }
        }

        defer {
            if !isSilent {
                Task { @MainActor in
                    self.isLoadingData = false
                }
            }
        }

        do {
            // 從後端獲取最新資料
            let remoteNotes = try await dailyRepo.fetchAllDailies()

            // 清除本機舊的 Daily 紀錄，避免資料庫重複混亂
            let descriptor = FetchDescriptor<Daily>()
            if let oldNotes = try? modelContext.fetch(descriptor) {
                for note in oldNotes {
                    modelContext.delete(note)
                }
            }

            // 將最新遠端資料存入 SwiftData 本機資料庫
            for note in remoteNotes {
                modelContext.insert(note)
            }

            // 保存本機資料庫並更新畫面陣列
            try? modelContext.save()
            self.notes = remoteNotes

        } catch {
            let errorMsg = error.localizedDescription
            print("載入便利貼失敗: \(errorMsg)")

            // 若為 401 或登入失效，不載入快取，直接清空資料並返回
            if errorMsg.contains("401") || errorMsg.contains("已在其他裝置登入") || errorMsg.contains("登入已失效") {
                self.notes = []
                isLoadingData = false
                return
            }

            // 僅在非 401 錯誤（如網路斷線）時，降級讀取本機快取資料
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
        speechRecognizer.stopRecording()
        let finalContent = newNoteText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !finalContent.isEmpty else { return }

        // 建立新的本機 Daily 模型
        let newNote = Daily(
            content: finalContent,
            date: Date(),
            colorHex: noteColor.toHex() ?? "#FFF0CC",
            sender: currentUserRole,
            moodName: sheetSelectedMoodName,
            isCaregiverOnly: isCaregiverOnly
        )

        // 同步寫入本機 SwiftData 資料庫
        modelContext.insert(newNote)
        try? modelContext.save()

        // 即時更新畫面列表
        self.notes.insert(newNote, at: 0)
        let noteID = newNote.id

        resetSheetState()

        // 背景同步至伺服器
        do {
            try await dailyRepo.syncDailyRecord(
                id: noteID,
                content: newNote.content,
                date: newNote.date,
                colorHex: newNote.colorHex,
                sender: newNote.sender,
                moodName: newNote.moodName,
                isCaregiverOnly: newNote.isCaregiverOnly
            )
        } catch {
            print("同步便利貼至伺服器失敗: \(error.localizedDescription)")
        }
    }

    /// 刪除便利貼（同步更新 UI、本機 SwiftData 與遠端伺服器）
    /// - Parameters:
    ///   - note: 欲刪除的 Daily 實體
    ///   - modelContext: SwiftData 資料庫操作上下文
    @MainActor
    func deleteNote(note: Daily, modelContext: ModelContext) async {
        let noteID = note.id

        // 從畫面清單中移除
        notes.removeAll { $0.id == noteID }

        // 從 SwiftData 本機資料庫刪除
        modelContext.delete(note)
        try? modelContext.save()

        // 連動刪除伺服器端資料
        do {
            try await dailyRepo.removeDailyRecord(recordID: noteID)
        } catch {
            print("從伺服器刪除便利貼失敗: \(error.localizedDescription)")
        }
    }

    /// 取消新增便利貼並重置 Sheet 狀態
    func cancelAddingNote() {
        speechRecognizer.stopRecording()
        resetSheetState()
    }

    /// 重置新增表單的輸入狀態與暫存變數
    private func resetSheetState() {
        newNoteText = ""
        sheetSelectedMoodName = nil
        showAddNoteSheet = false
        speechRecognizer.transcript = ""
    }

    /// 限制文字的最高行數與總字數
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

    /// 清除過多連續換行符號
    private func cleanExcessiveNewlines(_ text: String) -> String {
        return text.replacingOccurrences(
            of: "(\\n\\s*){3,}",
            with: "\n\n",
            options: .regularExpression
        )
    }

    /// 取得心情名稱對應之 SFSymbols 圖示名稱
    func getMoodIcon(for name: String) -> String {
        switch name {
        case "開心": return "face.smiling"
        case "平靜": return "face.dashed"
        case "疲憊": return "zzz"
        case "不舒服": return "thermometer"
        default: return ""
        }
    }

    /// 取得心情名稱對應之代表色彩
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
