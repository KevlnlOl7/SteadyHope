import SwiftUI

struct ReminderSettingsView: View {
    @ObservedObject var planVM: MedicationPlanViewModel
    var currentUserID: Int

    @StateObject private var reminderManager = MedicalReminderManager.shared
    @Environment(\.dismiss) private var dismiss

    // 本地暫存設定
    @State private var tempMedReminder: Bool = true
    @State private var tempClinicReminder: Bool = false
    @State private var tempClinicDate: Date = Date()
    @State private var tempAdvanceHours: Int = 2
    @State private var tempRefillReminder: Bool = false
    @State private var tempRefillDate: Date = Date()

    @State private var showSavedAlert: Bool = false
    @State private var showPlanManageSheet: Bool = false

    private let availableAdvanceHours = [1, 2, 3, 4, 5, 6, 8, 12]

    var body: some View {
        Form {
            // 用藥提醒設定
            Section(header: Text("用藥提醒")) {
                Toggle("啟用日常服藥提醒", isOn: $tempMedReminder)

                if tempMedReminder {
                    Button(action: {
                        showPlanManageSheet = true
                    }) {
                        HStack {
                            Text("管理每日用藥清單")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(planVM.planList.count) 筆")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            // 回診提醒設定（精簡版）
            Section(
                header: Text("回診提醒"),
                footer: tempClinicReminder ? Text("系統將於看診前一天晚上 8 點發送第一次提醒。") : nil
            ) {
                Toggle("啟用下次回診提醒", isOn: $tempClinicReminder)

                if tempClinicReminder {
                    DatePicker(
                        "回診時間",
                        selection: $tempClinicDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Picker("提前提醒", selection: $tempAdvanceHours) {
                        ForEach(availableAdvanceHours, id: \.self) { hours in
                            Text("看診前 \(hours) 小時").tag(hours)
                        }
                    }
                }
            }

            // 領藥提醒
            Section(
                header: Text("慢性病 / 處方箋領藥提醒"),
                footer: tempRefillReminder ? Text("預計領藥日當天上午 8 點發送提醒。") : nil
            ) {
                Toggle("啟用下次領藥提醒", isOn: $tempRefillReminder)

                if tempRefillReminder {
                    DatePicker(
                        "預計領藥日期",
                        selection: $tempRefillDate,
                        displayedComponents: [.date]
                    )
                }
            }

            // 確定儲存按鈕
            Section {
                Button(action: saveSettings) {
                    Text("儲存設定")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.blue)
            }
        }
        .navigationTitle("提醒設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadCurrentSettings)
        .sheet(isPresented: $showPlanManageSheet) {
            MedicationPlanManageView(
                planVM: planVM,
                currentUserID: currentUserID
            )
        }
        .alert("設定成功", isPresented: $showSavedAlert) {
            Button("確定") {
                dismiss()
            }
        } message: {
            Text("提醒設定已更新完成。")
        }
    }

    // 資料載入與儲存邏輯
    private func loadCurrentSettings() {
        tempMedReminder = reminderManager.isMedicationReminderEnabled
        tempClinicReminder = reminderManager.isClinicReminderEnabled
        tempClinicDate = reminderManager.clinicVisitDate
        tempAdvanceHours = reminderManager.clinicReminderAdvanceHours
        tempRefillReminder = reminderManager.isRefillReminderEnabled
        tempRefillDate = reminderManager.refillDate
    }

    private func saveSettings() {
        reminderManager.saveSettings(
            medReminder: tempMedReminder,
            clinicReminder: tempClinicReminder,
            clinicDate: tempClinicDate,
            advanceHours: tempAdvanceHours,
            refillReminder: tempRefillReminder,
            rDate: tempRefillDate
        )

        NotificationScheduler.shared.syncAllReminders(
            reminderManager: reminderManager,
            planVM: planVM
        )

        showSavedAlert = true
    }
}
