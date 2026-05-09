import SwiftUI

struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    
    // 控制是否按過註冊，按過才顯示紅字
    @State private var hasAttemptedRegister = false

    // 格式檢查邏輯
    private var isFormValid: Bool {
        !viewModel.name.isEmpty &&
        Validator.validateEmail(viewModel.email) == nil &&
        Validator.validatePassword(viewModel.password) == nil &&
        viewModel.password == viewModel.confirmPassword
    }
    
    // 若不為空，且目前不在讀取狀態
    private var canSubmit: Bool {
        !viewModel.name.isEmpty &&
        !viewModel.email.isEmpty &&
        !viewModel.password.isEmpty &&
        !viewModel.confirmPassword.isEmpty &&
        !viewModel.isLoading
    }

    var body: some View {
            NavigationStack {
                Form {
                    // 帳號設定
                    Section(header: Text("帳號設定")) {
                        TextField("電子信箱", text: $viewModel.email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disabled(viewModel.isLoading)
                        
                        SecureField("密碼", text: $viewModel.password)
                            .textContentType(.oneTimeCode)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.none)
                        
                        SecureField("確認密碼", text: $viewModel.confirmPassword)
                            .textContentType(.oneTimeCode)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.none)
                    }
                    
                    // 基本資料
                    Section(header: Text("基本資料")) {
                        TextField("姓名", text: $viewModel.name)
                            .disabled(viewModel.isLoading)
                        
                        Picker("性別", selection: $viewModel.gender) {
                            Text("男").tag(Gender.male)
                            Text("女").tag(Gender.female)
                            Text("其他").tag(Gender.other)
                        }
                        .pickerStyle(.segmented)
                        
                        Picker("疾病階段", selection: $viewModel.diseaseStage) {
                                Text("未知").tag("未知")
                                Text("初期").tag("初期")
                                Text("中期").tag("中期")
                                Text("後期").tag("後期")
                            }
                        
                        DatePicker("生日", selection: $viewModel.birthday, displayedComponents: .date)
                            .disabled(viewModel.isLoading)
                    }                    
                    Section {
                        
                        // 驗證訊息顯示區
                        VStack(alignment: .leading, spacing: 10) {
                            Group {
                                if hasAttemptedRegister {
                                    if let error = Validator.validateEmail(viewModel.email) { Text(error.localizedDescription) }
                                    if let error = Validator.validatePassword(viewModel.password) { Text(error.localizedDescription) }
                                    if viewModel.password != viewModel.confirmPassword { Text("兩次輸入的密碼不一致") }
                                }
                                if !viewModel.errorMessage.isEmpty {
                                    Text(viewModel.errorMessage).bold()
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.red)

                            // 註冊按鈕
                            Button(action: {
                                hasAttemptedRegister = true
                                if isFormValid {
                                    Task { await viewModel.register(modelContext: modelContext) }
                                }
                            }) {
                                HStack {
                                    if viewModel.isLoading { ProgressView().padding(.horizontal, 5) }
                                    Text(viewModel.isLoading ? "註冊中..." : "完成註冊")
                                }
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(canSubmit ? Color.blue : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(viewModel.isLoading)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 20, trailing: 10))
                }
                .navigationTitle("註冊帳號")
                .navigationBarTitleDisplayMode(.inline)
                .alert("註冊成功", isPresented: $viewModel.showSuccessAlert) {
                    Button("確定") {
                        dismiss()
                    }
                } message: {
                    Text("歡迎加入，請使用新帳號登入系統")
                }
            }
        }
        
    }
