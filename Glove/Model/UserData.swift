import Foundation
import SwiftData

@Model
class UserData {
    
    /// 用戶ID
    var userID: Int
    
    /// 用戶姓名
    var userName: String
    
    /// 用戶信箱
    var email: String
    
    /// 用戶密碼
    var password: String
    
    /// 用戶性別
    var gender: Bool
    
    /// 用戶生日
    var birthday: Date
    
    /// 疾病階段
    var diseaseStage: String
    
    /// 用戶創建日期
    var CreatedAt: Date
    
    init(userID: Int, userName: String, email: String, password: String, gender: Bool, birthday: Date, diseaseStage: String, CreatedAt: Date) {
        self.userID = userID
        self.userName = userName
        self.email = email
        self.password = password
        self.gender = gender
        self.birthday = birthday
        self.diseaseStage = diseaseStage
        self.CreatedAt = CreatedAt
    }
}

