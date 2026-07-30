import Foundation

/// 定義全域 401 通知名稱
extension Notification.Name {
    static let didReceive401Unauthorized = Notification.Name("didReceive401Unauthorized")
}

class AuthManager {
    static let shared = AuthManager()

    /// 儲存使用者驗證用的 Token 字串，用於 API 請求時的身份辨識
    private let tokenKey = "user_auth_token"

    // 新增紀錄儲存時間的 Key
    private let saveTimeKey = "token_save_timestamp"

    // 定義過期時間
    private let expirationInterval: TimeInterval = 24 * 60 * 60

    func saveToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        // 存入 Token 的同時，紀錄目前的時間戳記
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: saveTimeKey
        )
    }

    func getToken() -> String? {

        // 取得儲存的時間戳記
        let saveTimestamp = UserDefaults.standard.double(forKey: saveTimeKey)

        // 如果從未儲存過時間，直接視為無效
        guard saveTimestamp > 0 else { return nil }

        // 檢查是否超過 24 小時
        let currentTime = Date().timeIntervalSince1970
        if currentTime - saveTimestamp > expirationInterval {
            print("Token 已過期，執行清除作業")
            clearToken()
            return nil
        }

        // 沒過期，回傳 Token
        return UserDefaults.standard.string(forKey: tokenKey)
    }

    func clearToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: saveTimeKey)
    }
}
