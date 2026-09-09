import Combine
import Foundation
import SwiftData

/// 封裝單一服藥時間點與對應處方之排程項目
struct ScheduledDoseItem: Identifiable {
    /// 排程項目識別字串
    let id: String

    /// 所屬用藥計畫
    let plan: MedicationPlan

    /// 預計服藥時間字串（例如："08:00"）
    let timeString: String
}

@MainActor
final class MedicationPlanViewModel: ObservableObject {
    @Published var planList: [MedicationPlan] = []

    // 處方管理表單屬性
    @Published var planName: String = ""
    @Published var planDose: String = ""
    @Published var planUnit: String = ""
    @Published var planMedType: MedicationType = .oral
    @Published var planPatchRegion: PatchRegion?
    @Published var inputTime: Date = Date()
    @Published var selectedTimes: [Date] = []
    @Published var editingPlanIndex: Int?

    // 重複規律狀態
    @Published var repeatFrequency: RepeatFrequency = .daily
    @Published var customInterval: Int = 1
    @Published var customUnit: CustomRepeatUnit = .day
    @Published var selectedWeekdays: Set<Weekday> = []
    @Published var selectedMonthDays: Set<Int> = []

    private let planRepository = MedicationPlanRepository()

    /// 載入所有用藥計畫清單
    func loadAllPlans() async {
        do {
            let fetchedPlans = try await planRepository.getAllPlans()
            self.planList = fetchedPlans
        } catch {
            print("讀取排程失敗: \(error)")
        }
    }

    /// 儲存或更新當前表單之用藥排程至遠端伺服器
    /// - Parameter currentUserID: 建立或修改此排程之使用者 ID
    func savePlan(currentUserID: Int) {
        let finalName: String
        let doseString: String

        if planMedType == .patch {
            let trimmed = planName.trimmingCharacters(in: .whitespaces)
            finalName = trimmed.isEmpty ? "貼片" : trimmed
            doseString = ""
        } else {
            finalName = planName.trimmingCharacters(in: .whitespaces)
            guard !finalName.isEmpty else { return }
            doseString = planUnit.isEmpty ? planDose : "\(planDose)\(planUnit)"
        }

        let rawTimes: [String]
        if planMedType == .patch {
            rawTimes = [inputTime.toString(format: "HH:mm")]
        } else {
            let timeStrings = selectedTimes.map { $0.toString(format: "HH:mm") }
            rawTimes = timeStrings.isEmpty ? [inputTime.toString(format: "HH:mm")] : timeStrings
        }

        let weekdaysRaw = selectedWeekdays.map { String($0.rawValue) }.sorted().joined(separator: ",")
        let monthDaysRaw = selectedMonthDays.map { String($0) }.sorted().joined(separator: ",")

        let existingPlanID: Int?
        if let editingIndex = editingPlanIndex, editingIndex < planList.count {
            existingPlanID = planList[editingIndex].id
        } else {
            existingPlanID = nil
        }

        let planToSave = MedicationPlan(
            id: existingPlanID,
            userID: currentUserID,
            name: finalName,
            dose: doseString,
            medType: planMedType,
            defaultPatchRegion: planPatchRegion,
            timeSlotsRaw: rawTimes.joined(separator: ","),
            startDate: Date(),
            repeatFrequency: repeatFrequency,
            customInterval: customInterval,
            customUnit: customUnit,
            weekdaysRaw: weekdaysRaw,
            monthDaysRaw: monthDaysRaw
        )

        Task {
            do {
                let success = try await planRepository.savePlan(planToSave)
                if success {
                    await loadAllPlans()
                    resetPlanForm()
                }
            } catch {
                print("儲存排程失敗: \(error)")
            }
        }
    }

    /// 根據清單索引刪除指定的用藥排程
    /// - Parameter index: 欲刪除項目於 planList 中的索引值
    func deletePlan(at index: Int) {
        guard index < planList.count else { return }
        let planToDelete = planList[index]

        guard let planID = planToDelete.id else {
            planList.remove(at: index)
            if editingPlanIndex == index { resetPlanForm() }
            return
        }

        Task {
            do {
                let success = try await planRepository.deletePlan(id: planID)
                if success {
                    planList.remove(at: index)
                    if editingPlanIndex == index {
                        resetPlanForm()
                    }
                }
            } catch {
                print("刪除排程失敗: \(error)")
            }
        }
    }

    /// 是否已存在貼片類型處方
    var hasExistingPatch: Bool {
        planList.contains { $0.medType == .patch }
    }

    /// 貼片處方新增按鈕是否停用
    var isPatchButtonDisabled: Bool {
        planMedType == .patch && hasExistingPatch && editingPlanIndex == nil
    }

    /// 表單輸入內容是否無效
    var isFormInvalid: Bool {
        if planMedType == .oral {
            let isNameEmpty = planName.trimmingCharacters(in: .whitespaces).isEmpty
            let isDoseEmpty = planDose.trimmingCharacters(in: .whitespaces).isEmpty
            let isUnitEmpty = planUnit.trimmingCharacters(in: .whitespaces).isEmpty
            return isNameEmpty || isDoseEmpty || isUnitEmpty
        } else {
            return isPatchButtonDisabled
        }
    }

