import Foundation

///驗證與帳號資料的數據存取層
class AuthRepository {
    
    /// 底層網路服務實例
    private let authService = AuthService()
    
    /// 執行登入邏輯
    /// - Parameters:
    ///   - email: 使用者輸入的電子信箱
    ///   - password: 使用者輸入的明文密碼
    /// - Returns: 登入成功的 UserData 物件
    /// - Throws: Validation 類型的錯誤
    func login(email: String, password: String) async throws -> UserData {
        
        // 呼叫底層 Service 獲取資料
        return try await authService.login(email: email, password: password)
    }
}
