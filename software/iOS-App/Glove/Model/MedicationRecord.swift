import Foundation
import SwiftData

@Model
class MedicationRecord: Identifiable {

    /// 用藥紀錄ID
    var id: Int?

    /// 用戶ID
    var userID: Int

    /// 紀錄時間
    var date: Date

    /// 藥物名稱
    var name: String

    /// 用藥劑量
    var dose: String

    /// 初始化用藥紀錄模型
    init( id: Int? = nil, userID: Int, date: Date = Date(), name: String, dose: String) {
        self.id = id
        self.userID = userID
        self.date = date
        self.name = name
        self.dose = dose
    }

    /// 將 SwiftData 模型轉換為傳輸用 DTO 以便發送給後端 API
    func toDTO() -> MedicationRecordDTO {
        return MedicationRecordDTO(
            id: self.id,
            userID: self.userID,
            date: self.date,
            name: self.name,
            dose: self.dose
        )
    }
}
