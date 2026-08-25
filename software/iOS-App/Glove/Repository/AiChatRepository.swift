import Foundation

class AiChatRepository {

    /// 底層網路服務實例
    private let aiChatService = AiChatService()

    /// 發送聊天訊息給 AI
    /// - Parameter message: 使用者輸入的訊息內容
    /// - Returns: AI 回傳的回應內容字串
    /// - Throws: Validation 類型的錯誤
    func sendMessage(_ message: String) async throws -> String {
        let requestDTO = AiChatRequestDTO(message: message)
        let data = try await aiChatService.sendMessage(request: requestDTO)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let response = try decoder.decode(AiChatResponseDTO.self, from: data)
            return response.reply
        } catch {
            print("AI 聊天解析失敗: \(error)")
            throw Validation.server(message: "回傳資料格式異常")
        }
    }
}
