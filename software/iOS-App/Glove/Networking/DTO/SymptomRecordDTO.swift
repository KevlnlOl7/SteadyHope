import Foundation

/// 負責與後端 API 對接之症狀紀錄資料傳輸物件 (DTO)
struct SymptomRecordDTO: Codable {
    var id: Int?
    var userID: Int
    var date: Date
    var symptomNote: String
    var mediaDataList: [String]
    var isVideo: Bool

    /// 將 DTO 轉換為本機實體模型
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

/// 更新症狀紀錄請求之資料傳輸物件
struct UpdateSymptomRequestDTO: Codable {
    var date: Date?
    var symptomNote: String?
    var mediaDataList: [Data]?
    var isVideo: Bool?
}
