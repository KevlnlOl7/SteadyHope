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
    
    /// 用戶性別
    var gender: Int
    
    /// 用戶生日
    var birthday: Date
    
    /// 疾病階段
    var diseaseStage: String
    
    /// 登入身份
    var role: String
    
    init(userID: Int, userName: String, email: String, gender: Int, birthday: Date, diseaseStage: String,role: String) {
        self.userID = userID
        self.userName = userName
        self.email = email
        self.gender = gender
        self.birthday = birthday
        self.diseaseStage = diseaseStage
        self.role = role
    }
}

