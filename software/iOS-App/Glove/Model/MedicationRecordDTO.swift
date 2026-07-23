import Foundation

/// 專門負責與後端 API 對接的用藥紀錄數據傳輸物件
struct MedicationRecordDTO: Codable {
    var id: Int?
    var userID: Int
    var date: Date
    var name: String
    var dose: String

    /// 將 API 回傳的 DTO 轉化為可存入 SwiftData 本地資料庫的  MedicationRecord 模型
    func toModel() -> MedicationRecord {
        return MedicationRecord(
            id: self.id,
            userID: self.userID,
            date: self.date,
            name: self.name,
            dose: self.dose
        )
    }
}
