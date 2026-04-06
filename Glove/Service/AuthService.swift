import Foundation

/// 處理與驗證相關的底層網路通訊服務
class AuthService {
    
    /// 後端 API 的基礎 URL 地址
    private let baseURL = APIConfig.baseURL
    
    /// 向伺服器發送登入請求
    /// - Parameters:
    ///   - email: 使用者輸入的電子信箱
    ///   - password: 使用者輸入的明文密碼
    /// - Returns: 登入成功的 UserData 物件
    /// - Throws: Validation 類型的錯誤
    func login(email: String, password: String) async throws -> UserData {
        guard let url = URL(string: "\(baseURL)/users/login") else {
            throw Validation.server(message: "URL 格式錯誤")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["email": email, "password": password]
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
        
        // 解析資料
        let decoder = JSONDecoder()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        
        do {
            let dto = try decoder.decode(UserDataDTO.self, from: data)
            return dto.toModel()
        } catch {
            // 在 Console 印出錯誤
            print("解析失敗原因: \(error)")
            throw Validation.server(message: "使用者資料格式異常，請聯繫管理員")
        }
    }
    
    /// 向伺服器發送註冊請求 (使用包含密碼的 Request)
    /// - Parameter request: 包含姓名、信箱、密碼、性別、生日字串的請求物件
    /// - Returns: 註冊成功後的 UserData 物件
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
}

/// 對應後端 API 回傳的錯誤 JSON 格式
struct BackendError: Codable {
    let message: String
}
