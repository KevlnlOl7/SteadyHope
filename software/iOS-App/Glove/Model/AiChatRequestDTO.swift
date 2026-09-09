import Foundation

/// 發送至後端 AI 對話服務之請求資料傳輸物件 (DTO)
struct AiChatRequestDTO: Codable {
    let message: String
}

/// 後端 AI 對話服務回傳之回應資料傳輸物件 (DTO)
struct AiChatResponseDTO: Codable {
    let reply: String
    let createdAt: Date
}
