import Foundation
import SwiftData

@Model
class Daily {
    /// 紀錄唯一識別碼
    var id: String
    
    /// 使用者留言內容
    var content: String
    
    /// 紀錄建立時間
    var date: Date
    
    /// 卡片代表顏色色碼 (Hex String)
    var colorHex: String
    
    /// 發送者標籤或名稱
    var sender: String
    
    /// 心情狀態名稱（如：開心、平靜、疲憊、不舒服）
    var moodName: String?

    /// 初始化每日貼貼紀錄模型
    /// - Parameters:
    ///   - id: 紀錄唯一識別碼（預設為 UUID 字串）
    ///   - content: 使用者留言內容
    ///   - date: 紀錄時間（預設為目前時間）
    ///   - colorHex: 卡片代表顏色 Hex 色碼
    ///   - sender: 發送者標籤
    ///   - moodName: 心情狀態名稱
    init(
        id: String = UUID().uuidString,
        content: String,
        date: Date = Date(),
        colorHex: String,
        sender: String,
        moodName: String? = nil
    ) {
        self.id = id
        self.content = content
        self.date = date
        self.colorHex = colorHex
        self.sender = sender
        self.moodName = moodName
    }
}

extension Daily {
    /// 依據心情狀態名稱對應之 SFSymbols 圖示名稱
    var moodIcon: String {
        switch moodName {
        case "開心": return "face.smiling"
        case "平靜": return "face.dashed"
        case "疲憊": return "zzz"
        case "不舒服": return "thermometer"
        default: return ""
        }
    }
}
