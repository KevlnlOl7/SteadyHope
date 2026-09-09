import Foundation
import SwiftData

/// 用藥計畫重複週期頻率
enum RepeatFrequency: String, CaseIterable, Identifiable, Codable {
    case never = "永不"
    case daily = "每天"
    case weekly = "每週"
    case biweekly = "每兩週"
    case monthly = "每月"
    case yearly = "每年"
    case custom = "自訂"

    /// 重複週期名稱 ID
    var id: String { rawValue }
}

/// 自訂重複週期時間單位
enum CustomRepeatUnit: String, CaseIterable, Identifiable, Codable {
    case day = "天"
    case week = "週"
    case month = "月"

    /// 自訂時間單位名稱 ID
    var id: String { rawValue }
}

/// 星期（數值對齊 Calendar 星期定義：星期日為 1）
enum Weekday: Int, CaseIterable, Identifiable, Codable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    /// 星期數值 ID
    var id: Int { rawValue }

    /// 星期中文顯示名稱
    var shortName: String {
        switch self {
        case .sunday: return "星期日"
        case .monday: return "星期一"
        case .tuesday: return "星期二"
        case .wednesday: return "星期三"
        case .thursday: return "星期四"
        case .friday: return "星期五"
        case .saturday: return "星期六"
        }
    }
}

struct MedicationPlan: Identifiable, Hashable {
    /// 用藥計畫 ID
    var id: Int?

    /// 使用者 ID
    var userID: Int

    /// 藥物名稱
    var name: String

    /// 用藥劑量
    var dose: String

    /// 藥品劑型分類
    var medType: MedicationType

    /// 預設貼片黏貼部位（若非貼片劑型則為 nil）
    var defaultPatchRegion: PatchRegion?

    /// 服藥時間點原始字串（以逗號分隔，例如："08:00,18:00"）
    var timeSlotsRaw: String

    /// 推算重複週期的起始基準日期
    var startDate: Date

    /// 重複週期頻率
    var repeatFrequency: RepeatFrequency

    /// 自訂重複週期之間隔數值
    var customInterval: Int

    /// 自訂重複週期之時間單位
    var customUnit: CustomRepeatUnit

    /// 勾選之星期原始字串
    var weekdaysRaw: String

    /// 勾選之每月日期原始字串
    var monthDaysRaw: String

    /// 建立者身分角色（0: 患者本人, 1: 照護者）
    var creatorRole: Int?

    init(
        id: Int? = nil,
        userID: Int,
        name: String,
        dose: String,
        medType: MedicationType = .oral,
        defaultPatchRegion: PatchRegion? = nil,
        timeSlotsRaw: String = "",
        startDate: Date = Date(),
        repeatFrequency: RepeatFrequency = .daily,
        customInterval: Int = 1,
        customUnit: CustomRepeatUnit = .day,
        weekdaysRaw: String = "",
        monthDaysRaw: String = "",
        creatorRole: Int? = nil
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.dose = dose
        self.medType = medType
        self.defaultPatchRegion = defaultPatchRegion
        self.timeSlotsRaw = timeSlotsRaw
        self.startDate = startDate
        self.repeatFrequency = repeatFrequency
        self.customInterval = customInterval
        self.customUnit = customUnit
        self.weekdaysRaw = weekdaysRaw
        self.monthDaysRaw = monthDaysRaw
        self.creatorRole = creatorRole
    }

