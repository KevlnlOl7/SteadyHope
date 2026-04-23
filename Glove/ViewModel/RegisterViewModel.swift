import Foundation
import SwiftUI
import Combine
import SwiftData

class RegisterViewModel: ObservableObject {
    @Published var name = ""
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var gender: Gender = .unknown
    @Published var birthday = Calendar.current.date(byAdding: .year, value: -60, to: Date()) ?? Date()
    
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
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let birthString = formatter.string(from: birthday)
        
        let request = RegisterData(
            name: name,
            email: email,
            password: password,
            gender: gender.rawValue,
            birth: birthString
        )
        
        do {
            // 呼叫 API 並拿回 UserData
            let userData = try await repository.register(request: request)
            
            // 直接存入 SwiftData (唯一儲存)
            // 為確保本地只有一個登入使用者，先清空舊資料
            try? modelContext.delete(model: UserData.self)
            modelContext.insert(userData)
            
            // 存檔並標記成功
            try? modelContext.save()
            self.showSuccessAlert = true
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
