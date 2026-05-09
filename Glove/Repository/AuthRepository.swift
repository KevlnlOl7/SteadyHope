import Foundation

///驗證與帳號資料的數據存取層
class AuthRepository {
    
    /// 底層網路服務實例
    private let authService = AuthService()
    
    /// 執行登入邏輯
    /// - Parameter request: 登入用的數據傳輸物件 (Account)
    /// - Returns: 登入成功的 UserData 物件
    /// - Throws: Validation 類型的錯誤
    func login(request: Account) async throws -> UserData {
        let data = try await authService.login(email: request.email, password: request.password)
        let decoder = JSONDecoder()
        let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
        decoder.dateDecodingStrategy = .formatted(formatter)
        let response = try decoder.decode(LoginResponseDTO.self, from: data)
        AuthManager.shared.saveToken(response.token)
        return response.user.toModel()
    }
    
    /// 執行註冊邏輯
    /// - Parameter request: 註冊用的數據傳輸物件 (RegisterData)
    /// - Returns: 註冊成功後的 UserData 物件
    func register(request: RegisterData) async throws -> UserData {
        
        // 呼叫底層 Service 獲取資料
        return try await authService.register(request: request)
    }
}
