import Foundation

/// 負責與後端 API 對接之症狀紀錄資料傳輸物件 (DTO)
struct SymptomRecordDTO: Codable {
    var id: Int?
    var userID: Int
    var date: Date
    var symptomNote: String
    var mediaDataList: [String]
    var isVideo: Bool

    /// 將 DTO 轉換為本機 SwiftData 資料庫實體模型
    func toModel() -> SymptomRecord {
        let dataList = self.mediaDataList.compactMap { Data(base64Encoded: $0) }
        return SymptomRecord(
            id: self.id,
            userID: self.userID,
            date: self.date,
            symptomNote: self.symptomNote,
            mediaDataList: dataList,
            isVideo: self.isVideo
        )
    }
}
