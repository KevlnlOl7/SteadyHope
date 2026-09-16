import Foundation

/// 處理與驗證相關的底層網路通訊服務
class AuthAPIService {
    
    /// 後端 API 的基礎 URL 地址
    private let baseURL = APIConfig.baseURL

    /// 向伺服器發送登入請求
    /// - Parameters:
    ///   - email: 使用者輸入的電子信箱
    ///   - password: 使用者輸入的明文密碼
    /// - Returns: 伺服器回傳的原始 JSON 二進位資料 (Data)
    func login(email: String, password: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/users/login") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["email": email, "password": password]
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw NetworkError.encodingFailed
        }

        return try await NetworkManager.shared.requestData(request)
    }

    /// 向伺服器發送註冊請求
    /// - Parameter request: 包含姓名、信箱、密碼、性別、生日等註冊資訊之物件
    /// - Returns: 註冊成功後轉換為 SwiftData Model 之 UserData 實體
    func register(request: RegisterData) async throws -> UserData {
        guard let url = URL(string: "\(baseURL)/users/register") else {
            throw NetworkError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw NetworkError.encodingFailed
        }
        
        let decoder = JSONDecoder()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        
        let dto: UserDataDTO = try await NetworkManager.shared.request(urlRequest, decoder: decoder)
        return dto.toModel()
    }

    /// 向伺服器發送個人資料與密碼修改請求
    /// - Parameter request: 欲變更的使用者欄位或新舊密碼資料
    /// - Returns: 伺服器更新完成後回傳的原始 JSON 資料 (Data)
    func updateProfile(request: UpdateProfileRequestDTO) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/users/profile") else {
            throw NetworkError.invalidURL
        }
        guard let token = AuthManager.shared.getToken() else {
            throw NetworkError.unauthorized
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
            throw NetworkError.encodingFailed
        }

        return try await NetworkManager.shared.requestData(urlRequest)
    }
    
    /// 階段一：發送驗證碼至信箱
    /// - Parameter email: 使用者信箱
    func sendForgotPasswordCode(email: String) async throws {
        guard let url = URL(string: "\(APIConfig.baseURL)/users/forgot-password") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ForgotPasswordRequestDTO(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw NetworkError.encodingFailed
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError(reason: "伺服器無回應")
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errObj = try? JSONDecoder().decode([String: String].self, from: data),
               let reason = errObj["reason"] {
                throw NetworkError.serverError(reason: reason)
            }
            throw NetworkError.serverError(reason: "驗證碼發送失敗，請確認信箱是否正確")
        }
    }
    
    /// 階段二：驗證代碼並重設密碼
    /// - Parameters:
    ///   - email: 使用者信箱
    ///   - code: 6位數驗證碼
    ///   - newPassword: 新密碼
    func resetPasswordWithCode(email: String, code: String, newPassword: String) async throws {
        guard let url = URL(string: "\(APIConfig.baseURL)/users/reset-password") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ResetPasswordWithCodeRequestDTO(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            code: code.trimmingCharacters(in: .whitespacesAndNewlines),
            newPassword: newPassword
        )
        
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw NetworkError.encodingFailed
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError(reason: "伺服器無回應")
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errObj = try? JSONDecoder().decode([String: String].self, from: data),
               let reason = errObj["reason"] {
                throw NetworkError.serverError(reason: reason)
            }
            switch httpResponse.statusCode {
            case 400:
                throw NetworkError.serverError(reason: "密碼強度不足，需至少8碼且包含大小寫英文字母")
            case 401:
                throw NetworkError.serverError(reason: "驗證碼錯誤或已逾期")
            case 404:
                throw NetworkError.serverError(reason: "查無此帳號")
            default:
                throw NetworkError.serverError(reason: "密碼重設失敗，請確認資料正確性")
            }
        }
    }
}