    /// 自訂重複週期摘要字串
    var customRepeatSummaryText: String {
        switch customUnit {
        case .day:
            return customInterval == 1 ? "每天" : "每 \(customInterval) 天"
        case .week:
            let days = selectedWeekdays.sorted(by: { $0.rawValue < $1.rawValue }).map { $0.shortName }.joined(separator: "、")
            let intervalText = customInterval == 1 ? "每週" : "每 \(customInterval) 週"
            return days.isEmpty ? intervalText : "\(intervalText) (\(days))"
        case .month:
            let days = selectedMonthDays.sorted().map { "\($0)日" }.joined(separator: "、")
            let intervalText = customInterval == 1 ? "每月" : "每 \(customInterval) 個月"
            return days.isEmpty ? intervalText : "\(intervalText) (\(days))"
        }
    }

    /// 自訂重複週期頁尾提示字串
    var customRepeatFooterText: String {
        switch customUnit {
        case .day: return "行程每 \(customInterval) 天重複一次。"
        case .week: return "行程每 \(customInterval) 週重複一次。"
        case .month: return "行程每 \(customInterval) 個月重複一次。"
        }
    }

    /// 推算指定日期之口服藥物排程清單
    /// - Parameter date: 欲推算之目標日期
    /// - Returns: 依時間排序之 ScheduledDoseItem 清單
    func oralDoseItems(for date: Date = Date()) -> [ScheduledDoseItem] {
        var items: [ScheduledDoseItem] = []
        let oralPlans = planList.filter {
            $0.medType == .oral && $0.shouldTakeMedicine(on: date)
        }

        for (planIndex, plan) in oralPlans.enumerated() {
            let times = plan.timeArray
            let planKey = plan.id != nil ? "\(plan.id!)" : "index_\(planIndex)"

            if times.isEmpty {
                let uniqueID = "oral_\(planKey)_\(plan.name)_未設定時間"
                items.append(
                    ScheduledDoseItem(
                        id: uniqueID,
                        plan: plan,
                        timeString: "未設定時間"
                    )
                )
            } else {
                for (timeIndex, time) in times.enumerated() {
                    let uniqueID = "oral_\(planKey)_\(plan.name)_\(time)_\(timeIndex)"
                    items.append(
                        ScheduledDoseItem(
                            id: uniqueID,
                            plan: plan,
                            timeString: time
                        )
                    )
                }
            }
        }
        return items.sorted { $0.timeString < $1.timeString }
    }

    /// 新增服藥時間點至暫存清單
    func addTimePoint() {
        let timeString = inputTime.toString(format: "HH:mm")
        let exists = selectedTimes.contains {
            $0.toString(format: "HH:mm") == timeString
        }
        if !exists {
            selectedTimes.append(inputTime)
            selectedTimes.sort()
        }
    }

    /// 從暫存清單中移除指定服藥時間點
    /// - Parameter time: 欲移除之 Date 實例
    func removeTimePoint(_ time: Date) {
        selectedTimes.removeAll { $0 == time }
    }

    /// 載入既有用藥排程資料至表單以供編輯
    /// - Parameter index: 欲編輯項目於 planList 中的索引值
    func loadPlanForEditing(at index: Int) {
        guard index < planList.count else { return }
        let plan = planList[index]
        editingPlanIndex = index
        planName = plan.name
        let rawDose = plan.dose.trimmingCharacters(in: .whitespaces)
        if let numberMatch = rawDose.range(of: #"^[0-9]+(\.[0-9]+)?"#, options: .regularExpression) {
            self.planDose = String(rawDose[numberMatch])
            self.planUnit = String(rawDose[numberMatch.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            self.planDose = rawDose
            self.planUnit = ""
        }
        
        planMedType = plan.medType
        planPatchRegion = plan.defaultPatchRegion
        repeatFrequency = plan.repeatFrequency
        customInterval = plan.customInterval
        customUnit = plan.customUnit
        selectedWeekdays = plan.selectedWeekdays
        selectedMonthDays = plan.selectedMonthDays

        let timeStrings = plan.timeArray

        if plan.medType == .patch {
            if let date = timeStrings.first?.toDate(format: "HH:mm") {
                inputTime = date
            }
            selectedTimes = []
        } else {
            selectedTimes =
                timeStrings
                .compactMap { $0.toDate(format: "HH:mm") }
                .sorted()
        }
    }

    /// 重設用藥計畫輸入表單為預設狀態
    func resetPlanForm() {
        editingPlanIndex = nil
        planName = ""
        planDose = ""
        planUnit = ""
        planMedType = .oral
        planPatchRegion = nil
        selectedTimes = []
        inputTime = Date()
        repeatFrequency = .daily
        customInterval = 1
        customUnit = .day
        selectedWeekdays = []
        selectedMonthDays = []
    }

    /// 格式化用藥排程之時間點字串
    /// - Parameter plan: 欲格式化之 MedicationPlan 實例
    /// - Returns: 以頓號分隔之時間點字串（若無時間則回傳「未設定時間」）
    func formatPlanTimes(_ plan: MedicationPlan) -> String {
        let times = plan.timeArray
        return times.isEmpty ? "未設定時間" : times.joined(separator: "、")
    }
}
