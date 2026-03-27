import Foundation

enum Validation: Error {
    case empty(field: String)
    case email
    case password
    case server(message: String)
    
    var message: String {
            switch self {
            case .empty(let field):
                return "\(field)不可為空"
            case .email:
                return "Email 格式錯誤"
            case .password:
                return "密碼格式不符 (需8碼含大小寫)"
            case .server(let message):
                return message
            }
        }
}

enum Validator {
    static func validateRequired(value: String, fieldName: String) -> Validation? {
        if value.trimmingCharacters(in: .whitespaces).isEmpty {
            return .empty(field: fieldName)
        }
        return nil
    }
    
    static func validateEmail(_ email: String) -> Validation? {
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        return predicate.evaluate(with: email) ? nil : .email
    }
    
    static func validatePassword(_ password: String) -> Validation? {
        let passwordRegex = "^(?=.*[a-z])(?=.*[A-Z]).{8,}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", passwordRegex)
        return predicate.evaluate(with: password) ? nil : .password
    }
}
