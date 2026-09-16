import SwiftUI

struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var hasAttemptedRegister = false
    @State private var showDatePickerSheet = false
    private let diseaseStages = ["未知", "初期", "中期", "後期"]

    // 格式檢查邏輯
    private var isFormValid: Bool {
        !viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty
            && Validator.validateEmail(viewModel.email) == nil
            && Validator.validatePassword(viewModel.password) == nil
            && viewModel.password == viewModel.confirmPassword
            && !viewModel.isLoading
    }

    private var canSubmit: Bool {
        !viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !viewModel.email.isEmpty
            && !viewModel.password.isEmpty
            && !viewModel.confirmPassword.isEmpty
            && !viewModel.isLoading
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        roleSelectionCard
                        accountInfoCard
                        personalInfoCard
                        validationMessageSection
                        submitButtonSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("註冊帳號")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDatePickerSheet) {
                datePickerSheetView
            }
            .onAppear {
                if viewModel.email == "example@mail.com" {
                    viewModel.email = ""
                }
            }
            .alert("註冊成功", isPresented: $viewModel.showSuccessAlert) {
                Button("立即登入") {
                    dismiss()
                }
            } message: {
                Text("歡迎加入！請使用剛剛註冊的帳號與密碼進行登入。")
            }
        }
    }

    private var roleSelectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("使用者身分")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            HStack(spacing: 10) {
                roleCompactButton(
                    title: "病患本人",
                    icon: "heart.text.square.fill",
                    tag: 0,
                    tintColor: AppTheme.primary(for: colorScheme)
                )

                roleCompactButton(
                    title: "照護者家屬",
                    icon: "person.badge.shield.checkmark.fill",
                    tag: 1,
                    tintColor: AppTheme.accent(for: colorScheme)
                )
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(18)
        .softCardShadow()
    }

    private func roleCompactButton(title: String, icon: String, tag: Int, tintColor: Color) -> some View {
        let isSelected = viewModel.role == tag
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                viewModel.role = tag
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? tintColor : AppTheme.textSecondary(for: colorScheme))

                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? AppTheme.textPrimary(for: colorScheme) : AppTheme.textSecondary(for: colorScheme))

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(tintColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(isSelected ? tintColor.opacity(0.12) : AppTheme.background(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? tintColor : Color.clear, lineWidth: 1.2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var accountInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                Text("帳號與安全性")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("電子信箱")
                    .font(.caption.bold())
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                TextField(
                    "",
                    text: $viewModel.email,
                    prompt: Text("請輸入電子信箱").foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))
                )
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled(true)
                .disabled(viewModel.isLoading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.background(for: colorScheme))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .accentColor(AppTheme.primary(for: colorScheme))
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("登入密碼")
                    .font(.caption.bold())
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                SecureField(
                    "",
                    text: $viewModel.password,
                    prompt: Text("至少 6 位字元").foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))
                )
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.none)
                .disabled(viewModel.isLoading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.background(for: colorScheme))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("確認密碼")
                    .font(.caption.bold())
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                SecureField(
                    "",
                    text: $viewModel.confirmPassword,
                    prompt: Text("請再次輸入密碼").foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))
                )
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.none)
                .disabled(viewModel.isLoading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.background(for: colorScheme))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .cornerRadius(10)
            }
        }
        .padding(18)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(18)
        .softCardShadow()
    }

    private var personalInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .foregroundColor(AppTheme.accent(for: colorScheme))
                Text("基本資料")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("真實姓名")
                    .font(.caption.bold())
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                TextField(
                    "",
                    text: $viewModel.name,
                    prompt: Text("請輸入姓名").foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))
                )
                .disabled(viewModel.isLoading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.background(for: colorScheme))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("生理性別")
                    .font(.caption.bold())
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                HStack(spacing: 10) {
                    genderButton(title: "男", gender: .male, icon: "figure.stand")
                    genderButton(title: "女", gender: .female, icon: "figure.stand.dress")
                    genderButton(title: "其他", gender: .other, icon: "person.fill.questionmark")
                }
            }

            if viewModel.role == 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("疾病階段")
                        .font(.caption.bold())
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                    HStack(spacing: 8) {
                        ForEach(diseaseStages, id: \.self) { stage in
                            Button {
                                viewModel.diseaseStage = stage
                            } label: {
                                Text(stage)
                                    .font(.system(size: 13, weight: viewModel.diseaseStage == stage ? .bold : .medium))
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        viewModel.diseaseStage == stage
                                            ? AppTheme.primary(for: colorScheme).opacity(0.18)
                                            : AppTheme.background(for: colorScheme)
                                    )
                                    .foregroundColor(
                                        viewModel.diseaseStage == stage
                                            ? AppTheme.primary(for: colorScheme)
                                            : AppTheme.textSecondary(for: colorScheme)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                viewModel.diseaseStage == stage
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

                        Text(formattedDate(viewModel.birthday))
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.5))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppTheme.background(for: colorScheme))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
        }
        .padding(18)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(18)
        .softCardShadow()
    }

    private var datePickerSheetView: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "選擇出生日期",
                    selection: $viewModel.birthday,
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

    private func genderButton(title: String, gender: Gender, icon: String) -> some View {
        let isSelected = viewModel.gender == gender
        return Button {
            viewModel.gender = gender
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 14, weight: isSelected ? .bold : .medium))
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(isSelected ? AppTheme.primary(for: colorScheme).opacity(0.18) : AppTheme.background(for: colorScheme))
            .foregroundColor(isSelected ? AppTheme.primary(for: colorScheme) : AppTheme.textSecondary(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? AppTheme.primary(for: colorScheme) : Color.clear, lineWidth: 1.2)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "yyyy 年 MM 月 dd 日"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private var validationMessageSection: some View {
        if hasAttemptedRegister || !viewModel.errorMessage.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if hasAttemptedRegister {
                    if let error = Validator.validateEmail(viewModel.email) {
                        Text("• \(error.localizedDescription)")
                    }
                    if let error = Validator.validatePassword(viewModel.password) {
                        Text("• \(error.localizedDescription)")
                    }
                    if viewModel.password != viewModel.confirmPassword {
                        Text("• 兩次輸入的密碼不一致")
                    }
                }
                if !viewModel.errorMessage.isEmpty {
                    Text("• \(viewModel.errorMessage)")
                }
            }
            .font(.footnote)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
        }
    }

    private var submitButtonSection: some View {
        Button(action: {
            hasAttemptedRegister = true
            if isFormValid {
                Task {
                    await viewModel.register(modelContext: modelContext)
                }
            }
        }) {
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(viewModel.isLoading ? "註冊中..." : "建立帳號")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(colorScheme == .dark ? AppTheme.background(for: colorScheme) : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                canSubmit && !viewModel.isLoading
                    ? AppTheme.primary(for: colorScheme)
                    : AppTheme.textSecondary(for: colorScheme).opacity(0.35)
            )
            .cornerRadius(14)
            .shadow(
                color: canSubmit ? AppTheme.primary(for: colorScheme).opacity(0.25) : Color.clear,
                radius: 8, y: 4
            )
        }
        .disabled(!canSubmit || viewModel.isLoading)
    }
}
