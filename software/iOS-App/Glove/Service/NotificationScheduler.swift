import Foundation
import UserNotifications

class NotificationScheduler {
    static let shared = NotificationScheduler()

    /// 請求本地推播通知權限
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("推播權限請求失敗: \(error)")
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
    }
    
    /// 排程每日固定用藥通知
    private func scheduleMedicationNotifications(planVM: MedicationPlanViewModel) {
        for plan in planVM.planList {
            for timeStr in plan.timeArray {
                let parts = timeStr.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                let hour = parts[0]
                let minute = parts[1]

                let content = UNMutableNotificationContent()
                content.title = "用藥提醒"
                content.body = "現在是服藥時間，請記得服用：\(plan.name) \(plan.dose)"
                content.sound = .default

                var dateComponents = DateComponents()
                dateComponents.hour = hour
                dateComponents.minute = minute

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "med_\(plan.id ?? 0)_\(timeStr)",
                    content: content,
                    trigger: trigger
                )
                UNUserNotificationCenter.current().add(request)
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
}
