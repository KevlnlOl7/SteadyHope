import Vapor
import Foundation

struct UserResponse: Content {
    let id: Int?
    let email: String
    let name: String?
    let birth: Date?
    let gender: Int?
    let diseaseStage: String?
}
struct LoginResponse: Content {
    let token: String
    let user: UserResponse // 這裡直接使用你已經寫好的 UserResponse[cite: 6]
}
