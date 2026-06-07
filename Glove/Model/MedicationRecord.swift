import Foundation
import SwiftData

struct MedicationRecord: Identifiable, Codable {

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
}
