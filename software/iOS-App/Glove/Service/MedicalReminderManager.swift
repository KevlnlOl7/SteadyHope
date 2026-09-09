import Combine
import Foundation
import SwiftUI

/// 醫療相關提醒設定之本機資料持久化與狀態管理中心
@MainActor
final class MedicalReminderManager: ObservableObject {
    static let shared = MedicalReminderManager()

    // 用藥提醒設定
    @AppStorage("isMedicationReminderEnabled") var isMedicationReminderEnabled: Bool = true

    // 下次回診設定
    @AppStorage("clinicVisitDateTimestamp") private var clinicVisitTimestamp: Double = 0
    @AppStorage("isClinicVisitReminderEnabled") var isClinicReminderEnabled: Bool = false
    @AppStorage("clinicReminderAdvanceHours") var clinicReminderAdvanceHours: Int = 2

    // 下次領藥設定
    @AppStorage("refillDateTimestamp") private var refillTimestamp: Double = 0
    @AppStorage("isRefillReminderEnabled") var isRefillReminderEnabled: Bool = false

    /// 回診預約日期與時間
    var clinicVisitDate: Date {
        get {
            clinicVisitTimestamp > 0 ? Date(timeIntervalSince1970: clinicVisitTimestamp) : Date()
        }
        set {
            clinicVisitTimestamp = newValue.timeIntervalSince1970
        }
    }

    /// 處方領藥預約日期
    var refillDate: Date {
        get {
            refillTimestamp > 0 ? Date(timeIntervalSince1970: refillTimestamp) : Date()
        }
        set {
            refillTimestamp = newValue.timeIntervalSince1970
        }
    }

    /// 回診時間格式化文字
    var clinicVisitDisplayText: String {
        guard isClinicReminderEnabled, clinicVisitTimestamp > 0 else {
            return "未設定"
        }
        return clinicVisitDate.toString(format: "yyyy/MM/dd HH:mm")
    }

    /// 領藥時間格式化文字
    var refillDisplayText: String {
        guard isRefillReminderEnabled, refillTimestamp > 0 else {
            return "未設定"
        }
        return refillDate.toString(format: "yyyy/MM/dd")
    }

    /// 一次性更新並儲存所有提醒設定
    /// - Parameters:
    ///   - medReminder: 是否開啟每日用藥提醒
    ///   - clinicReminder: 是否開啟回診提醒
    ///   - clinicDate: 回診預約時間
    ///   - advanceHours: 回診提前提醒時數
    ///   - refillReminder: 是否開啟領藥提醒
    ///   - rDate: 領藥預約日期
    func saveSettings(
        medReminder: Bool,
        clinicReminder: Bool,
        clinicDate: Date,
        advanceHours: Int,
        refillReminder: Bool,
        rDate: Date
    ) {
        self.isMedicationReminderEnabled = medReminder
        self.isClinicReminderEnabled = clinicReminder
        self.clinicVisitDate = clinicDate
        self.clinicReminderAdvanceHours = advanceHours
        self.isRefillReminderEnabled = refillReminder
        self.refillDate = rDate
    }
}
