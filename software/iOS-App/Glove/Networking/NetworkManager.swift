import Foundation

class NetworkManager {
    /// 靜態單例存取點
    static let shared = NetworkManager()
    
    private init() {}

    /// 通用的非同步 API 請求函式
    /// - Parameter urlRequest: 欲發送之 URLRequest 物件
    /// - Returns: 解碼後之 Decodable 目標型態物件
    func request<T: Decodable>(_ urlRequest: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw Validation.server(message: "無法連線至伺服器，請檢查網路狀態")
        }

        // 檢查 HTTP 狀態碼與授權驗證
        if let httpResponse = response as? HTTPURLResponse {
            // 全域統一攔截 401 Unauthorized
            if httpResponse.statusCode == 401 {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .didReceive401Unauthorized,
                        object: nil,
                        userInfo: ["message": "您的帳號已在其他裝置登入，請重新登入。"]
                    )
                }
                throw Validation.server(message: "登入已失效，請重新登入")
            }
            
            // 處理非 2xx 成功範圍之狀態碼
            guard (200...299).contains(httpResponse.statusCode) else {
                throw Validation.server(message: "伺服器回應異常 (\(httpResponse.statusCode))")
            }
        }

        // 執行 JSON 資料解碼
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw Validation.server(message: "資料解析失敗")
        }
    }
}
