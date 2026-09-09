import Foundation

/// 後端 AI 對話歷史紀錄單筆資料傳輸物件 (DTO)
struct AIChatHistoryItemDTO: Codable, Sendable {
    let id: String
    let content: String
    let role: String
    let createdAt: Date

    /// 判斷訊息是否由使用者發送
    var isUser: Bool {
        return role.lowercased() == "user"
    }

    /// 轉換為 UI 顯示使用之 ChatMessage 實體
    func toModel() -> ChatMessage {
        ChatMessage(
            text: content,
            isUser: isUser,
            timestamp: createdAt
        )
    }
}

/// 發送至後端 AI 對話服務之請求資料傳輸物件 (DTO)
struct AIChatRequestDTO: Codable {
    let message: String
}

/// 後端 AI 對話服務回傳之回應資料傳輸物件 (DTO)
struct AIChatResponseDTO: Codable {
    let reply: String
    let createdAt: Date
}
