import Foundation
import SwiftData

@Model
class UserData {
    var userID: Int
    var userName: String
    var email: String
    var token: String
    var gender: Bool
    
    init(userID: Int, userName: String, email: String, token: String, gender: Bool) {
        self.userID = userID
        self.userName = userName
        self.email = email
        self.token = token
        self.gender = gender
    }
}

