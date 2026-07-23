import Combine
import Foundation
import SwiftData
import SwiftUI

class RegisterViewModel: ObservableObject {
    @Published var name = ""
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var gender: Gender = .unknown
    @Published var birthday =
        Calendar.current.date(byAdding: .year, value: -60, to: Date()) ?? Date()
    @Published var diseaseStage = ""
    @Published var role: Int = 0  // 0: 病患, 1: 照護者

    /// 控制讀取狀態 防重送
    @Published var isLoading = false
    @Published var errorMessage = ""

    // 註冊成功Alert
    @Published var showSuccessAlert = false

    private let repository = AuthRepository()

    @MainActor
    func register(modelContext: ModelContext) async {
        isLoading = true
        errorMessage = ""

        let birthString = birthday.toString(format: "yyyy-MM-dd")

        let request = RegisterData(
            name: name,
            email: email,
            password: password,
            gender: gender.rawValue,
            birth: birthString,
            diseaseStage: diseaseStage,
            role: role
        )

        do {
            // 呼叫 API 並拿回 UserData
            let userData = try await repository.register(request: request)

            // 確保本地只有一個登入使用者：安全地清空舊資料
            let descriptor = FetchDescriptor<UserData>()
            if let oldUsers = try? modelContext.fetch(descriptor) {
                for user in oldUsers {
                    modelContext.delete(user)
                }
            }

            // 插入新登入的使用者資料
            modelContext.insert(userData)

            // 存檔並標記成功
            try modelContext.save()
            self.showSuccessAlert = true
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
