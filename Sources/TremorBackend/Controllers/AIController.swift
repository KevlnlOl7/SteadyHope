import Vapor
import Foundation

struct AIController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let ai = routes.grouped("api", "ai")
        ai.post("chat", use: handleChat)
    }
    
    @Sendable
    func handleChat(req: Request) async throws -> ChatResponseDTO {
        // 1. 確保身分
        let _ = try req.auth.require(UserPayload.self)
        
        // 2. 解析前端問題
        struct ChatRequestDTO: Content {
            let message: String
        }
        let userRequest = try req.content.decode(ChatRequestDTO.self)
        
        // 3. 取得並清理金鑰
        guard let rawApiKey = Environment.get("GEMINI_API_KEY") else {
            throw Abort(.internalServerError, reason: "後端未配置 AI 金鑰")
        }
        let apiKey = rawApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 💡 診斷日誌：確認讀到的是正確的個人金鑰
        req.logger.info("【金鑰驗證】目前正在使用金鑰開頭：\(apiKey.prefix(12))")
        
        // 4. ⚡ 速度優化一：配置超低延遲的 3.1 Flash-Lite 模型
        let modelName = "gemini-3.1-flash-lite"
        let geminiURL = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent"
        
        // 💡 速度優化二：在提示詞中強制限制字數，這是「最速且最有效」的降延遲手段！
        let systemPrompt = "【系統指引：你現在是一位溫暖的帕金森氏症心靈陪伴與衛教助手（小安），語氣要有同理心，涉及專業醫療診斷時務必提醒患者就醫。為了體貼患者閱讀並提升回應速度，請務必精簡回答，字數嚴格限制在 150-200 字以內，分段清晰，不囉唆。】"
        let combinedMessage = "\(systemPrompt)\n\n使用者提問：\(userRequest.message)"
        
        let requestBody = GeminiRequest(
            contents: [
                .init(role: "user", parts: [.init(text: combinedMessage)])
            ]
        )
        
        // 5. 建立 Headers
        var googleHeaders = HTTPHeaders()
        googleHeaders.add(name: "Content-Type", value: "application/json")
        googleHeaders.add(name: "x-goog-api-key", value: apiKey)
        
        // 發送標準請求
        let clientResponse = try await req.client.post(URI(string: geminiURL), headers: googleHeaders) {
            try $0.content.encode(requestBody, as: .json)
        }
        
        // 6. 解析回覆
        guard clientResponse.status == .ok else {
            let bytesLength = clientResponse.body?.readableBytes ?? 0
            let errorBody = clientResponse.body?.getString(at: 0, length: bytesLength) ?? "無錯誤內文"
            
            req.logger.error("Gemini API 呼叫失敗，狀態碼：\(clientResponse.status)，詳細原因：\(errorBody)")
            
            throw Abort(.badGateway, reason: "AI 陪伴助手暫時忙碌中，請稍後再試")
        }
        
        let geminiResponse = try clientResponse.content.decode(GeminiResponse.self)
        
        guard let aiReply = geminiResponse.candidates?.first?.content.parts.first?.text else {
            throw Abort(.internalServerError, reason: "生成回應失敗，請重新嘗試")
        }
        
        return ChatResponseDTO(reply: aiReply)
    }
}

// =-=-=-=-=-= DTO 模型 =-=-=-=-=-=
struct GeminiRequest: Content {
    struct ContentObj: Codable {
        struct Part: Codable {
            let text: String
        }
        let role: String
        let parts: [Part]
    }
    let contents: [ContentObj]
}

struct GeminiResponse: Codable {
    struct Candidate: Codable {
        struct ContentObj: Codable {
            struct Part: Codable {
                let text: String
            }
            let parts: [Part]
        }
        let content: ContentObj
    }
    let candidates: [Candidate]?
}

struct ChatResponseDTO: Content {
    let reply: String
}
