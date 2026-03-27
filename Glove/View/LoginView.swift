import SwiftUI
struct LoginView: View {
    
    /// 使用者輸入信箱
    @State private var email = ""
    
    /// 使用者輸入密碼
    @State private var password = ""

    @StateObject private var loginVM = LoginViewModel()
    @Environment(\.modelContext) private var modelContext
    /// 驗證信箱格式
    private var isEmailValid: Bool {
        Validator.validateEmail(email) == nil
    }
    
    /// 驗證密碼格式
    private var isPasswordValid: Bool {
        Validator.validatePassword(password) == nil
    }
    
    
    // 若格式對，且目前不在讀取狀態
    private var canSubmit: Bool {
        isEmailValid && isPasswordValid && !loginVM.isLoading
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 15) {
                Text("歡迎使用＾-＾")
                
                TextField("帳號", text: $email)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .disabled(loginVM.isLoading)
                
                SecureField("密碼", text: $password)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .disabled(loginVM.isLoading)
                
                // 驗證訊息顯示區
                VStack(alignment: .leading, spacing: 5) {
                    
                    if !email.isEmpty, let error = Validator.validateEmail(email) {
                        Text(error.message)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    if !password.isEmpty, let error = Validator.validatePassword(password) {
                        Text(error.message)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    if !loginVM.loginError.isEmpty {
                        Text(loginVM.loginError)
                            .font(.caption)
                            .bold()
                            .foregroundColor(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 5)
                
                Button(action: {
                    Task {
                        await loginVM.login(
                                            email: email,
                                            password: password,
                                            modelContext: modelContext
                                        )
                            }
                }) {
                    HStack {
                        if loginVM.isLoading {
                            ProgressView()
                                .padding(.horizontal, 5)
                        }
                        Text(loginVM.isLoading ? "登入中..." : "登入")
                    }
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSubmit ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(!canSubmit)
                
                Spacer()
            }
            .padding()
            .navigationTitle("登入")
            .navigationBarBackButtonHidden(true)
            .navigationDestination(isPresented: $loginVM.isAuthenticated) {
                IndexView(loginVM:loginVM)
            }
        }
    }
}

#Preview {
    LoginView()
}
