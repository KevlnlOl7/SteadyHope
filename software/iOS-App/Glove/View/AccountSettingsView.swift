import SwiftUI

struct AccountSettingsView: View {
    @ObservedObject var loginVM: LoginViewModel

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
        Form {
            accountInfoSection
            bondManagementSection
        }
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

    /// 帳號基本資訊區塊
    private var accountInfoSection: some View {
        Section(header: Text("帳號資訊")) {
            HStack {
                Text("姓名")
                Spacer()
                Text(loginVM.userData?.userName ?? "未填寫")
                    .foregroundColor(.gray)
            }

            HStack {
                Text("電子信箱")
                Spacer()
                Text(loginVM.userData?.email ?? "未讀取到 Email")
                    .foregroundColor(.gray)
            }

            HStack {
                Text("身分角色")
                Spacer()
                Text(isPatient ? "病患本人" : "照護者家屬")
                    .foregroundColor(.gray)
            }
        }
    }

    /// 安全與個人資料設定區塊
    private var securitySection: some View {
        Section(header: Text("安全與個人資料")) {
            NavigationLink {
                EditProfileView(loginVM: loginVM)
            } label: {
                HStack {
                    Image(systemName: "person.text.rectangle")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text("編輯個人資料與修改密碼")
                }
            }
        }
    }

    /// 家屬連動管理區塊
    private var bondManagementSection: some View {
        Section(header: Text("家屬連動管理")) {
            if isCheckStatusLoading {
                HStack {
                    Text("正在檢查連動狀態...")
                        .foregroundColor(.gray)
                    Spacer()
                    ProgressView()
                }
            } else if isPatient {
                patientBondView
            } else {
                caregiverBondView
            }
        }
    }

    /// 病患端連動介面（支援一對多）
    @ViewBuilder
    private var patientBondView: some View {
        Button(action: {
            Task { await generatePairingCodeAction() }
        }) {
            HStack {
                Text("提供配對碼給照護者")
                    .foregroundColor(.primary)
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Text("產生配對碼")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
        }
        .disabled(isLoading)

        if boundCaregivers.isEmpty {
            Text("目前尚未綁定任何照護者")
                .font(.footnote)
                .foregroundColor(.gray)
        } else {
            ForEach(boundCaregivers, id: \.partnerEmail) { caregiver in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(
                                caregiver.partnerName.isEmpty
                                    ? "未具名照護者" : caregiver.partnerName
                            )
                            .font(.body)
                            .bold()

                            HStack(spacing: 4) {
                                Circle()
                                    .frame(width: 6, height: 6)
                                    .foregroundColor(.green)
                                Text("已連接")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }

                        Text(caregiver.partnerEmail)
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        targetCaregiverToUnlink = caregiver
                        showUnlinkConfirmationAlert = true
                    } label: {
                        Text("解除")
                            .font(.caption.bold())
                            .foregroundColor(.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
            .onDelete { indexSet in
                if let firstIndex = indexSet.first {
                    targetCaregiverToUnlink = boundCaregivers[firstIndex]
                    showUnlinkConfirmationAlert = true
                }
            }
        }
    }

    /// 照護者端連動介面（單一病患）
    @ViewBuilder
    private var caregiverBondView: some View {
        if let patient = boundPatient {
            HStack {
                Text("連動狀態")
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

            HStack {
                Text("被照護者姓名")
                Spacer()
                Text(patient.partnerName)
                    .foregroundColor(.gray)
            }

            HStack {
                Text("被照護者信箱")
                Spacer()
                Text(patient.partnerEmail)
                    .foregroundColor(.gray)
            }

            Button(role: .destructive) {
                showUnlinkConfirmationAlert = true
            } label: {
                HStack {
                    Spacer()
                    Text("解除與被照護者的連動")
                        .bold()
                    Spacer()
                }
            }
        } else {
            HStack {
                Image(systemName: "envelope")
                    .foregroundColor(.gray)
                    .frame(width: 24)
                TextField("請輸入病患的電子信箱", text: $inputPatientEmail)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
            }

            HStack {
                Image(systemName: "key.viewfinder")
                    .foregroundColor(.gray)
                    .frame(width: 24)
                TextField("請輸入 6 位數配對碼", text: $inputPairingCode)
                    .keyboardType(.numberPad)
            }

            Button(action: {
                Task { await linkPatientAction() }
            }) {
                HStack {
                    Spacer()
                    if isLoading {
                        ProgressView().padding(.horizontal, 4)
                    }
                    Text("確認發起安全連動")
                    Spacer()
                }
                .bold()
                .foregroundColor(.white)
            }
            .listRowBackground(
                inputPatientEmail.isEmpty
                    || inputPairingCode.count != 6 || isLoading
                    ? Color.blue.opacity(0.4) : Color.blue
            )
            .disabled(
                inputPatientEmail.isEmpty
                    || inputPairingCode.count != 6 || isLoading
            )
        }
    }

    /// 檢查連動狀態 (GET /users/bonds/caregivers 或 /users/bonds/patient)
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

    /// 病患端產生配對碼 (POST /users/bonds/generate-code)
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

    /// 照護者端執行連動 (POST /users/bonds/link)
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

    /// 執行解除綁定操作 (DELETE /users/bonds/unlink)
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
