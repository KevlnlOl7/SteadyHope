import Foundation

/// 依日期分組之對話訊息資料結構
struct DateGroupedMessages: Identifiable {
    let id = UUID()
    /// 分組日期
    let date: Date
    /// 當日訊息清單
    let messages: [ChatMessage]
}

/// 對話訊息模型
struct ChatMessage: Identifiable {
    let id = UUID()
    /// 訊息內文
    let text: String
    /// 是否為使用者發送
    let isUser: Bool
    /// 發送時間戳記
    let timestamp: Date
}
