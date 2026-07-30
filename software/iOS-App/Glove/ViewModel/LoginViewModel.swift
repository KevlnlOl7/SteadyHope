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
    
    /// 標記照護者目前是否已經成功連接病患
    @Published var isLinked: Bool = false

    // 連資料庫 取得用戶資料
    private let authRepository = AuthRepository()
    
    /// 照護者綁定的病患/連動對象詳細資料
    @Published var boundPartner: LinkedPartnerResponseDTO?
    
    /// 控制 401 登出提示視窗
    @Published var showSessionExpiredAlert: Bool = false
    @Published var sessionExpiredMessage: String = ""

    /// 載入與確認連動夥伴資料
    @MainActor
    func loadPartnerIfNeeded() async {
        // 如果不是照護者 (role != 1)，可以直接 return
        guard userData?.role == 1 else { return }

        do {
            let bondRepo = UserBondRepository()
            let partner = try await bondRepo.fetchMyBoundPartnerInfo()

            self.boundPartner = partner
            self.isLinked = !partner.partnerEmail.isEmpty

        } catch {
            print("抓取連動夥伴資料失敗: \(error.localizedDescription)")
            self.isLinked = false
        }
    }
    
    /// 患者姓名
    var partnerName: String {
        if userData?.role == 1 {
            return boundPartner?.partnerName ?? "患者"
        } else {
            return userData?.userName ?? "患者"
        }
    }
    
    init() {
            // 全域監聽 401 登出通知
            NotificationCenter.default.addObserver(
                forName: .didReceive401Unauthorized,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                print("[全域攔截] 收到 401 Unauthorized，自動執行登出...")
                
                // 取得後端傳來的錯誤訊息，如果沒有就用預設提示
                let message = notification.userInfo?["message"] as? String ?? "您的帳號已在其他裝置登入，或登入已過期，請重新登入。"
                
                DispatchQueue.main.async {
                    self?.handleUnauthorizedLogout(message: message)
                }
            }
        }
    
    /// 處理 401 被踢掉或過期的登出邏輯
        @MainActor
        private func handleUnauthorizedLogout(message: String) {
            // 1. 執行原本的登出邏輯 (清除 Token 與狀態)
            self.logout()
            self.isAuthenticated = false
            // 2. 設定提示訊息並觸發 Alert
            self.sessionExpiredMessage = message
            self.showSessionExpiredAlert = true
        }
    
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
            let loginAccount = Account(email: email, password: password)

            // 取得包含 token 的回傳結果
            let fetchedResponse = try await authRepository.login(
                request: loginAccount
            )

            // 寫入新資料前，先安全地清空本地所有舊的 UserData
            let descriptor = FetchDescriptor<UserData>()
            if let oldUsers = try? modelContext.fetch(descriptor) {
                for user in oldUsers {
                    modelContext.delete(user)
                }
            }

            // 處理使用者資料
            let userModel = fetchedResponse.user.toModel()
            modelContext.insert(userModel)

            try modelContext.save()

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
    /// - Parameter modelContext: 傳入以一併清除本地資料庫的 UserData
    @MainActor
    func logout(modelContext: ModelContext? = nil) {
        self.isAuthenticated = false
        self.userData = nil
        self.isLinked = false
        self.loginError = ""
        AuthManager.shared.clearToken()

        // 如果有傳入 modelContext，一併清空本地資料庫的 UserData
        if let modelContext = modelContext {
            let descriptor = FetchDescriptor<UserData>()
            if let oldUsers = try? modelContext.fetch(descriptor) {
                for user in oldUsers {
                    modelContext.delete(user)
                }
            }
            try? modelContext.save()
        }
    }
}
