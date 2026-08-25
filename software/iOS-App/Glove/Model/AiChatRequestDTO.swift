import Foundation

struct AiChatRequestDTO: Codable {
    let message: String
}

struct AiChatResponseDTO: Codable {
    let reply: String
}
