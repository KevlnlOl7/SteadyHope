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
