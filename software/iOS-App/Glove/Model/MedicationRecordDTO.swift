import Foundation

/// 專門負責與後端 API 對接的用藥紀錄數據傳輸物件
struct MedicationRecordDTO: Codable {
    var id: Int?
    var userID: Int?
    var date: Date
    var name: String
    var dose: String
    var medType: String
    var patchRegion: String?
    var skinCondition: String?
    var skinImageDataList: [String]

    /// 將 DTO 轉換為本機 SwiftData 資料庫實體模型
    func toModel() -> MedicationRecord {
        let imageData = self.skinImageDataList.compactMap { Data(base64Encoded: $0) }
        let resolvedPatchRegion = self.patchRegion.flatMap { PatchRegion(rawValue: $0) }

        return MedicationRecord(
            id: self.id,
            userID: self.userID ?? 0,
            date: self.date,
            name: self.name,
            dose: self.dose,
            medType: MedicationType(rawValue: self.medType) ?? .oral,
            patchRegion: resolvedPatchRegion,
            skinCondition: self.skinCondition,
            skinImageDataList: imageData
        )
    }
}
