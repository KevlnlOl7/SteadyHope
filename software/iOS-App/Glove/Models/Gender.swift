import Foundation

enum Gender: Int, Codable {
    case unknown = 0
    case male = 1
    case female = 2
    case other = 3

    var label: String {
        switch self {
        case .male: return "男"
        case .female: return "女"
        case .other: return "其他"
        case .unknown: return "未設定"
        }
    }
}
