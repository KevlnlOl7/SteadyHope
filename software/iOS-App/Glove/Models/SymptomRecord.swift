import Foundation
import SwiftData

@Model
class SymptomRecord: Identifiable {
    /// 症狀紀錄 ID
    var id: Int?

    /// 使用者 ID
    var userID: Int

    /// 紀錄時間
    var date: Date

    /// 症狀文字描述
    var symptomNote: String

    /// 多媒體二進位資料清單（支援多張照片或影片）
    var mediaDataList: [Data]

    /// 是否為影片格式
    var isVideo: Bool

    /// 首筆多媒體資料（相容舊版本單檔存取）
    var mediaData: Data? {
        mediaDataList.first
    }

    /// 初始化症狀紀錄實體模型
    /// - Parameters:
    ///   - id: 症狀紀錄 ID
    ///   - userID: 使用者 ID
    ///   - date: 紀錄時間
    ///   - symptomNote: 症狀文字描述
    ///   - mediaDataList: 多媒體二進位資料清單
    ///   - isVideo: 是否為影片格式
    init(
        id: Int? = nil,
        userID: Int,
        date: Date = Date(),
        symptomNote: String,
        mediaDataList: [Data] = [],
        isVideo: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.date = date
        self.symptomNote = symptomNote
        self.mediaDataList = mediaDataList
        self.isVideo = isVideo
    }

    /// 將 SwiftData 模型轉換為傳輸用 DTO 以便發送至後端 API
    /// - Returns: 包含 Base64 多媒體編碼之 SymptomRecordDTO 實例
    func toDTO() -> SymptomRecordDTO {
        let base64List = self.mediaDataList.map { $0.base64EncodedString() }

        return SymptomRecordDTO(
            id: self.id,
            userID: self.userID,
            date: self.date,
            symptomNote: self.symptomNote,
            mediaDataList: base64List,
            isVideo: self.isVideo
        )
    }
}
