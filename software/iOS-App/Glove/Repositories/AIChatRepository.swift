import Foundation

class AIChatRepository {

    /// 底層網路服務實例
    private let aiChatService = AIChatAPIService()

    /// 共用之 ISO 8601 JSONDecoder
    private var iso8601Decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 發送聊天訊息給 AI
    /// - Parameter message: 使用者輸入的訊息內容
    /// - Returns: 包含 AI 回應內容與時間戳記之 Response DTO
    /// - Throws: 網路傳輸或資料解析錯誤 (NetworkError)
    func sendMessage(_ message: String) async throws -> AIChatResponseDTO {
        let requestDTO = AIChatRequestDTO(message: message)
        let data = try await aiChatService.sendMessage(request: requestDTO)

        do {
            let response = try iso8601Decoder.decode(AIChatResponseDTO.self, from: data)
            return response
        } catch {
            print("AI 聊天解析失敗: \(error)")
            throw NetworkError.decodeError
        }
    }

    /// 取得歷史對話紀錄並解析為 ChatMessage 清單
    /// - Returns: ChatMessage 陣列
    /// - Throws: 網路傳輸或資料解析錯誤
    func fetchHistory() async throws -> [ChatMessage] {
        do {
            let historyItems = try await aiChatService.fetchHistory()
            return historyItems.map { $0.toModel() }
        } catch {
            // 如果是因為找不到資料（例如 404）或空資料拋出的錯誤，直接回傳空陣列，不跳出警告
            print("取得歷史紀錄為空或查無資料: \(error)")
            return []
        }
    }

    /// 請求 AI 生成看診溝通卡片摘要
    /// - Parameter payload: 看診摘要請求物件
    /// - Returns: 生成後之 ConsultationSummaryResponseDTO
    /// - Throws: 網路傳輸或資料解析錯誤
    func generateConsultationSummary(payload: GenerateConsultationSummaryRequestDTO) async throws -> ConsultationSummaryResponseDTO {
        let data = try await aiChatService.generateConsultationSummary(request: payload)

        do {
            return try iso8601Decoder.decode(ConsultationSummaryResponseDTO.self, from: data)
        } catch {
            print("看診摘要解析失敗: \(error)")
            throw NetworkError.decodeError
        }
    }
}
