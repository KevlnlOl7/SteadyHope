import Foundation
import SwiftUI
import Combine
import SwiftData

import Foundation

class LoginViewModel: ObservableObject {
    
    /// 控制讀取狀態 防重送
    @Published var isLoading = false
    
    /// 登入失敗時回傳的錯誤訊息
    @Published var loginError = ""
    
    /// 標記使用者目前是否已通過驗證並成功登入
    @Published var isAuthenticated = false
    
    /// 用戶資料
    @Published var userData: UserData?
    
    // TODO:連資料庫 取得用戶資料
    private let authRepository = AuthRepository()
    
    /// 執行登入驗證邏輯
    /// - Parameters:
    ///   - email: 使用者輸入的帳號
    ///   - password: 使用者輸入的明文密碼
    @MainActor
    func login(email: String, password: String,modelContext: ModelContext) async {
        isLoading = true
        loginError = ""
        do {
            let fetchedData = try await authRepository.login(email: email, password: password)
            
            modelContext.insert(fetchedData)
            try? modelContext.save()
                    
            self.userData = fetchedData
            self.isAuthenticated = true
            } catch let error as Validation {
                self.loginError = error.message
            } catch {
                self.loginError = "原始錯誤：\(error.localizedDescription)"
            }
        isLoading = false
    }
    
    /// 使用者登出
    /// 清除登入狀態與使用者資料
    @MainActor
    func logout() {
        self.isAuthenticated = false
        self.userData = nil
        self.loginError = ""
    }
}
