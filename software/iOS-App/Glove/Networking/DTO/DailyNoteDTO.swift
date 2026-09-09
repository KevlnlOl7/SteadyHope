import Foundation

/// 用於新增或更新便利貼的 Request 傳輸物件 (發送 POST)
struct DailyRequestDTO: Codable {
    let id: String
    let content: String
    let date: Date
    let colorHex: String
    let sender: String
    let moodName: String?
    let isCaregiverOnly: Bool?
}

/// 用於承接後端回傳 DailyRecord 的 Response 結構 (接收 GET)
struct DailyRecordResponseDTO: Codable {
    let id: String
    let userID: Int
    let content: String
    let date: Date
    let colorHex: String
    let sender: String
    let moodName: String?
    let isCaregiverOnly: Bool?
}
