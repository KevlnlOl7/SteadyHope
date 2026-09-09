import Foundation
import SwiftData

@Model
class HealthVitalsRecord: Identifiable {
    
    /// 伺服器端資料庫主鍵識別碼
    var id: Int?

    /// 所屬使用者識別碼
    var userID: Int

    /// 紀錄建立或量測之日期時間
    var date: Date

    /// 收縮壓數值（毫米汞柱，mmHg）
    var systolicBP: String?

    /// 舒張壓數值（毫米汞柱，mmHg）
    var diastolicBP: String?

    /// 血糖數值（毫克/分升，mg/dL）
    var bloodSugar: String?

    /// 體溫數值（攝氏度，°C）
    var bodyTemp: String?

    /// 體重數值（公斤，kg）
    var bodyWeight: String?

    /// 每日睡眠時數（小時）
    var sleepHours: String?

    /// 當日食量與飲食狀況描述
    var foodAmount: String?

    /// 初始化生理數據與日常作息紀錄實體
    /// - Parameters:
    ///   - id: 伺服器端資料庫主鍵識別碼
    ///   - userID: 所屬使用者識別碼
    ///   - date: 紀錄建立或量測之日期時間
    ///   - systolicBP: 收縮壓數值
    ///   - diastolicBP: 舒張壓數值
    ///   - bloodSugar: 血糖數值
    ///   - bodyTemp: 體溫數值
    ///   - bodyWeight: 體重數值
    ///   - sleepHours: 每日睡眠時數
    ///   - foodAmount: 當日食量與飲食狀況描述
    init(
        id: Int? = nil,
        userID: Int,
        date: Date = Date(),
        systolicBP: String? = nil,
        diastolicBP: String? = nil,
        bloodSugar: String? = nil,
        bodyTemp: String? = nil,
        bodyWeight: String? = nil,
        sleepHours: String? = nil,
        foodAmount: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.date = date
        self.systolicBP = systolicBP
        self.diastolicBP = diastolicBP
        self.bloodSugar = bloodSugar
        self.bodyTemp = bodyTemp
        self.bodyWeight = bodyWeight
        self.sleepHours = sleepHours
        self.foodAmount = foodAmount
    }
}
