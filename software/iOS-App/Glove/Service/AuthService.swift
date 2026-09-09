import Foundation

/// 處理與驗證相關的底層網路通訊服務
class AuthService {
    
    /// 後端 API 的基礎 URL 地址
    private let baseURL = APIConfig.baseURL

    /// 向伺服器發送登入請求
    /// - Parameters:
    ///   - email: 使用者輸入的電子信箱
    ///   - password: 使用者輸入的明文密碼
    /// - Returns: 伺服器回傳的原始 JSON 二進位資料 (Data)
    /// - Throws: Validation 類型的驗證或伺服器錯誤
    func login(email: String, password: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/users/login") else {
            throw Validation.server(message: "URL 格式錯誤")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": email, "password": password]
        request.httpBody = try? JSONEncoder().encode(body)
        
        // 執行請求
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Validation.server(message: "無法連線至伺服器，請檢查網路狀態")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Validation.server(message: "伺服器回應異常")
        }
        
        // 處理狀態碼
        if httpResponse.statusCode == 401 {
            throw Validation.server(message: "帳號或密碼錯誤")
        } else if httpResponse.statusCode != 200 {
            throw Validation.server(message: "登入服務暫時無法使用 (\(httpResponse.statusCode))")
        }

        return data
    }

    /// 向伺服器發送註冊請求
    /// - Parameter request: 包含姓名、信箱、密碼、性別、生日等註冊資訊之物件
    /// - Returns: 註冊成功後轉換為 SwiftData Model 之 UserData 實體
    /// - Throws: Validation 類型的驗證或伺服器錯誤
    func register(request: RegisterData) async throws -> UserData {
        guard let url = URL(string: "\(baseURL)/users/register") else {
            throw Validation.server(message: "URL 格式錯誤")
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
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
            throw Validation.server(message: "無法連線至伺服器")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Validation.server(message: "伺服器回應異常")
        }
        
        // 處理狀態碼
        if httpResponse.statusCode == 409 {
            throw Validation.server(message: "該電子信箱已被註冊")
        } else if ![200, 201].contains(httpResponse.statusCode) {
            throw Validation.server(message: "註冊失敗 (\(httpResponse.statusCode))")
        }
        
        // 解析回傳的資料
        let decoder = JSONDecoder()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        
        do {
            let dto = try decoder.decode(UserDataDTO.self, from: data)
            return dto.toModel()
        } catch {
            print("註冊解析失敗: \(error)")
            throw Validation.server(message: "回傳資料格式異常")
        }
    }

    /// 向伺服器發送個人資料與密碼修改請求
    /// - Parameter request: 欲變更的使用者欄位或新舊密碼資料
    /// - Returns: 伺服器更新完成後回傳的原始 JSON 資料 (Data)
    /// - Throws: Validation 類型的驗證或伺服器錯誤
    func updateProfile(request: UpdateProfileRequestDTO) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/users/profile") else {
            throw Validation.server(message: "URL 格式錯誤")
        }
        guard let token = AuthManager.shared.getToken() else {
            throw Validation.server(message: "權限不足，請重新登入")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "PUT"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            throw Validation.server(message: "資料封裝失敗")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw Validation.server(message: "無法連線至伺服器")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Validation.server(message: "伺服器回應異常")
        }

        if httpResponse.statusCode == 401 {
            throw Validation.server(message: "登入憑證已過期，請重新登入")
        } else if httpResponse.statusCode != 200 {
            throw Validation.server(message: "更新個人資料失敗 (\(httpResponse.statusCode))")
        }

        return data
    }
}

/// 對應後端 API 回傳的錯誤 JSON 格式
struct BackendError: Codable {
    let message: String
}
