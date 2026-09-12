import SwiftUI

struct AccountSettingsView: View {
    @ObservedObject var loginVM: LoginViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var isLoading: Bool = false
    @State private var isCheckStatusLoading: Bool = false
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var isShowingPairingCodeAlert: Bool = false
    @State private var generatedCode: String = ""

    // 解除綁定二次確認對話框狀態
    @State private var showUnlinkConfirmationAlert: Bool = false
    @State private var targetCaregiverToUnlink: LinkedPartnerResponseDTO? = nil

    private let bondRepo = UserBondRepository()

    // 病患端：多位照護者清單
    @State private var boundCaregivers: [LinkedPartnerResponseDTO] = []

    // 照護者端：單一病患資訊
    @State private var boundPatient: LinkedPartnerResponseDTO? = nil

    // 照護者輸入欄位
    @State private var inputPatientEmail: String = ""
    @State private var inputPairingCode: String = ""

    /// 判斷目前登入身份是否為被照護者（病患）
    private var isPatient: Bool {
        loginVM.userData?.role == 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                accountInfoCard
                securityCard
                bondManagementCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle("連動與帳號管理")
        .alert("您的安全配對碼", isPresented: $isShowingPairingCodeAlert) {
            Button("確定", role: .cancel) {}
        } message: {
            Text("請將此 6 位數驗證碼提供給您的家屬：\n\n\(generatedCode)\n\n有效期限為 10 分鐘。")
                .font(.title2)
        }
        .alert("確認解除連動", isPresented: $showUnlinkConfirmationAlert) {
            Button("取消", role: .cancel) {
                targetCaregiverToUnlink = nil
            }
            Button("確認解除", role: .destructive) {
                Task {
                    await unlinkAction()
                }
            }
        } message: {
            if isPatient {
                Text("確定要解除與照護者 [\(targetCaregiverToUnlink?.partnerName ?? targetCaregiverToUnlink?.partnerEmail ?? "")] 的綁定關係嗎？")
            } else {
                Text("確定要解除與目前被照護者的連動關係嗎？解除後將無法檢視其健康數據。")
            }
        }
        .alert("提示", isPresented: $showAlert) {
            Button("確定", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .task {
            await checkConnectionStatus()
        }
    }

    /// 帳號基本資訊卡片
    private var accountInfoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("帳號資訊")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                HStack {
                    Text("姓名")
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Spacer()
                    Text(loginVM.userData?.userName ?? "未填寫")
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .padding(.vertical, 12)

                Divider()

                HStack {
                    Text("電子信箱")
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Spacer()
                    Text(loginVM.userData?.email ?? "未讀取到 Email")
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .padding(.vertical, 12)

                Divider()

                HStack {
                    Text("身分角色")
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Spacer()
                    Text(isPatient ? "病患本人" : "照護者家屬")
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()
        }
    }

    /// 安全與個人資料卡片
    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("安全與個人資料")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 4)

            NavigationLink {
                EditProfileView(loginVM: loginVM)
            } label: {
                HStack {
                    Image(systemName: "person.text.rectangle")
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .frame(width: 24)
                    Text("編輯個人資料與修改密碼")
                        .font(.body)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()
        }
    }

    /// 家屬連動管理卡片
    private var bondManagementCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("家屬連動管理")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 4)

            if isCheckStatusLoading {
                HStack {
                    Text("正在檢查連動狀態...")
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    Spacer()
                    ProgressView()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppTheme.cardBackground(for: colorScheme))
                .cornerRadius(15)
                .softCardShadow()
            } else if isPatient {
                patientBondView
            } else {
                caregiverBondView
            }
        }
    }

    /// 病患端連動介面卡片（支援一對多）
    @ViewBuilder
    private var patientBondView: some View {
        VStack(spacing: 0) {
            Button(action: {
                Task { await generatePairingCodeAction() }
            }) {
                HStack {
                    Text("提供配對碼給照護者")
                        .font(.body)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("產生配對碼")
                            .font(.subheadline.bold())
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                    }
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            if boundCaregivers.isEmpty {
                Divider()

                HStack {
                    Text("目前尚未綁定任何照護者")
                        .font(.footnote)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                ForEach(Array(boundCaregivers.enumerated()), id: \.element.partnerEmail) { index, caregiver in
                    Divider()

                    NavigationLink {
                        CaregiverDetailSettingsView(
                            caregiver: $boundCaregivers[index],
                            loginVM: loginVM,
                            onUnlink: {
                                targetCaregiverToUnlink = caregiver
                                showUnlinkConfirmationAlert = true
                            }
                        )
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(caregiver.partnerName.isEmpty ? "未具名照護者" : caregiver.partnerName)
                                        .font(.body.bold())
                                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                                    Circle()
                                        .frame(width: 6, height: 6)
                                        .foregroundColor(.green)
                                    Text("已連接")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }

                                Text(caregiver.partnerEmail)
                                    .font(.footnote)
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(15)
        .softCardShadow()
    }

    /// 照護者端連動介面卡片
    @ViewBuilder
    private var caregiverBondView: some View {
        if let patient = boundPatient {
            VStack(spacing: 0) {
                HStack {
                    Text("連動狀態")
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .frame(width: 8, height: 8)
                            .foregroundColor(.green)
                        Text("已連接病患")
                            .bold()
                            .foregroundColor(.green)
                    }
                }
                .padding(.vertical, 12)

                Divider()

                HStack {
                    Text("被照護者姓名")
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Spacer()
                    Text(patient.partnerName)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .padding(.vertical, 12)

                Divider()

                HStack {
                    Text("被照護者信箱")
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Spacer()
                    Text(patient.partnerEmail)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .padding(.vertical, 12)

                Divider()

                Button(role: .destructive) {
                    showUnlinkConfirmationAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Text("解除與被照護者的連動")
                            .font(.body.bold())
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .softCardShadow()
        } else {
            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .frame(width: 24)
                        TextField("請輸入病患的電子信箱", text: $inputPatientEmail)
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                    }
                    .padding(.vertical, 12)

                    Divider()

                    HStack {
                        Image(systemName: "key.viewfinder")
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .frame(width: 24)
                        TextField("請輸入 6 位數配對碼", text: $inputPairingCode)
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .keyboardType(.numberPad)
                    }
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 16)
                .background(AppTheme.cardBackground(for: colorScheme))
                .cornerRadius(15)
                .softCardShadow()

                Button {
                    Task { await linkPatientAction() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView().tint(.white).padding(.trailing, 4)
                        }
                        Text("確認發起安全連動")
                            .font(.system(size: 16, weight: .bold))
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        inputPatientEmail.isEmpty || inputPairingCode.count != 6 || isLoading
                            ? AppTheme.primary(for: colorScheme).opacity(0.4)
                            : AppTheme.primary(for: colorScheme)
                    )
                    .cornerRadius(15)
                    .shadow(
                        color: (inputPatientEmail.isEmpty || inputPairingCode.count != 6 || isLoading)
                            ? Color.clear
                            : AppTheme.primary(for: colorScheme).opacity(0.25),
                        radius: 8,
                        y: 4
                    )
                }
                .disabled(inputPatientEmail.isEmpty || inputPairingCode.count != 6 || isLoading)
            }
        }
    }

    private func checkConnectionStatus() async {
        isCheckStatusLoading = true
        defer { isCheckStatusLoading = false }

        do {
            if isPatient {
                boundCaregivers = try await bondRepo.fetchBoundCaregivers()
            } else {
                let patient = try await bondRepo.fetchBoundPatientInfo()
                boundPatient = patient
                loginVM.boundPartner = patient
                loginVM.isLinked = true
            }
        } catch {
            boundCaregivers = []
            boundPatient = nil
            loginVM.isLinked = false
        }
    }

    private func generatePairingCodeAction() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await bondRepo.requestPairingCode()
            generatedCode = result.pairingCode
            loginVM.userData?.pairingCode = result.pairingCode
            isShowingPairingCodeAlert = true
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func linkPatientAction() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let email = inputPatientEmail.trimmingCharacters(in: .whitespaces)
            let code = inputPairingCode.trimmingCharacters(in: .whitespaces)

            let result = try await bondRepo.linkWithPatient(
                email: email,
                code: code
            )
            boundPatient = result
            loginVM.boundPartner = result
            loginVM.isLinked = true

            alertMessage = "成功與被照護者 [\(result.partnerName)] 完成連動！"
            showAlert = true
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func unlinkAction() async {
        isLoading = true
        defer {
            isLoading = false
            targetCaregiverToUnlink = nil
        }

        do {
            if isPatient {
                if let caregiver = targetCaregiverToUnlink {
                    try await bondRepo.unlinkCaregiver(caregiverEmail: caregiver.partnerEmail)
                    await checkConnectionStatus()
                    alertMessage = "已成功解除與該照護者的連動。"
                }
            } else {
                try await bondRepo.unlinkCurrentPatient()
                boundPatient = nil
                loginVM.boundPartner = nil
                loginVM.isLinked = false
                alertMessage = "已成功解除與病患的連動關係。"
            }
            showAlert = true
        } catch {
            alertMessage = "解除連動失敗：\(error.localizedDescription)"
            showAlert = true
        }
    }
}

struct CaregiverDetailSettingsView: View {
    @Binding var caregiver: LinkedPartnerResponseDTO
    @ObservedObject var loginVM: LoginViewModel
    @Environment(\.colorScheme) private var colorScheme
    var onUnlink: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // 照護者基本資訊卡片
                VStack(alignment: .leading, spacing: 6) {
                    Text("照護者資訊")
                        .font(.caption.bold())
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        HStack {
                            Text("姓名")
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            Spacer()
                            Text(caregiver.partnerName.isEmpty ? "未具名" : caregiver.partnerName)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                        .padding(.vertical, 12)

                        Divider()

                        HStack {
                            Text("電子信箱")
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            Spacer()
                            Text(caregiver.partnerEmail)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                        .padding(.vertical, 12)
                    }
                    .padding(.horizontal, 16)
                    .background(AppTheme.cardBackground(for: colorScheme))
                    .cornerRadius(15)
                    .softCardShadow()
                }

                // 協助權限控管卡片
                VStack(alignment: .leading, spacing: 6) {
                    Text("協助權限控管")
                        .font(.caption.bold())
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        Toggle(
                            "允許協助建立或修改用藥清單",
                            isOn: Binding(
                                get: { caregiver.canManageMedPlan ?? false },
                                set: { newValue in
                                    caregiver.canManageMedPlan = newValue
                                    updatePermissions()
                                }
                            )
                        )
                        .tint(AppTheme.primary(for: colorScheme))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .padding(.vertical, 12)

                        Divider()

                        Toggle(
                            "允許協助新增或修改用藥紀錄",
                            isOn: Binding(
                                get: { caregiver.canAddMedRecord ?? false },
                                set: { newValue in
                                    caregiver.canAddMedRecord = newValue
                                    updatePermissions()
                                }
                            )
                        )
                        .tint(AppTheme.primary(for: colorScheme))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .padding(.vertical, 12)
                    }
                    .padding(.horizontal, 16)
                    .background(AppTheme.cardBackground(for: colorScheme))
                    .cornerRadius(15)
                    .softCardShadow()

                    Text("開啟後，該照護者將能協助您建立用藥清單或新增用藥紀錄。")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                }

                // 解除綁定操作卡片
                Button(role: .destructive) {
                    onUnlink()
                } label: {
                    HStack {
                        Spacer()
                        Text("解除與此照護者的綁定")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(AppTheme.cardBackground(for: colorScheme))
                    .cornerRadius(15)
                    .softCardShadow()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle("照護者設定")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func updatePermissions() {
        let requestDTO = PermissionRequestDTO(
            caregiverID: caregiver.caregiverID ?? 0,
            canManageMedPlan: caregiver.canManageMedPlan,
            canAddMedRecord: caregiver.canAddMedRecord
        )
        Task {
            await loginVM.updateCaregiverPermission(caregiver: requestDTO)
        }
    }
}
