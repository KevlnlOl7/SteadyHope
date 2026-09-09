import Foundation

class AiChatService {

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
    func sendMessage(request: AiChatRequestDTO) async throws -> Data {
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw NetworkError.serverError(reason: "無法連線至伺服器，請檢查網路狀態")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError(reason: "伺服器回應異常")
        }

        if httpResponse.statusCode == 401 {
            throw NetworkError.unauthorized
        } else if ![200, 201].contains(httpResponse.statusCode) {
            throw NetworkError.serverError(
                reason: "AI 服務暫時無法使用 (\(httpResponse.statusCode))"
            )
        }

        return data
    }

    /// 取得歷史對話紀錄並直接解碼
    /// - Returns: 解碼後的聊天歷史列表 [AiChatHistoryItemDTO]
    /// - Throws: NetworkError 類型的錯誤
    func fetchHistory() async throws -> [AiChatHistoryItemDTO] {
        guard let url = URL(string: "\(baseURL)/api/ai/history") else {
            throw NetworkError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"

        if let token = AuthManager.shared.getToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw NetworkError.serverError(reason: "無法連線至伺服器，請檢查網路狀態")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError(reason: "伺服器回應異常")
        }

        if httpResponse.statusCode == 401 {
            throw NetworkError.unauthorized
        } else if httpResponse.statusCode != 200 {
            throw NetworkError.serverError(
                reason: "取得歷史紀錄失敗 (\(httpResponse.statusCode))"
            )
        }

        do {
            return try iso8601Decoder.decode([AiChatHistoryItemDTO].self, from: data)
        } catch {
            throw NetworkError.decodeError
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw NetworkError.serverError(reason: "無法連線至伺服器，請檢查網路狀態")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError(reason: "伺服器回應異常")
        }

        if httpResponse.statusCode == 401 {
            throw NetworkError.unauthorized
        } else if ![200, 201].contains(httpResponse.statusCode) {
            throw NetworkError.serverError(reason: "產生看診摘要失敗 (\(httpResponse.statusCode))")
        }

        return data
    }
}
