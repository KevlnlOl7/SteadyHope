import Foundation

class AiChatService {

    /// 後端 API 的基礎 URL 地址
    private let baseURL = APIConfig.baseURL

    /// 向伺服器發送 AI 聊天請求
    /// - Parameter request: 包含聊天內容的 ChatRequest 物件
    /// - Returns: 伺服器回傳的原始 Data 資料
    /// - Throws: Validation 類型的錯誤
    func sendMessage(request: AiChatRequestDTO) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/api/ai/chat") else {
            throw Validation.server(message: "URL 格式錯誤")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

         // Authorization Token 
         if let token = AuthManager.shared.getToken() {
             urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
         }

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw Validation.server(message: "資料封裝失敗")
        }

        // 執行請求
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw Validation.server(message: "無法連線至伺服器，請檢查網路狀態")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Validation.server(message: "伺服器回應異常")
        }

        // 處理狀態碼
        if httpResponse.statusCode == 401 {
            throw Validation.server(message: "身份驗證失敗，請重新登入")
        } else if ![200, 201].contains(httpResponse.statusCode) {
            throw Validation.server(message: "AI 服務暫時無法使用 (\(httpResponse.statusCode))")
        }

        return data
    }
}
