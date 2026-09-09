import Foundation

/// 病患生成配對碼後，後端回傳的 DTO
struct PairingCodeResponseDTO: Codable {
    /// 系統產生的綁定配對碼
    let pairingCode: String

    /// 配對碼的有效期限與到期時間
    let expiresAt: Date
}

/// 照護者發起綁定時，傳送至後端伺服器的請求 Body 資料
struct LinkPatientRequestDTO: Codable {
    /// 目標病患的電子郵件
    let patientEmail: String

    /// 病患提供之有效配對碼
    let pairingCode: String
}

/// 綁定成功或查詢綁定狀態時，後端回傳的連動關係資料 DTO
struct LinkedPartnerResponseDTO: Codable, Identifiable, Hashable {
    /// 使用 partnerEmail 作為唯一識別碼
    var id: String { partnerEmail }

    /// 連動對象的電子郵件
    let partnerEmail: String

    /// 連動對象的姓名
    let partnerName: String

    /// 綁定關係的唯一識別碼
    let bondID: Int?

    /// 連動對象的使用者 ID
    let partnerID: Int?

    /// 連動對象的身份角色（0: 被照護者 / 患者, 1: 照護者）
    let partnerRole: Int?

    /// 是否允許協助建立與管理用藥清單
    var canManageMedPlan: Bool?

    /// 是否允許協助新增用藥紀錄
    var canAddMedRecord: Bool?
    
    let caregiverID: Int?
}

/// 解除綁定關係請求之資料傳輸物件
struct UnlinkBondRequestDTO: Codable {
    var caregiverEmail: String?
    var caregiverID: Int?
}


// 建立傳遞的 Body 結構
struct PermissionRequestDTO: Encodable {
    let caregiverID: Int
    let canManageMedPlan: Bool?
    let canAddMedRecord: Bool?
}
