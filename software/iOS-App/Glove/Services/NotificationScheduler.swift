import Foundation
import UserNotifications

class NotificationScheduler {
    static let shared = NotificationScheduler()

    /// 請求本地推播通知權限
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                AppLog.error("推播權限請求失敗: \(error)")
            }
        }
    }

    /// 重新同步並註冊所有醫療提醒通知
    /// - Parameters:
    ///   - reminderManager: 醫療提醒設定管理物件
    ///   - planVM: 用藥計畫 ViewModel
    func syncAllReminders(
        reminderManager: MedicalReminderManager,
        planVM: MedicationPlanViewModel
    ) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        if reminderManager.isMedicationReminderEnabled {
            scheduleMedicationNotifications(planVM: planVM)
        }

        if reminderManager.isClinicReminderEnabled {
            scheduleClinicNotifications(
                clinicDate: reminderManager.clinicVisitDate,
                advanceHours: reminderManager.clinicReminderAdvanceHours
            )
        }

        if reminderManager.isRefillReminderEnabled {
            scheduleRefillNotifications(refillDate: reminderManager.refillDate)
        }

        if reminderManager.isDailyAssessmentReminderEnabled {
            scheduleDailyAssessmentReminder(time: reminderManager.dailyAssessmentReminderTime)
        }
    }
    
    /// 排程每日固定用藥通知
    func scheduleMedicationNotifications(planVM: MedicationPlanViewModel) {
        let center = UNUserNotificationCenter.current()

        for plan in planVM.planList {
            guard let planID = plan.id else { continue }

            for timeStr in plan.timeArray {
                let parts = timeStr.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                let hour = parts[0]
                let minute = parts[1]

                let content = UNMutableNotificationContent()
                content.title = "用藥提醒"
                let doseText = plan.dose.isEmpty ? "" : " (\(plan.dose))"
                content.body = "現在是服藥時間，請記得服用：\(plan.name)\(doseText)"
                content.sound = .default

                var dateComponents = DateComponents()
                dateComponents.hour = hour
                dateComponents.minute = minute

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let identifier = "plan_\(planID)_\(timeStr)"
                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }
    
    /// 排程回診提醒通知（包含前一天 20:00 及提前特定小時）
    private func scheduleClinicNotifications(clinicDate: Date, advanceHours: Int) {
        let center = UNUserNotificationCenter.current()

        if let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: clinicDate) {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: dayBefore)
            comps.hour = 20
            comps.minute = 0

            if let triggerDate = Calendar.current.date(from: comps), triggerDate > Date() {
                let content = UNMutableNotificationContent()
                content.title = "回診提醒（明天）"
                content.body = "明天有預約門診，請確認看診時間與攜帶健保卡。"
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let req = UNNotificationRequest(identifier: "clinic_day_before", content: content, trigger: trigger)
                center.add(req)
            }
        }

        if let targetTime = Calendar.current.date(byAdding: .hour, value: -advanceHours, to: clinicDate), targetTime > Date() {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: targetTime)
            let content = UNMutableNotificationContent()
            content.title = "即將看診提醒"
            content.body = "距離預約回診時間還有 \(advanceHours) 小時，請準備出發。"
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "clinic_advance_hours", content: content, trigger: trigger)
            center.add(req)
        }
    }
    
    /// 排程領藥提醒通知（當天早上 08:00）
    private func scheduleRefillNotifications(refillDate: Date) {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: refillDate)
        comps.hour = 8
        comps.minute = 0

        guard let targetDate = Calendar.current.date(from: comps), targetDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "領藥提醒"
        content.body = "今天是預計領藥日，請記得前往藥局或醫院領取處方藥品。"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: "refill_day", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    /// 排程每日症狀評估量表填寫提醒
    private func scheduleDailyAssessmentReminder(time: Date) {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)

        let content = UNMutableNotificationContent()
        content.title = "症狀評估提醒"
        content.body = "今天還沒填寫健康快篩喔！花 1 分鐘記錄今天的身體狀態，協助追蹤病情變化。"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "daily_assessment_reminder",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// 當日完成填寫評估後，取消今天提醒，並重新設定由明日開始生效的循環推播
    func cancelTodayAssessmentReminderIfCompleted(reminderTime: Date = Date()) {
        let center = UNUserNotificationCenter.current()
        // 移除當前循環
        center.removePendingNotificationRequests(withIdentifiers: ["daily_assessment_reminder"])

        // 重新預約每日定時提醒（明日同時間繼續生效）
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: reminderTime)
        let minute = calendar.component(.minute, from: reminderTime)

        let content = UNMutableNotificationContent()
        content.title = "症狀評估提醒"
        content.body = "今天還沒填寫健康快篩喔！花 1 分鐘記錄今天的身體狀態，協助追蹤病情變化。"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "daily_assessment_reminder",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
    
    /// 移除所有用藥計畫推播
    func clearAllMedicationNotifications() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let idsToRemove = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("plan_") || $0.hasPrefix("med_") }
        center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
    }
}
