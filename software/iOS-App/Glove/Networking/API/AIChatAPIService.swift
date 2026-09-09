import Foundation

class AIChatAPIService {

    /// 後端 API 的基礎 URL 地址
    private let baseURL = APIConfig.baseURL

    /// 通用的 ISO 8601 JSONDecoder
    private var iso8601Decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 向伺服器發送 AI 聊天請求
    /// - Parameter request: 包含聊天內容的 ChatRequest 物件
    /// - Returns: 伺服器回傳的原始 Data 資料
    /// - Throws: NetworkError 類型的錯誤
    func sendMessage(request: AIChatRequestDTO) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/api/ai/chat") else {
            throw NetworkError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = AuthManager.shared.getToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw NetworkError.encodingFailed
        }

        return try await NetworkManager.shared.requestData(urlRequest)
    }
    
    /// 取得歷史對話紀錄並直接解碼
    /// - Returns: 解碼後的聊天歷史列表 [AIChatHistoryItemDTO]
    /// - Throws: NetworkError 類型的錯誤
    func fetchHistory() async throws -> [AIChatHistoryItemDTO] {
        guard let url = URL(string: "\(baseURL)/api/ai/history") else {
            throw NetworkError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"

        if let token = AuthManager.shared.getToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return try await NetworkManager.shared.request(urlRequest, decoder: iso8601Decoder)
    }

    /// 向後端 AI 請求生成看診溝通卡片摘要原始 Data
    func generateConsultationSummary(request: GenerateConsultationSummaryRequestDTO) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/api/ai/consultation-summary") else {
            throw NetworkError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = AuthManager.shared.getToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw NetworkError.encodingFailed
        }

        return try await NetworkManager.shared.requestData(urlRequest)
    }
}
