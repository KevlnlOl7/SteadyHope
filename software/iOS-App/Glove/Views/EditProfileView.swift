import SwiftUI

struct EditProfileView: View {
    @ObservedObject var loginVM: LoginViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    /// 表單編輯狀態
    @State private var name: String = ""
    @State private var birthDate: Date = Date()
    @State private var gender: Int = 1 /// 0: 女, 1: 男, 2: 其他
    @State private var diseaseStage: String = "未知"
    
    /// 密碼變更狀態
    @State private var oldPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmNewPassword: String = ""
    
    /// 介面提示與彈窗狀態
    @State private var showDatePickerSheet: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showSuccessAlert: Bool = false
    
    private let diseaseStages = ["未知", "初期", "中期", "後期"]
    private let authRepo = AuthRepository()
    
    /// 判斷使用者是否有嘗試填寫密碼變更
    private var isAttemptingPasswordChange: Bool {
        !oldPassword.isEmpty || !newPassword.isEmpty || !confirmNewPassword.isEmpty
    }
    
    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    profileHeaderCard
                    basicInfoCard
                    changePasswordCard
                    
                    if let errorMessage = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(errorMessage)
                        }
                        .font(.footnote)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    }
                    
                    Button(action: saveProfile) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isLoading ? "正在儲存..." : "儲存修改")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(colorScheme == .dark ? AppTheme.background(for: colorScheme) : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            isFormValid && !isLoading
                            ? AppTheme.primary(for: colorScheme)
                            : AppTheme.textSecondary(for: colorScheme).opacity(0.35)
                        )
                        .cornerRadius(14)
                        .shadow(
                            color: isFormValid ? AppTheme.primary(for: colorScheme).opacity(0.25) : Color.clear,
                            radius: 8, y: 4
                        )
                    }
                    .disabled(!isFormValid || isLoading)
                    .padding(.top, 6)
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
        }
        .navigationTitle("編輯個人資料")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDatePickerSheet) {
            datePickerSheetView
        }
        .alert("更新成功", isPresented: $showSuccessAlert) {
            Button("確定") {
                if isAttemptingPasswordChange {
                    loginVM.logout()
                } else {
                    dismiss()
                }
            }
        } message: {
            Text(isAttemptingPasswordChange ? "密碼已更新，請使用新密碼重新登入。" : "個人資料已成功儲存。")
        }
        .onAppear {
            loadCurrentUserData()
        }
    }
    
    /// 頂部頭像與基本資訊看板
    private var profileHeaderCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.primary(for: colorScheme).opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: loginVM.userData?.role == 1 ? "person.badge.shield.checkmark.fill" : "person.fill")
                    .font(.system(size: 30))
                    .foregroundColor(AppTheme.primary(for: colorScheme))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(loginVM.userData?.userName ?? "用戶")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                
                Text(loginVM.userData?.email ?? "")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                
                HStack(spacing: 6) {
                    Text(loginVM.userData?.role == 1 ? "照護者家屬" : "病患本人")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.primary(for: colorScheme).opacity(0.15))
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .cornerRadius(6)
                    
                    if loginVM.userData?.role == 0 {
                        Text(diseaseStage)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.accent(for: colorScheme).opacity(0.2))
                            .foregroundColor(AppTheme.accent(for: colorScheme))
                            .cornerRadius(6)
                    }
                }
                .padding(.top, 2)
            }
            Spacer()
        }
        .padding(18)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(18)
        .softCardShadow()
    }
    
    /// 基本資料編輯卡片
    private var basicInfoCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "person.text.rectangle.fill")
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                Text("基本資料")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }
            
            /// 姓名輸入欄位
            VStack(alignment: .leading, spacing: 6) {
                Text("姓名")
                    .font(.caption.bold())
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                TextField("請輸入姓名", text: $name)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppTheme.background(for: colorScheme))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .cornerRadius(10)
            }
            
            /// 性別切換選項
            VStack(alignment: .leading, spacing: 6) {
                Text("性別")
                    .font(.caption.bold())
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                HStack(spacing: 10) {
                    genderOptionButton(title: "男", tag: 1, icon: "figure.stand")
                    genderOptionButton(title: "女", tag: 0, icon: "figure.stand.dress")
                    genderOptionButton(title: "其他", tag: 2, icon: "person.fill.questionmark")
                }
            }
            
            /// 疾病分期設定 (僅限病患角色)
            if loginVM.userData?.role == 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("疾病階段")
                        .font(.caption.bold())
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    
                    HStack(spacing: 8) {
                        ForEach(diseaseStages, id: \.self) { stage in
                            Button {
                                diseaseStage = stage
                            } label: {
                                Text(stage)
                                    .font(.system(size: 13, weight: diseaseStage == stage ? .bold : .medium))
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        diseaseStage == stage
                                        ? AppTheme.primary(for: colorScheme).opacity(0.18)
                                        : AppTheme.background(for: colorScheme)
                                    )
                                    .foregroundColor(
                                        diseaseStage == stage
                                        ? AppTheme.primary(for: colorScheme)
                                        : AppTheme.textSecondary(for: colorScheme)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                diseaseStage == stage
                                                ? AppTheme.primary(for: colorScheme)
                                                : Color.clear,
                                                lineWidth: 1.2
                                            )
                                    )
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            /// 出生日期選擇觸發按鈕
            VStack(alignment: .leading, spacing: 6) {
                Text("出生日期")
                    .font(.caption.bold())
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                
                Button {
                    showDatePickerSheet = true
                } label: {
                    HStack {
                        Image(systemName: "calendar")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                        
                        Text(birthDate.toString(format: "yyyy 年 MM 月 dd 日"))
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppTheme.background(for: colorScheme))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
        }
        .padding(18)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(18)
        .softCardShadow()
    }
    
    /// 修改密碼卡片
    private var changePasswordCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundColor(AppTheme.accent(for: colorScheme))
                Text("修改密碼")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                
                Spacer()
                
                Text("若不變更請留空")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            
            VStack(spacing: 12) {
                customSecureField(title: "目前舊密碼", text: $oldPassword, placeholder: "變更密碼時必填")
                customSecureField(title: "新密碼", text: $newPassword, placeholder: "至少 6 位字元")
                customSecureField(title: "確認新密碼", text: $confirmNewPassword, placeholder: "再次輸入新密碼")
                
                if !newPassword.isEmpty && !confirmNewPassword.isEmpty && newPassword != confirmNewPassword {
                    Text("兩次輸入的新密碼不一致")
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if isAttemptingPasswordChange {
                    Text("密碼變更成功後系統將自動登出其他裝置，需重新登入。")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
        }
        .padding(18)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(18)
        .softCardShadow()
    }
    
    /// 日曆選取彈窗視圖
    private var datePickerSheetView: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "選擇出生日期",
                    selection: $birthDate,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .tint(AppTheme.primary(for: colorScheme))
                .padding()
                
                Spacer()
            }
            .background(AppTheme.background(for: colorScheme))
            .navigationTitle("選擇出生日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        showDatePickerSheet = false
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                }
            }
        }
        .presentationDetents([.medium, .height(480)])
    }
    
    /// 性別單選按鈕元件
    private func genderOptionButton(title: String, tag: Int, icon: String) -> some View {
        Button {
            gender = tag
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 14, weight: gender == tag ? .bold : .medium))
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                gender == tag
                ? AppTheme.primary(for: colorScheme).opacity(0.18)
                : AppTheme.background(for: colorScheme)
            )
            .foregroundColor(
                gender == tag
                ? AppTheme.primary(for: colorScheme)
                : AppTheme.textSecondary(for: colorScheme)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        gender == tag
                        ? AppTheme.primary(for: colorScheme)
                        : Color.clear,
                        lineWidth: 1.2
                    )
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    /// 密碼安全輸入欄位元件
    private func customSecureField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            
            SecureField(
                "",
                text: text,
                prompt: Text(placeholder).foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))
            )
            .textContentType(.oneTimeCode)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.none)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.background(for: colorScheme))
            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            .cornerRadius(10)
        }
    }
    
    /// 載入當前使用者現有資訊至編輯表單
    private func loadCurrentUserData() {
        guard let user = loginVM.userData else { return }
        name = user.userName
        birthDate = user.birthday
        gender = user.gender
        diseaseStage = user.diseaseStage
    }
    
    /// 驗證表單輸入之合法性
    private var isFormValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        
        if isAttemptingPasswordChange {
            guard !oldPassword.isEmpty, !newPassword.isEmpty, !confirmNewPassword.isEmpty else {
                return false
            }
            guard newPassword == confirmNewPassword else {
                return false
            }
        }
        return true
    }
    
    /// 執行儲存個人資料與密碼設定
    private func saveProfile() {
        guard isFormValid else { return }
        isLoading = true
        errorMessage = nil
        
        let requestDTO = UpdateProfileRequestDTO(
            name: name.trimmingCharacters(in: .whitespaces),
            birth: birthDate,
            gender: gender,
            diseaseStage: loginVM.userData?.role == 0 ? diseaseStage : nil,
            oldPassword: isAttemptingPasswordChange ? oldPassword : nil,
            newPassword: isAttemptingPasswordChange ? newPassword : nil
        )
        
        Task {
            do {
                try await loginVM.updateProfile(request: requestDTO)
                self.isLoading = false
                self.showSuccessAlert = true
            } catch {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
