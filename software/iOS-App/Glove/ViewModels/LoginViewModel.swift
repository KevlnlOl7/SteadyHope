import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class LoginViewModel: ObservableObject {

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

    /// 照護者綁定的病患詳細資料（一對一）
    @Published var boundPartner: LinkedPartnerResponseDTO?

    /// 病患端綁定的照護者列表（一對多）
    @Published var boundCaregivers: [LinkedPartnerResponseDTO] = []

    /// 控制 401 登出提示視窗
    @Published var showSessionExpiredAlert: Bool = false
    @Published var sessionExpiredMessage: String = ""

    private let authRepository = AuthRepository()
    private let tremorRepository: TremorRepositoryProtocol

    /// 病患姓名計算屬性（依當前身分切換呈現對象）
    var partnerName: String {
        if userData?.role == 1 {
            return boundPartner?.partnerName ?? "患者"
        } else {
            return userData?.userName ?? "患者"
        }
    }

    init(tremorRepository: TremorRepositoryProtocol? = nil) {
        self.tremorRepository =
            tremorRepository
            ?? TremorRepository(tokenProvider: {
                AuthManager.shared.getToken()
            })

        // 全域監聽 401 登出通知
        NotificationCenter.default.addObserver(
            forName: .didReceive401Unauthorized,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let strongSelf = self else { return }

            print("[全域廣播] 收到 401 Unauthorized，自動執行登出機制...")
            let message = notification.userInfo?["message"] as? String
                ?? "您的帳號已在其他裝置登入，或登入已過期，請重新登入。"

            Task { @MainActor in
                strongSelf.handleUnauthorizedLogout(message: message)
            }
        }
    }

    /// 載入與確認連動夥伴資料
    func loadPartnerIfNeeded() async {
        guard let role = userData?.role else { return }
        let bondRepo = UserBondRepository()

        do {
            if role == 1 {
                let partner = try await bondRepo.fetchBoundPatientInfo()
                self.boundPartner = partner
                self.isLinked = !partner.partnerEmail.isEmpty
            } else if role == 0 {
                let caregivers = try await bondRepo.fetchBoundCaregivers()
                self.boundCaregivers = caregivers
                self.isLinked = !caregivers.isEmpty
            }
        } catch {
            print("抓取連動夥伴資料失敗: \(error.localizedDescription)")
            self.boundPartner = nil
            self.boundCaregivers = []
            self.isLinked = false
        }
    }

    /// 處理 401 憑證失效或重複登入之登出邏輯
    private func handleUnauthorizedLogout(message: String) {
        self.logout()
        self.isAuthenticated = false
        self.sessionExpiredMessage = message
        self.showSessionExpiredAlert = true
    }

    /// 向伺服器發送請求以更新特定照護者之操作權限設定
    func updateCaregiverPermission(caregiver: PermissionRequestDTO) async {
        do{
            let bondRepo = UserBondRepository()
            try await bondRepo.updateCaregiverPermissions(
                caregiverID: caregiver.caregiverID,
                canManageMedPlan: caregiver.canManageMedPlan ?? false,
                canAddMedRecord: caregiver.canAddMedRecord ?? false
            )
        } catch {
            print("[LoginVM] 更新照護者權限失敗: \(error.localizedDescription)")
        }
    }
    
    /// 執行登入驗證邏輯
    /// - Parameters:
    ///   - email: 使用者帳號信箱
    ///   - password: 密碼
    ///   - modelContext: SwiftData 上下文環境
    func login(email: String, password: String, modelContext: ModelContext) async {
        isLoading = true
        loginError = ""

        do {
            let loginAccount = Account(email: email, password: password)

            // 取得包含 token 的回傳結果
            let fetchedResponse = try await authRepository.login(
                request: loginAccount
            )

            // 寫入新資料前清空本地舊 UserData
            let descriptor = FetchDescriptor<UserData>()
            if let oldUsers = try? modelContext.fetch(descriptor) {
                for user in oldUsers {
                    modelContext.delete(user)
                }
            }

            // 處理並保存使用者資料至 SwiftData
            let userModel = fetchedResponse.user.toModel()
            modelContext.insert(userModel)
            try modelContext.save()

            self.userData = userModel
            self.isAuthenticated = true
            self.isLoading = false

            // 重置 DataViewModel 的 session id，確保登入後即時數據關聯至最新階段
            DataViewModel.shared.currentSessionId = UUID().uuidString
            print("[Auth] 登入成功，已就緒雲端資料庫通道 (User: \(userModel.userName))")

        } catch {
            print("登入失敗: \(error.localizedDescription)")
            self.loginError = "帳號或密碼錯誤"
            self.isLoading = false
        }
    }

    /// 執行更新個人資料與密碼設定
    /// - Parameters:
    ///   - request: 更新資料請求物件
    ///   - modelContext: SwiftData 上下文環境（選填，若傳入則同步寫入資料庫）
    func updateProfile(
        request: UpdateProfileRequestDTO,
        modelContext: ModelContext? = nil
    ) async throws {
        let updatedDTO = try await authRepository.updateProfile(
            request: request
        )

        if let updatedUser = updatedDTO {
            let userModel = updatedUser.toModel()
            self.userData = userModel

            if let modelContext = modelContext {
                let descriptor = FetchDescriptor<UserData>()
                if let oldUsers = try? modelContext.fetch(descriptor) {
                    for user in oldUsers {
                        modelContext.delete(user)
                    }
                }
                modelContext.insert(userModel)
                try? modelContext.save()
            }
        } else if let currentUser = self.userData {
            if let name = request.name {
                currentUser.userName = name
            }
            if let birth = request.birth {
                currentUser.birthday = birth
            }
            if let gender = request.gender {
                currentUser.gender = gender
            }
            if currentUser.role == 0, let stage = request.diseaseStage {
                currentUser.diseaseStage = stage
            }
            self.userData = currentUser
            try? modelContext?.save()
        }
    }

    /// 使用者登出並清除本機快取與權限
    /// - Parameter modelContext: SwiftData 上下文環境（選填）
    func logout(modelContext: ModelContext? = nil) {
        self.isAuthenticated = false
        self.userData = nil
        self.boundPartner = nil
        self.boundCaregivers = []
        self.isLinked = false
        self.loginError = ""
        AuthManager.shared.clearToken()

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
