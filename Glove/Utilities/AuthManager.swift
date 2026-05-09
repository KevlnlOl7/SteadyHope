import Foundation

class AuthManager {
    static let shared = AuthManager()
    
    /// 儲存使用者驗證用的 Token 字串，用於 API 請求時的身份辨識
    private let tokenKey = "user_auth_token"

    func saveToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }

    func getToken() -> String? {
        return UserDefaults.standard.string(forKey: tokenKey)
    }

    func clearToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }
}
