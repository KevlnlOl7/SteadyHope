import SwiftUI

struct LoginView: View {
    
    @ObservedObject var loginVM: LoginViewModel
    @Environment(\.modelContext) private var modelContext
    
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
            VStack(spacing: 15) {
                Text("歡迎使用＾-＾")
                    .font(.title2)
                    .padding(.bottom, 10)
                
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
                
                VStack(alignment: .leading, spacing: 5) {
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
                .padding(.horizontal, 5)
                
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
                .disabled(loginVM.isLoading)
                
                Spacer()
                
                HStack {
                    Text("還沒有帳號嗎？")
                        .foregroundColor(.secondary)
                    
                    NavigationLink(destination: RegisterView()) {
                        Text("立即註冊")
                            .bold()
                            .foregroundColor(.blue)
                    }
                }
                .font(.subheadline)
                .padding(.bottom, 20)
            }
            .padding()
            .navigationTitle("登入")
        }
    }
}
