import Foundation
import SwiftUI
import Combine


class LoginViewModel: ObservableObject {
    
    /// 控制讀取狀態 防重送
    @Published var isLoading = false
    
    /// 登入失敗時回傳的錯誤訊息
    @Published var loginError = ""
    
    /// 標記使用者目前是否已通過驗證並成功登入
    @Published var isAuthenticated = false
    
    /// 暫存登入成功的用戶資訊
    @Published var currentUser: UserData?

    private let mockUser = UserData(
        userID: 1,
        userName: "Admin",
        email: "test@test.com",
        password: "password123",
    )
    
    /// 執行登入驗證邏輯
    /// - Parameters:
    ///   - email: 使用者輸入的帳號
    ///   - password: 使用者輸入的明文密碼
    @MainActor
    func login(email: String, password: String) async {
        isLoading = true
        loginError = ""

        // 先這樣模擬後端驗證邏輯 還沒連資料庫
        if email == mockUser.email && password == mockUser.password {
            self.currentUser = mockUser
            self.isAuthenticated = true
        } else {
            self.loginError = "帳號或密碼錯誤"
        }
        
        isLoading = false
    }
    
    /// 使用者登出
    /// 清除登入狀態與使用者資料
    @MainActor
    func logout() {
        self.isAuthenticated = false
        self.currentUser = nil
        self.loginError = ""
    }
}
