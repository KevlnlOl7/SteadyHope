import Foundation

final class NetworkManager {
    static let shared = NetworkManager()
    
    private init() {}

    /// 發送網路請求並取得原始 Data（集中處理網路連線、401 攔截與 HTTP 狀態碼檢驗）
    /// - Parameter urlRequest: 欲發送的 URLRequest
    /// - Returns: 伺服器回傳的成功 Data (200...299)
    @discardableResult
    func requestData(_ urlRequest: URLRequest) async throws -> Data {
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

        // 全域攔截 401 Unauthorized
        if httpResponse.statusCode == 401 {
            let reason = parseServerError(from: data, defaultMessage: "登入已過期或帳號已在其他裝置登入")
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .didReceive401Unauthorized,
                    object: nil,
                    userInfo: ["message": reason]
                )
            }
            throw NetworkError.unauthorized
        }

        // 處理非 2xx 成功狀態碼
        guard (200...299).contains(httpResponse.statusCode) else {
            let reason = parseServerError(from: data, defaultMessage: "伺服器回應異常 (\(httpResponse.statusCode))")
            throw NetworkError.serverError(reason: reason)
        }

        return data
    }

    /// 發送網路請求並自動解碼為指定型別
    /// - Parameters:
    ///   - urlRequest: 欲發送之 URLRequest
    ///   - decoder: 自訂 JSONDecoder（若傳入 nil 則預設採用 ISO 8601 日期解析）
    /// - Returns: 解碼後之物件
    func request<T: Decodable>(_ urlRequest: URLRequest, decoder: JSONDecoder? = nil) async throws -> T {
        let data = try await requestData(urlRequest)
        let activeDecoder = decoder ?? Self.makeDefaultDecoder()

        do {
            return try activeDecoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodeError
        }
    }

    /// 建立預設的 JSON 解碼器（加上 nonisolated 避免被 Swift 6 自動推導為 MainActor 隔離）
    nonisolated static func makeDefaultDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 解析 Vapor 後端回傳的錯誤訊息結構
    /// - Parameters:
    ///   - data: 伺服器回傳之原始資料
    ///   - defaultMessage: 若解析失敗時所採用之預設錯誤訊息
    /// - Returns: 解析後的錯誤原因字串
    private func parseServerError(from data: Data, defaultMessage: String) -> String {
        /// 用於解析後端錯誤回應格式之內部資料傳輸物件
        struct VaporError: Decodable {
            let reason: String
        }
        if let serverError = try? JSONDecoder().decode(VaporError.self, from: data) {
            return serverError.reason
        }
        return defaultMessage
    }
}
