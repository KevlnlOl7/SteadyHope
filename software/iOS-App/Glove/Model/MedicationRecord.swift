import Foundation
import SwiftData

/// 藥品劑型種類分類
enum MedicationType: String, Codable, CaseIterable {
    case oral = "口服"
    case patch = "貼片"
}

/// 藥物貼片黏貼解剖部位
enum PatchRegion: String, Codable, CaseIterable, Identifiable {
    case leftUpperArm = "左上臂"
    case rightUpperArm = "右上臂"
    case leftChest = "左上胸"
    case rightChest = "右上胸"
    case leftAbdomen = "左下腹"
    case rightAbdomen = "右下腹"
    case leftThigh = "左大腿"
    case rightThigh = "右大腿"
    case leftUpperBack = "左上背"
    case rightUpperBack = "右上背"
    case leftWaist = "左腰"
    case rightWaist = "右腰"

    /// 貼片部位 ID
    var id: String { self.rawValue }
}

@Model
class MedicationRecord: Identifiable {
    /// 用藥紀錄 ID
    var id: Int?

    /// 使用者 ID
    var userID: Int

    /// 紀錄時間
    var date: Date

    /// 藥物名稱
    var name: String

    /// 用藥劑量
    var dose: String

    /// 藥品劑型分類
    var medType: MedicationType

    /// 貼片黏貼部位（若非貼片劑型則為 nil）
    var patchRegion: PatchRegion?

    /// 貼片黏貼處皮膚狀況描述（例如：紅腫、發癢、無異狀）
    var skinCondition: String?

    /// 貼片黏貼處皮膚患部照片之二進位資料清單
    var skinImageDataList: [Data]

    /// 初始化用藥紀錄實體模型
    /// - Parameters:
    ///   - id: 用藥紀錄 ID
    ///   - userID: 使用者 ID
    ///   - date: 紀錄時間
    ///   - name: 藥物名稱
    ///   - dose: 用藥劑量
    ///   - medType: 藥品劑型分類
    ///   - patchRegion: 貼片黏貼部位（若非貼片劑型則為 nil）
    ///   - skinCondition: 貼片黏貼處皮膚狀況描述
    ///   - skinImageDataList: 貼片黏貼處皮膚患部照片之二進位資料清單
    init(
        id: Int? = nil,
        userID: Int,
        date: Date = Date(),
        name: String,
        dose: String,
        medType: MedicationType = .oral,
        patchRegion: PatchRegion? = nil,
        skinCondition: String? = nil,
        skinImageDataList: [Data] = []
    ) {
        self.id = id
        self.userID = userID
        self.date = date
        self.name = name
        self.dose = dose
        self.medType = medType
        self.patchRegion = patchRegion
        self.skinCondition = skinCondition
        self.skinImageDataList = skinImageDataList
    }

    /// 將 SwiftData 模型轉換為傳輸用 DTO 以便發送給後端 API
    /// - Returns: 包含 Base64 圖片編碼之 MedicationRecordDTO 實例
    func toDTO() -> MedicationRecordDTO {
        let base64Images = self.skinImageDataList.map {
            $0.base64EncodedString()
        }

        return MedicationRecordDTO(
            id: self.id,
            userID: self.userID,
            date: self.date,
            name: self.name,
            dose: self.dose,
            medType: self.medType.rawValue,
            patchRegion: self.patchRegion?.rawValue,
            skinCondition: self.skinCondition,
            skinImageDataList: base64Images
        )
    }
}
