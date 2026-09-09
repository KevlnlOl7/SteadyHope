import SwiftUI

struct ProfileSideMenuView: View {
    @Binding var isOpen: Bool
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var medVM: MedicationViewModel
    @ObservedObject var dataVM: DataViewModel
    @ObservedObject var planVM: MedicationPlanViewModel
    @ObservedObject var symptomVM: SymptomViewModel
    @ObservedObject var vitalsVM: HealthVitalsViewModel
    @StateObject private var reminderManager = MedicalReminderManager.shared

    /// 判斷使用者是否為照護者且尚未綁定被照護者
    private var isUnlinkedCaregiver: Bool {
        let isCaregiver = loginVM.userData?.role == 1
        return isCaregiver && !loginVM.isLinked
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if isOpen {
                // 背景遮罩
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isOpen = false
                        }
                    }

                // 抽屜選單主體
                VStack(alignment: .leading, spacing: 0) {
                    headerView
                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if !isUnlinkedCaregiver {
                                reminderSection
                            }
                            functionAndSettingsSection
                        }
                    }

                    Spacer()

                    logoutButton
                }
                .frame(width: 280)
                .background(Color.white)
                .transition(.move(edge: .leading))
            }
        }
        .task {
            if !isUnlinkedCaregiver {
                await planVM.loadAllPlans()
            }
        }
    }

    /// 使用者頭像與身分資訊
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.gray)

            Text(loginVM.userData?.userName ?? "用戶")
                .font(.system(size: 20, weight: .bold))

            Text(loginVM.userData?.role == 1 ? "照護者" : "使用者")
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.12))
                .foregroundColor(.blue)
                .cornerRadius(6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 50)
        .padding(.bottom, 16)
    }

        }
    }

    /// 功能與設定區塊
    private var functionAndSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("功能與設定")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, isUnlinkedCaregiver ? 10 : 0)

            VStack(spacing: 4) {
                if !isUnlinkedCaregiver {

                    NavigationLink(
                        destination: ExportSettingsView(
                            loginVM: loginVM,
                            medVM: medVM,
                            dataVM: dataVM,
                            symptomVM: symptomVM,
                            vitalsVM: vitalsVM
                        )
                    ) {
                        MenuRow(icon: "square.and.arrow.up", title: "匯出最近資料")
                    }
                }

                NavigationLink(destination: AccountSettingsView(loginVM: loginVM)) {
                    MenuRow(icon: "gearshape", title: "帳號設定")
                }

                NavigationLink(destination: AboutUsView()) {
                    MenuRow(icon: "info.circle", title: "關於我們")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// 登出按鈕
    private var logoutButton: some View {
        Button(action: {
            loginVM.logout()
        }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("登出")
                    .fontWeight(.bold)
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.red.opacity(0.1))
            .cornerRadius(10)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }
}


// 關於我們頁面
struct AboutUsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "heart.text.clipboard.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.blue)

                    Text("健康照護監測系統")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Version 1.0.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("系統簡介")
                            .font(.headline)
                        Text("本系統專為照護者與使用者打造，整合用藥排程、生理量測數據、日常症狀評估與智慧提醒，提供即時、精準的遠距健康追蹤。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("主要特色")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• 智慧用藥與回診提醒")
                            Text("• 生理訊號與動作症狀追蹤")
                            Text("• MDS-UPDRS 臨床症狀自我評估")
                            Text("• 照護者即時狀態連動")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(20)
                .background(Color(red: 0.96, green: 0.96, blue: 0.97))
                .cornerRadius(14)
                .padding(.horizontal, 20)

                Spacer(minLength: 40)
            }
        }
        .background(Color.white)
        .navigationTitle("關於我們")
        .navigationBarTitleDisplayMode(.inline)
    }
}
