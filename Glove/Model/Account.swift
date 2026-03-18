import Foundation
import Foundation
import SwiftData

@Model
class Account {
    
    /// 用戶ID
    var userID: Int?
    
    /// 用戶信箱
    var email: String
    
    /// 用戶密碼
    var password: String
    
    init(userID: Int? = nil, email: String, password: String) {
        self.userID = userID
        self.email = email
        self.password = password
    }
    
}
