import Foundation
import SwiftData

/// 本地儲存的使用者基本資料模型 (SwiftData Model)
@Model
class UserData {

    /// 用戶 ID（設定為唯一主鍵，重複時由 SwiftData 進行覆蓋）
    @Attribute(.unique)
    var userID: Int

    /// 用戶姓名
    var userName: String

    /// 用戶電子郵件
    var email: String

    /// 用戶性別（例如：0: 女性, 1: 男性）
    var gender: Int

    /// 用戶出生日期
    var birthday: Date

    /// 疾病階段描述
    var diseaseStage: String

    /// 登入身份角色（0: 患者 / 被照護者, 1: 照護者）
    var role: Int

    /// 綁定用配對碼（僅在特定狀態或產生配對時存在）
    var pairingCode: String?

    // 頭貼欄位
    @Attribute(.externalStorage) var avatarData: Data?
    
    /// 初始化使用者資料模型
    init( userID: Int, userName: String, email: String, gender: Int, birthday: Date, diseaseStage: String, role: Int, pairingCode: String? = nil, avatarData: Data? = nil) {
        self.userID = userID
        self.userName = userName
        self.email = email
        self.gender = gender
        self.birthday = birthday
        self.diseaseStage = diseaseStage
        self.role = role
        self.pairingCode = pairingCode
        self.avatarData = avatarData
    }
}
