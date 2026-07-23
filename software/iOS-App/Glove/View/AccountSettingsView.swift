import SwiftUI

struct AccountSettingsView: View {
    @ObservedObject var loginVM: LoginViewModel

    @State private var isLoading: Bool = false
    @State private var isCheckStatusLoading: Bool = false
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @State private var isShowingPairingCodeAlert: Bool = false
    @State private var generatedCode: String = ""

    private let bondRepo = UserBondRepository()

    /// 儲存連動對象的電子郵件與姓名
    @State private var boundFamilyEmail: String = ""
    @State private var boundFamilyName: String = ""

    /// 供照護者輸入綁定資料的暫存欄位
    @State private var inputPatientEmail: String = ""
    @State private var inputPairingCode: String = ""

    /// 判斷目前登入身份是否為被照護者（病患）
    private var isPatient: Bool {
        if loginVM.userData?.role == 0 {
            return true
        }
        return false
    }

    /// 判斷是否已成功與家屬連動
    private var isSuccessfullyLinked: Bool {
        return !boundFamilyEmail.isEmpty
    }

    var body: some View {
        Form {
            Section(header: Text("帳號資訊")) {
                HStack {
                    Text("電子信箱")
                    Spacer()
                    Text(loginVM.userData?.email ?? "未讀取到 Email")
                        .foregroundColor(.gray)
                }
            }

            // TODO: 修改密碼邏輯
            Section(header: Text("安全設定")) {
                NavigationLink {
                    Text("這裡放修改密碼的畫面")
                } label: {
                    HStack {
                        Text("修改密碼")
                        Spacer()
                    }
                }
            }

            Section(header: Text("家屬連動")) {
                if isCheckStatusLoading {
                    HStack {
                        Text("正在檢查連動狀態...")
                            .foregroundColor(.gray)
                        Spacer()
                        ProgressView()
                    }
                } else if isSuccessfullyLinked {
                    HStack {
                        Text("連動狀態")
                            .font(.body)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .frame(width: 8, height: 8)
                                .foregroundColor(.green)
                            Text("已連接家屬")
                                .font(.body)
                                .bold()
                                .foregroundColor(.green)
                        }
                    }

                    HStack {
                        Text(isPatient ? "照護者端名稱" : "被照護者名稱")
                            .font(.body)
                        Spacer()
                        Text(boundFamilyName)
                            .font(.body)
                            .foregroundColor(.gray)
                    }

                    HStack {
                        Text(isPatient ? "照護者端信箱" : "被照護者信箱")
                            .font(.body)
                        Spacer()
                        Text(boundFamilyEmail)
                            .font(.body)
                            .foregroundColor(.gray)
                    }
                } else {
                    // 尚未綁定成功的狀態
                    if isPatient {
                        // 病患端：提供產生配對碼按鈕
                        Button(action: {
                            Task {
                                await generatePairingCodeAction()
                            }
                        }) {
                            HStack {
                                Text("提供配對碼給家屬")
                                    .foregroundColor(.primary)
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                } else {
                                    Text("點擊產生")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .disabled(isLoading)
                    } else {
                        // 照護者端：輸入病患信箱與配對碼
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
            }
        }
        .navigationTitle("帳號設定")
        .alert("您的安全配對碼", isPresented: $isShowingPairingCodeAlert) {
            Button("確定", role: .cancel) {}
        } message: {
            Text("請將此 6 位數驗證碼提供給您的家屬：\n\n\(generatedCode)\n\n有效期限為 10 分鐘。")
                .font(.title2)
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

    /// 檢查連動狀態
    private func checkConnectionStatus() async {
        isCheckStatusLoading = true
        defer { isCheckStatusLoading = false }

        do {
            let result = try await bondRepo.fetchMyBoundPartnerInfo()
            boundFamilyEmail = result.partnerEmail
            boundFamilyName = result.partnerName
            loginVM.boundPartner = result
            loginVM.isLinked = !result.partnerEmail.isEmpty
        } catch {
            boundFamilyEmail = ""
            boundFamilyName = ""
            loginVM.isLinked = false
        }
    }

    /// 病患端執行產生配對碼請求
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

    /// 照護者端執行連動綁定請求
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

            boundFamilyEmail = result.partnerEmail
            boundFamilyName = result.partnerName

            loginVM.boundPartner = result
            loginVM.isLinked = !result.partnerEmail.isEmpty

            alertMessage = "成功與被照護者 [\(result.partnerName)] 完成連動！"
            showAlert = true
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}
