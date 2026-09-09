import Foundation

/// 新增生理量測數據之請求傳輸物件
struct CreateHealthVitalsRequestDTO: Codable {
    var date: Date
    var systolicBP: String?
    var diastolicBP: String?
    var bloodSugar: String?
    var bodyTemp: String?
    var bodyWeight: String?
    var sleepHours: String?
    var foodAmount: String?
}

/// 更新既有生理量測數據之請求傳輸物件
struct UpdateHealthVitalsRequestDTO: Codable {
    var date: Date?
    var systolicBP: String?
    var diastolicBP: String?
    var bloodSugar: String?
    var bodyTemp: String?
    var bodyWeight: String?
    var sleepHours: String?
    var foodAmount: String?
}

/// 伺服器端生理量測數據之回應傳輸物件
struct HealthVitalsResponseDTO: Codable, Identifiable {
    let id: Int?
    let userID: Int
    let date: Date
    let systolicBP: String?
    let diastolicBP: String?
    let bloodSugar: String?
    let bodyTemp: String?
    let bodyWeight: String?
    let sleepHours: String?
    let foodAmount: String?
    let createdAt: Date?

    /// 將回應 DTO 轉換為本機 SwiftData 資料庫實體模型
    /// - Returns: HealthVitalsRecord 實例
    func toModel() -> HealthVitalsRecord {
        HealthVitalsRecord(
            id: id,
            userID: userID,
            date: date,
            systolicBP: systolicBP,
            diastolicBP: diastolicBP,
            bloodSugar: bloodSugar,
            bodyTemp: bodyTemp,
            bodyWeight: bodyWeight,
            sleepHours: sleepHours,
            foodAmount: foodAmount
        )
    }
}
