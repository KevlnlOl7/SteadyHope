import Combine
import Foundation
import SwiftUI

/// 醫療相關提醒設定之本機資料持久化與狀態管理中心
@MainActor
final class MedicalReminderManager: ObservableObject {
    static let shared = MedicalReminderManager()

    /// 是否啟用推播提醒開關
    @AppStorage("isMedicationReminderEnabled") var isMedicationReminderEnabled: Bool = true
    @AppStorage("isClinicVisitReminderEnabled") var isClinicReminderEnabled: Bool = false
    @AppStorage("clinicReminderAdvanceHours") var clinicReminderAdvanceHours: Int = 2
    @AppStorage("isRefillReminderEnabled") var isRefillReminderEnabled: Bool = false
    @AppStorage("isUnlabeledReminderEnabled") var isUnlabeledReminderEnabled: Bool = true
    @AppStorage("isDailyAssessmentReminderEnabled") var isDailyAssessmentReminderEnabled: Bool = true

    /// 儲存於本機之時間戳記（秒數）
    @AppStorage("clinicVisitDateTimestamp") private var clinicVisitTimestamp: Double = 0
    @AppStorage("refillDateTimestamp") private var refillTimestamp: Double = 0
    @AppStorage("unlabeledReminderTimestamp") private var unlabeledReminderTimestamp: Double = 0
    @AppStorage("dailyAssessmentReminderTimestamp") private var dailyAssessmentReminderTimestamp: Double = 0

    /// 回診預約日期與時間計算屬性，封裝時間戳記之雙向轉換
    var clinicVisitDate: Date {
        get {
            clinicVisitTimestamp > 0 ? Date(timeIntervalSince1970: clinicVisitTimestamp) : Date()
        }
        set {
            clinicVisitTimestamp = newValue.timeIntervalSince1970
        }
    }

    /// 處方領藥預約日期計算屬性，封裝時間戳記之雙向轉換
    var refillDate: Date {
        get {
            refillTimestamp > 0 ? Date(timeIntervalSince1970: refillTimestamp) : Date()
        }
        set {
            refillTimestamp = newValue.timeIntervalSince1970
        }
    }

    /// 待補填提醒時間計算屬性（預設每日 21:00）
    var unlabeledReminderTime: Date {
        get {
            if unlabeledReminderTimestamp > 0 {
                return Date(timeIntervalSince1970: unlabeledReminderTimestamp)
            } else {
                var comps = DateComponents()
                comps.hour = 21
                comps.minute = 0
                return Calendar.current.date(from: comps) ?? Date()
            }
        }
        set {
            unlabeledReminderTimestamp = newValue.timeIntervalSince1970
        }
    }

    /// 每日量表提醒時間計算屬性（預設每日 20:30）
    var dailyAssessmentReminderTime: Date {
        get {
            if dailyAssessmentReminderTimestamp > 0 {
                return Date(timeIntervalSince1970: dailyAssessmentReminderTimestamp)
            } else {
                var comps = DateComponents()
                comps.hour = 20
                comps.minute = 30
                return Calendar.current.date(from: comps) ?? Date()
            }
        }
        set {
            dailyAssessmentReminderTimestamp = newValue.timeIntervalSince1970
        }
    }

    /// 提供畫面顯示之回診時間格式化字串，未設定或未開啟時呈現「未設定」
    var clinicVisitDisplayText: String {
        guard isClinicReminderEnabled, clinicVisitTimestamp > 0 else {
            return "未設定"
        }
        return clinicVisitDate.toString(format: "yyyy/MM/dd HH:mm")
    }

    /// 提供畫面顯示之領藥時間格式化字串，未設定或未開啟時呈現「未設定」
    var refillDisplayText: String {
        guard isRefillReminderEnabled, refillTimestamp > 0 else {
            return "未設定"
        }
        return refillDate.toString(format: "yyyy/MM/dd")
    }

    /// 一次性更新並儲存所有醫療提醒開關與排程時間設定
    /// - Parameters:
    ///   - medReminder: 是否啟用用藥提醒
    ///   - clinicReminder: 是否啟用回診提醒
    ///   - clinicDate: 回診預約日期時間
    ///   - advanceHours: 回診提早提醒小時數
    ///   - refillReminder: 是否啟用領藥提醒
    ///   - rDate: 領藥預約日期
    ///   - unlabeledReminder: 是否啟用震顫補標記提醒
    ///   - unlabeledTime: 震顫補標記每日提醒時間
    ///   - assessmentReminder: 是否啟用每日量表填寫提醒
    ///   - assessmentTime: 每日量表提醒時間
    func saveSettings(
        medReminder: Bool,
        clinicReminder: Bool,
        clinicDate: Date,
        advanceHours: Int,
        refillReminder: Bool,
        rDate: Date,
        unlabeledReminder: Bool,
        unlabeledTime: Date,
        assessmentReminder: Bool,
        assessmentTime: Date
    ) {
        self.isMedicationReminderEnabled = medReminder
        self.isClinicReminderEnabled = clinicReminder
        self.clinicVisitDate = clinicDate
        self.clinicReminderAdvanceHours = advanceHours
        self.isRefillReminderEnabled = refillReminder
        self.refillDate = rDate
        self.isUnlabeledReminderEnabled = unlabeledReminder
        self.unlabeledReminderTime = unlabeledTime
        self.isDailyAssessmentReminderEnabled = assessmentReminder
        self.dailyAssessmentReminderTime = assessmentTime
    }
}
