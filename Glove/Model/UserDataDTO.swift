import Foundation

/// 專門負責與後端 API 對接的帳號數據傳輸物件 (Data Transfer Object)
struct UserDataDTO: Codable {
    let userID: Int?
    let userName: String?
    let email: String
    let gender: String?
    let birthday: Date?
    let diseaseStage: String?
    
    // 處理後端 JSON 欄位命名不一致 
    enum CodingKeys: String, CodingKey {
            case userID = "id"
            case userName = "name"
            case email = "email"
            case gender = "gender"
            case birthday = "birth"
            case diseaseStage = "diseaseStage"
        }
    
    /// 將 DTO 轉換為可存入 SwiftData 的 UserData 模型
    func toModel() -> UserData {
            return UserData(
                userID: self.userID ?? 0,
                userName: self.userName ?? "未知用戶",
                email: self.email,
                gender: self.gender ?? "",
                birthday: self.birthday ?? Date(),
                diseaseStage: self.diseaseStage ?? "尚未設定",
            )
        }
}
