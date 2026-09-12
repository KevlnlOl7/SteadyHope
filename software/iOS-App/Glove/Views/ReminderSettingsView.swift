import SwiftUI

struct ReminderSettingsView: View {
    @ObservedObject var planVM: MedicationPlanViewModel
    var currentUserID: Int

    @StateObject private var reminderManager = MedicalReminderManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // 本地暫存設定
    @State private var tempMedReminder: Bool = true
    @State private var tempClinicReminder: Bool = false
    @State private var tempClinicDate: Date = Date()
    @State private var tempAdvanceHours: Int = 2
    @State private var tempRefillReminder: Bool = false
    @State private var tempRefillDate: Date = Date()

    // 震顫待補填提醒暫存
    @State private var tempUnlabeledReminder: Bool = true
    @State private var tempUnlabeledReminderTime: Date = {
        var comps = DateComponents()
        comps.hour = 21
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }()

    // 每日量表評估未填寫提醒暫存
    @State private var tempAssessmentReminder: Bool = true
    @State private var tempAssessmentReminderTime: Date = {
        var comps = DateComponents()
        comps.hour = 20
        comps.minute = 30
        return Calendar.current.date(from: comps) ?? Date()
    }()

    @State private var showSavedAlert: Bool = false
    @State private var showPlanManageSheet: Bool = false

    private let availableAdvanceHours = [1, 2, 3, 4, 5, 6, 8, 12]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                medicationReminderCard
                clinicReminderCard
                refillReminderCard
                assessmentReminderCard
                unlabeledReminderCard
                saveButtonSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(AppTheme.background(for: colorScheme))
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

    /// 用藥提醒卡片
    private var medicationReminderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("用藥提醒")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Toggle("啟用日常服藥提醒", isOn: $tempMedReminder)
                    .tint(AppTheme.primary(for: colorScheme))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .padding(.vertical, 12)

                if tempMedReminder {
                    Divider()

                    Button {
                        showPlanManageSheet = true
                    } label: {
                        HStack {
                            Text("管理每日用藥清單")
                                .font(.body)
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            Spacer()
                            Text("\(planVM.planList.count) 筆")
                                .font(.subheadline)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()
        }
    }

    /// 回診提醒卡片
    private var clinicReminderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("回診提醒")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Toggle("啟用下次回診提醒", isOn: $tempClinicReminder)
                    .tint(AppTheme.primary(for: colorScheme))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .padding(.vertical, 12)

                if tempClinicReminder {
                    Divider()

                    DatePicker(
                        "回診時間",
                        selection: $tempClinicDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .tint(AppTheme.primary(for: colorScheme))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .padding(.vertical, 10)

                    Divider()

                    HStack {
                        Text("提前提醒")
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        Spacer()
                        Picker("", selection: $tempAdvanceHours) {
                            ForEach(availableAdvanceHours, id: \.self) { hours in
                                Text("看診前 \(hours) 小時").tag(hours)
                            }
                        }
                        .tint(AppTheme.primary(for: colorScheme))
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()

            if tempClinicReminder {
                Text("系統將於看診前一天晚上 8 點發送第一次提醒。")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }

    /// 領藥提醒卡片
    private var refillReminderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("慢性病 / 處方箋領藥提醒")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Toggle("啟用下次領藥提醒", isOn: $tempRefillReminder)
                    .tint(AppTheme.primary(for: colorScheme))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .padding(.vertical, 12)

                if tempRefillReminder {
                    Divider()

                    DatePicker(
                        "預計領藥日期",
                        selection: $tempRefillDate,
                        displayedComponents: [.date]
                    )
                    .tint(AppTheme.primary(for: colorScheme))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()

            if tempRefillReminder {
                Text("預計領藥日當天上午 8 點發送提醒。")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }

    /// 每日評估量表提醒卡片
    private var assessmentReminderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("症狀評估每日提醒")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Toggle("啟用量表未填寫提醒", isOn: $tempAssessmentReminder)
                    .tint(AppTheme.primary(for: colorScheme))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .padding(.vertical, 12)

                if tempAssessmentReminder {
                    Divider()

                    DatePicker(
                        "提醒時間",
                        selection: $tempAssessmentReminderTime,
                        displayedComponents: [.hourAndMinute]
                    )
                    .tint(AppTheme.primary(for: colorScheme))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()

            if tempAssessmentReminder {
                Text("若當日尚未填寫評估量表，系統將於設定時間推播提醒。")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }

    /// 震顫事件紀錄提醒卡片
    private var unlabeledReminderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("震顫事件紀錄提醒")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                Toggle("啟用未標記事件每日提醒", isOn: $tempUnlabeledReminder)
                    .tint(AppTheme.primary(for: colorScheme))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .padding(.vertical, 12)

                if tempUnlabeledReminder {
                    Divider()

                    DatePicker(
                        "提醒時間",
                        selection: $tempUnlabeledReminderTime,
                        displayedComponents: [.hourAndMinute]
                    )
                    .tint(AppTheme.primary(for: colorScheme))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()

            if tempUnlabeledReminder {
                Text("若當日或過往有顯著震顫事件尚未標記情境，系統將於設定時間推播提醒補填。")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
        }
    }

    /// 儲存設定按鈕
    private var saveButtonSection: some View {
        Button(action: saveSettings) {
            Text("儲存設定")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(colorScheme == .dark ? AppTheme.background(for: colorScheme) : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(AppTheme.primary(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(
                    color: AppTheme.primary(for: colorScheme).opacity(0.25),
                    radius: 8,
                    y: 4
                )
        }
        .padding(.top, 8)
    }

    // 資料載入與儲存邏輯
    private func loadCurrentSettings() {
        tempMedReminder = reminderManager.isMedicationReminderEnabled
        tempClinicReminder = reminderManager.isClinicReminderEnabled
        tempClinicDate = reminderManager.clinicVisitDate
        tempAdvanceHours = reminderManager.clinicReminderAdvanceHours
        tempRefillReminder = reminderManager.isRefillReminderEnabled
        tempRefillDate = reminderManager.refillDate

        tempUnlabeledReminder = reminderManager.isUnlabeledReminderEnabled
        tempUnlabeledReminderTime = reminderManager.unlabeledReminderTime

        tempAssessmentReminder = reminderManager.isDailyAssessmentReminderEnabled
        tempAssessmentReminderTime = reminderManager.dailyAssessmentReminderTime
    }

    private func saveSettings() {
        reminderManager.saveSettings(
            medReminder: tempMedReminder,
            clinicReminder: tempClinicReminder,
            clinicDate: tempClinicDate,
            advanceHours: tempAdvanceHours,
            refillReminder: tempRefillReminder,
            rDate: tempRefillDate,
            unlabeledReminder: tempUnlabeledReminder,
            unlabeledTime: tempUnlabeledReminderTime,
            assessmentReminder: tempAssessmentReminder,
            assessmentTime: tempAssessmentReminderTime
        )

        NotificationScheduler.shared.syncAllReminders(
            reminderManager: reminderManager,
            planVM: planVM
        )

        showSavedAlert = true
    }
}
