import Foundation
import SwiftData

struct RegisterData: Codable {
    
    /// 用戶姓名
    let name: String
    
    /// 用戶信箱
    let email: String
    
    /// 用戶密碼
    let password: String
    
    /// 用戶性別
    let gender: Int
    
    /// 用戶生日
    let birth: String // 格式：yyyy-MM-dd
}
