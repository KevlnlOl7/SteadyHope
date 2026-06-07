import Foundation

/// 專門負責與後端 API 對接的帳號數據傳輸物件 (Data Transfer Object)
struct UserDataDTO: Codable {
    let userID: Int?
    let userName: String?
    let email: String
    let gender: Int
    let birthday: Date?
    let diseaseStage: String?
    let role:String
    
    // 處理後端 JSON 欄位命名不一致
    enum CodingKeys: String, CodingKey {
        case userID = "id"
        case userName = "name"
        case email = "email"
        case gender = "gender"
        case birthday = "birth"
        case diseaseStage = "diseaseStage"
        case role = "role"
    }
    
    /// 將 DTO 轉換為可存入 SwiftData 的 UserData 模型
    func toModel() -> UserData {
        return UserData(
            userID: self.userID ?? 0,
            userName: self.userName ?? "未知用戶",
            email: self.email,
            gender: self.gender,
            birthday: self.birthday ?? Date(),
            diseaseStage: self.diseaseStage ?? "尚未設定",
            role:self.role
        )
    }
}
enum Gender: Int, Codable {
    case unknown = 0
    case male = 1
    case female = 2
    case other = 3
    
    var label: String {
        switch self {
        case .male: return "男"
        case .female: return "女"
        case .other: return "其他"
        case .unknown: return "未設定"
        }
    }
}
