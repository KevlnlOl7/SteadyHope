import Foundation
import SwiftData

@Model
class UserData {
    
    /// 使用者ID
    var userID: Int?
    
    /// 使用者姓名
    var userName: String?
    
    /// 使用者信箱
    var email: String
    
    /// 使用者密碼
    var password: String
    
    init(userID: Int? = nil, userName: String? = nil, email: String, password: String) {
        self.userID = userID
        self.userName = userName
        self.email = email
        self.password = password
        }
}