    /// 將 timeSlotsRaw 解析為乾淨的時間點字串陣列
    var timeArray: [String] {
        timeSlotsRaw.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 勾選之星期集合（自動轉換與同步 weekdaysRaw 字串）
    var selectedWeekdays: Set<Weekday> {
        get {
            let ids = weekdaysRaw.components(separatedBy: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return Set(ids.compactMap { Weekday(rawValue: $0) })
        }
        set {
            let sortedRaw = newValue.map { $0.rawValue }.sorted()
            weekdaysRaw = sortedRaw.map { String($0) }.joined(separator: ",")
        }
    }

    /// 勾選之每月特定日期集合（自動轉換與同步 monthDaysRaw 字串）
    var selectedMonthDays: Set<Int> {
        get {
            let days = monthDaysRaw.components(separatedBy: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return Set(days)
        }
        set {
            let sortedDays = newValue.sorted()
            monthDaysRaw = sortedDays.map { String($0) }.joined(separator: ",")
        }
    }

    /// 用於介面呈現之重複規則文字摘要
    var repeatSummary: String {
        switch repeatFrequency {
        case .never:
            return "永不"
        case .daily:
            return "每天"
        case .weekly:
            return "每週"
        case .biweekly:
            return "每兩週"
        case .monthly:
            return "每月"
        case .yearly:
            return "每年"
        case .custom:
            switch customUnit {
            case .day:
                return customInterval == 1 ? "每天" : "每 \(customInterval) 天"
            case .week:
                let days =
                    selectedWeekdays
                    .sorted(by: { $0.rawValue < $1.rawValue })
                    .map { $0.shortName }
                    .joined(separator: "、")
                let intervalText =
                    customInterval == 1 ? "每週" : "每 \(customInterval) 週"
                return days.isEmpty ? intervalText : "\(intervalText) (\(days))"
            case .month:
                let days =
                    selectedMonthDays
                    .sorted()
                    .map { "\($0)日" }
                    .joined(separator: "、")
                let intervalText =
                    customInterval == 1 ? "每月" : "每 \(customInterval) 個月"
                return days.isEmpty ? intervalText : "\(intervalText) (\(days))"
            }
        }
    }

    /// 判斷指定目標日期是否符合服藥排程規則
    func shouldTakeMedicine(on targetDate: Date) -> Bool {
        let calendar = Calendar.current

        let startOfDayTarget = calendar.startOfDay(for: targetDate)
        let startOfDayStart = calendar.startOfDay(for: startDate)
        if startOfDayTarget < startOfDayStart { return false }

        switch repeatFrequency {
        case .never:
            return calendar.isDate(targetDate, inSameDayAs: startDate)

        case .daily:
            return true

        case .weekly:
            let weekdayTarget = calendar.component(.weekday, from: targetDate)
            let weekdayStart = calendar.component(.weekday, from: startDate)
            return weekdayTarget == weekdayStart

        case .biweekly:
            let weekdayTarget = calendar.component(.weekday, from: targetDate)
            let weekdayStart = calendar.component(.weekday, from: startDate)
            guard weekdayTarget == weekdayStart else { return false }
            let days =
                calendar.dateComponents(
                    [.day],
                    from: startOfDayStart,
                    to: startOfDayTarget
                ).day ?? 0
            let weeks = days / 7
            return weeks % 2 == 0

        case .monthly:
            return calendar.component(.day, from: targetDate)
                == calendar.component(.day, from: startDate)

        case .yearly:
            let targetComp = calendar.dateComponents(
                [.month, .day],
                from: targetDate
            )
            let startComp = calendar.dateComponents(
                [.month, .day],
                from: startDate
            )
            return targetComp.month == startComp.month
                && targetComp.day == startComp.day

        case .custom:
            switch customUnit {
            case .day:
                let days =
                    calendar.dateComponents(
                        [.day],
                        from: startOfDayStart,
                        to: startOfDayTarget
                    ).day ?? 0
                return days % customInterval == 0

            case .week:
                let days =
                    calendar.dateComponents(
                        [.day],
                        from: startOfDayStart,
                        to: startOfDayTarget
                    ).day ?? 0
                let weeks = days / 7
                guard weeks % customInterval == 0 else { return false }

                if !selectedWeekdays.isEmpty {
                    let weekdayInt = calendar.component(
                        .weekday,
                        from: targetDate
                    )
                    guard let weekday = Weekday(rawValue: weekdayInt) else {
                        return false
                    }
                    return selectedWeekdays.contains(weekday)
                }
                return true

            case .month:
                let months =
                    calendar.dateComponents(
                        [.month],
                        from: startOfDayStart,
                        to: startOfDayTarget
                    ).month ?? 0
                guard months % customInterval == 0 else { return false }

                if !selectedMonthDays.isEmpty {
                    let day = calendar.component(.day, from: targetDate)
                    return selectedMonthDays.contains(day)
                }
                return true
            }
        }
    }

    /// 將領域模型轉換為資料傳輸物件 (DTO)
    func toDTO() -> MedicationPlanDTO {
        MedicationPlanDTO(
            id: self.id,
            userID: self.userID,
            name: self.name,
            dose: self.dose,
            medType: self.medType,
            defaultPatchRegion: self.defaultPatchRegion,
            timeSlotsRaw: self.timeSlotsRaw,
            startDate: self.startDate,
            repeatFrequency: self.repeatFrequency,
            customInterval: self.customInterval,
            customUnit: self.customUnit,
            weekdaysRaw: self.weekdaysRaw,
            monthDaysRaw: self.monthDaysRaw,
            creatorRole: self.creatorRole
        )
    }
}
