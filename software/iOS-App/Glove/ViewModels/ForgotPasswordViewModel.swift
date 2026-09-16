import Foundation
import Combine
import SwiftUI

@MainActor
final class ForgotPasswordViewModel: ObservableObject {
    enum Step {
        case requestEmail
        case verifyAndReset
    }
    
    @Published var currentStep: Step = .requestEmail
    
    // 欄位狀態
    @Published var email: String = ""
    @Published var code: String = ""
    @Published var newPassword: String = ""
    @Published var confirmPassword: String = ""
    
    // UI 狀態
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var showErrorAlert: Bool = false
    @Published var showSuccessAlert: Bool = false
    
    private let repository = AuthRepository()
    
    // 階段一欄位檢查
    var isEmailStepValid: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedEmail.isEmpty && Validator.validateEmail(trimmedEmail) == nil
    }
    
    // 階段二欄位檢查
    var isResetStepValid: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newPassword.isEmpty &&
        !confirmPassword.isEmpty
    }
    
    /// 階段一：送出信箱取得驗證碼
    func sendVerificationCode() async {
        guard isEmailStepValid else {
            errorMessage = "請輸入有效的電子郵件格式"
            showErrorAlert = true
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        do {
            try await repository.sendForgotPasswordCode(email: email)
            isLoading = false
            withAnimation {
                currentStep = .verifyAndReset
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
    
    /// 階段二：驗證碼驗證與密碼重設
    func confirmResetPassword() async {
        guard isResetStepValid else {
            errorMessage = "請完整填寫驗證碼與新密碼"
            showErrorAlert = true
            return
        }
        
        guard newPassword == confirmPassword else {
            errorMessage = "兩次輸入的新密碼不相符"
            showErrorAlert = true
            return
        }
        
        if let passwordError = Validator.validatePassword(newPassword) {
            errorMessage = passwordError.errorDescription ?? "密碼需至少8碼且包含大小寫英文字母"
            showErrorAlert = true
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        do {
            try await repository.resetPasswordWithCode(
                email: email,
                code: code,
                newPassword: newPassword
            )
            isLoading = false
            showSuccessAlert = true
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
}
