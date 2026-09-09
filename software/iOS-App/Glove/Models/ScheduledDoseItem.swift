import Foundation

/// 封裝單一服藥時間點與對應處方之排程項目
struct ScheduledDoseItem: Identifiable {
    /// 排程項目識別字串
    let id: String

    /// 所屬用藥計畫
    let plan: MedicationPlan

    /// 預計服藥時間字串（例如："08:00"）
    let timeString: String
}
