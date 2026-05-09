import Foundation

struct LoginResponseDTO: Codable {
    let token: String
    let user: UserDataDTO
}
