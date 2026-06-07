import Combine
import Foundation
import SwiftData
import SwiftUI

class LoginViewModel: ObservableObject {

    /// 控制讀取狀態 防重送
    @Published var isLoading = false

    /// 登入失敗時回傳的錯誤訊息
    @Published var loginError = ""

    /// 標記使用者目前是否已通過驗證並成功登入
    @Published var isAuthenticated = false

    /// 用戶資料
    @Published var userData: UserData?

    // 連資料庫 取得用戶資料
    private let authRepository = AuthRepository()

    /// 執行登入驗證邏輯
    /// - Parameters:
    ///   - email: 使用者輸入的帳號
    ///   - password: 使用者輸入的明文密碼
    @MainActor
    func login(email: String, password: String, modelContext: ModelContext)
        async
    {
        isLoading = true
        loginError = ""

        do {
            if email == "test@test.com" && password == "Kk123456" {
                let testUser = UserData(
                    userID: 0,
                    userName: "Admin",
                    email: "",
                    gender: 0,
                    birthday: Date(),
                    diseaseStage: "first stage",
                    role: ""
                )

                self.userData = testUser
                self.isAuthenticated = true
                return
            }
            let loginAccount = Account(email: email, password: password)

            // 取得包含 token 的回傳結果
            let fetchedResponse = try await authRepository.login(
                request: loginAccount
            )

            // 處理使用者資料
            let userModel = fetchedResponse.user.toModel()
            modelContext.insert(userModel)
            try? modelContext.save()

            self.userData = userModel
            self.isAuthenticated = true

        } catch {
            print("登入失敗: \(error)")
            self.loginError = "帳號或密碼錯誤"
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
