import Foundation

/// 負責與後端 API 對接的帳號資料傳輸物件 (DTO)
struct UserDataDTO: Codable {
    let userID: Int?
    let userName: String?
    let email: String
    let gender: Int
    let birthday: Date?
    let diseaseStage: String?
    let role: Int
    let pairingCode: String?
    let avatarData: Data?

    // 處理後端 JSON 欄位命名對應
    enum CodingKeys: String, CodingKey {
        case userID = "id"
        case userName = "name"
        case email = "email"
        case gender = "gender"
        case birthday = "birth"
        case diseaseStage = "diseaseStage"
        case role = "role"
        case pairingCode = "pairingCode"
        case avatarData = "avatarData"
    }

    /// 將 DTO 轉換為本機實體模型
    func toModel() -> UserData {
        UserData(
            userID: self.userID ?? 0,
            userName: self.userName ?? "未知用戶",
            email: self.email,
            gender: self.gender,
            birthday: self.birthday ?? Date(),
            diseaseStage: self.diseaseStage ?? "尚未設定",
            role: self.role,
            pairingCode: self.pairingCode,
            avatarData: self.avatarData
        )
    }
}

/// 更新個人資料請求之資料傳輸物件
struct UpdateProfileRequestDTO: Codable {
    var name: String?
    var birth: Date?
    var gender: Int?
    var diseaseStage: String?
    var oldPassword: String?
    var newPassword: String?
    var avatarData: Data?
}

/// 發送忘記密碼驗證碼 Request
struct ForgotPasswordRequestDTO: Encodable {
    let email: String
}

/// 驗證驗證碼並重設密碼 Request
struct ResetPasswordWithCodeRequestDTO: Encodable {
    let email: String
    let code: String
    let newPassword: String
}
