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

    /// 計算下一個即將到來的服藥時段
    private var nextDoseTimeText: String {
        guard reminderManager.isMedicationReminderEnabled else {
            return "已關閉提醒"
        }

        let now = Date()
        let items = planVM.oralDoseItems(for: now)
        guard !items.isEmpty else {
            return "今日無排程"
        }

        let currentHM = now.toString(format: "HH:mm")
        let allTimes = Array(Set(items.map { $0.timeString }))
            .filter { $0 != "未設定時間" }
            .sorted()

        if let nextTime = allTimes.first(where: { $0 > currentHM }) {
            return nextTime
        } else if !allTimes.isEmpty {
            return "今日已無待服藥物"
        } else {
            return "未設定時間"
        }
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

    /// 提醒日程區塊
    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("提醒日程")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 10)

            VStack(spacing: 8) {
                ReminderCard(
                    icon: "pills.fill",
                    iconColor: .orange,
                    title: "下次用藥時間",
                    timeText: nextDoseTimeText
                )

                ReminderCard(
                    icon: "calendar.badge.clock",
                    iconColor: .blue,
                    title: "下次回診時間",
                    timeText: reminderManager.clinicVisitDisplayText
                )

                ReminderCard(
                    icon: "cross.case.fill",
                    iconColor: .green,
                    title: "下次領藥時間",
                    timeText: reminderManager.refillDisplayText
                )
            }
            .padding(.horizontal, 16)

            Divider().padding(.vertical, 4)
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
                        destination: ReminderSettingsView(
                            planVM: planVM,
                            currentUserID: loginVM.userData?.userID ?? 0
                        )
                    ) {
                        MenuRow(icon: "bell.badge", title: "提醒設定")
                    }

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

// 提醒小卡組件
struct ReminderCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let timeText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.system(size: 18))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(timeText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(red: 0.96, green: 0.96, blue: 0.97))
        .cornerRadius(10)
    }
}

// 選單行組件
struct MenuRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.gray)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
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
