import SwiftUI

struct LoginView: View {
    
    @ObservedObject var loginVM: LoginViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var email = ""
    @State private var password = ""
    @State private var hasAttemptedLogin = false
    
    private var isEmailValid: Bool {
        Validator.validateEmail(email) == nil
    }
    
    private var isPasswordValid: Bool {
        Validator.validatePassword(password) == nil
    }
    
    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !loginVM.isLoading
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Image("SteadyHopeLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 90, height: 90)
                        
                        Text("SteadyHope")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 20)
                    
                    VStack(spacing: 16) {
                        // 帳號輸入框
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .frame(width: 22)
                            
                            TextField("電子信箱", text: $email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                .disabled(loginVM.isLoading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(AppTheme.cardBackground(for: colorScheme))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(hasAttemptedLogin && !isEmailValid ? Color.red.opacity(0.8) : Color.clear, lineWidth: 1)
                        )
                        .softCardShadow()
                        
                        // 密碼輸入框
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .frame(width: 22)
                            
                            SecureField("密碼", text: $password)
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                .disabled(loginVM.isLoading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(AppTheme.cardBackground(for: colorScheme))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(hasAttemptedLogin && !isPasswordValid ? Color.red.opacity(0.8) : Color.clear, lineWidth: 1)
                        )
                        .softCardShadow()
                        
                        // 錯誤訊息提示
                        VStack(alignment: .leading, spacing: 4) {
                            if hasAttemptedLogin {
                                if let error = Validator.validateEmail(email) {
                                    Text(error.localizedDescription)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                
                                if let error = Validator.validatePassword(password) {
                                    Text(error.localizedDescription)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            
                            if !loginVM.loginError.isEmpty {
                                Text(loginVM.loginError)
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        
                        // 登入按鈕
                        Button(action: {
                            self.hideKeyboard()
                            hasAttemptedLogin = true
                            if isEmailValid && isPasswordValid {
                                Task {
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    await loginVM.login(
                                        email: email,
                                        password: password,
                                        modelContext: modelContext
                                    )
                                }
                            }
                        }) {
                            HStack(spacing: 8) {
                                if loginVM.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                                Text(loginVM.isLoading ? "登入中..." : "登入")
                                    .font(.headline)
                                    .bold()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSubmit ? AppTheme.primary(for: colorScheme) : AppTheme.textSecondary(for: colorScheme).opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(loginVM.isLoading || !canSubmit)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text("還沒有帳號嗎？")
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        
                        NavigationLink(destination: RegisterView()) {
                            Text("立即註冊")
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.primary(for: colorScheme))
                        }
                    }
                    .font(.subheadline)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    self.hideKeyboard()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("登入已失效", isPresented: $loginVM.showSessionExpiredAlert) {
            Button("確定", role: .cancel) { }
        } message: {
            Text(loginVM.sessionExpiredMessage)
        }
    }
}
