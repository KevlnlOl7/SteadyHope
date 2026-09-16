import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = ForgotPasswordViewModel()
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // 流程指示器
                        HStack(spacing: 12) {
                            stepIndicator(number: "1", title: "輸入信箱", isActive: viewModel.currentStep == .requestEmail)
                            Rectangle()
                                .fill(AppTheme.cardBorder(for: colorScheme))
                                .frame(height: 2)
                            stepIndicator(number: "2", title: "驗證並重設", isActive: viewModel.currentStep == .verifyAndReset)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        
                        if viewModel.currentStep == .requestEmail {
                            emailStepContent
                        } else {
                            resetStepContent
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("忘記密碼")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .alert("重設成功", isPresented: $viewModel.showSuccessAlert) {
                Button("返回登入") {
                    dismiss()
                }
            } message: {
                Text("您的密碼已重設成功，請使用新密碼登入。")
            }
            .alert("操作失敗", isPresented: $viewModel.showErrorAlert) {
                Button("確定", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }
    
    // 步驟指示圖示
    private func stepIndicator(number: String, title: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isActive ? AppTheme.primary(for: colorScheme) : Color.gray.opacity(0.3))
                    .frame(width: 24, height: 24)
                Text(number)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(title)
                .font(.system(size: 13, weight: isActive ? .bold : .regular))
                .foregroundColor(isActive ? AppTheme.textPrimary(for: colorScheme) : AppTheme.textSecondary(for: colorScheme))
        }
    }
    
    // 階段一表單
    private var emailStepContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("請輸入您註冊的電子信箱")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Text("系統將發送 6 位數重設驗證碼至您的信箱。")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            
            TextField("電子信箱", text: $viewModel.email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(AppTheme.cardBackground(for: colorScheme))
                .cornerRadius(12)
            
            Button {
                Task {
                    await viewModel.sendVerificationCode()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(viewModel.isEmailStepValid ? AppTheme.primary(for: colorScheme) : Color.gray.opacity(0.4))
                        .frame(height: 50)
                    
                    if viewModel.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("發送驗證碼")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .disabled(!viewModel.isEmailStepValid || viewModel.isLoading)
        }
        .padding(.horizontal, 24)
    }
    
    // 階段二表單
    private var resetStepContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("請輸入驗證碼與新密碼")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Text("驗證信已發送至：\(viewModel.email)")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            
            VStack(spacing: 12) {
                TextField("6 位數驗證碼", text: $viewModel.code)
                    .keyboardType(.numberPad)
                    .padding()
                    .background(AppTheme.cardBackground(for: colorScheme))
                    .cornerRadius(12)
                
                SecureField("新密碼（至少8碼，含大小寫英文字母）", text: $viewModel.newPassword)
                    .padding()
                    .background(AppTheme.cardBackground(for: colorScheme))
                    .cornerRadius(12)
                
                SecureField("確認新密碼", text: $viewModel.confirmPassword)
                    .padding()
                    .background(AppTheme.cardBackground(for: colorScheme))
                    .cornerRadius(12)
            }
            
            Button {
                Task {
                    await viewModel.confirmResetPassword()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(viewModel.isResetStepValid ? AppTheme.primary(for: colorScheme) : Color.gray.opacity(0.4))
                        .frame(height: 50)
                    
                    if viewModel.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("確認重設密碼")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .disabled(!viewModel.isResetStepValid || viewModel.isLoading)
            
            Button {
                withAnimation {
                    viewModel.currentStep = .requestEmail
                }
            } label: {
                Text("返回重新輸入信箱")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
    }
}
