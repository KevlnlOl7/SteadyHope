import Foundation

/// 病患生成配對碼後，後端回傳的 DTO
struct PairingCodeResponseDTO: Codable {

    /// 系統產生的綁定配對碼
    let pairingCode: String

    /// 配對碼的有效期限與到期時間
    let expiresAt: Date
}

/// 照護者發起綁定時，必須傳送給後端請求的 Body 資料
struct LinkPatientRequestDTO: Codable {

    /// 目標病患的電子郵件
    let patientEmail: String

    /// 病患提供之有效配對碼
    let pairingCode: String
}

/// 綁定成功或查詢綁定狀態時，後端回傳的連動關係資料 DTO
struct LinkedPartnerResponseDTO: Codable {

    /// 綁定關係的唯一識別碼 (Primary Key)
    let bondID: Int

    /// 連動對象的使用者 ID
    let partnerID: Int

    /// 連動對象的姓名
    let partnerName: String

    /// 連動對象的電子郵件
    let partnerEmail: String

    /// 連動對象的身份角色（0: 被照護者 / 患者, 1: 照護者）
    let partnerRole: Int
}
