import SwiftUI

extension View {
    /// 收鍵盤
    func hideKeyboard(){
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    /// 用藥紀錄列表
    /// - Parameters:
    ///   - date: 格式化後的日期字串
    ///   - time: 格式化後的時間字串
    ///   - name: 藥品名稱
    ///   - dose: 包含單位的用量字串
    ///   - showDivider: 是否在下方顯示分割線，預設為 false
    func medicationRow(date: String, time: String, name: String, dose: String, showDivider: Bool = false) -> some View {
            DataRow(
                title: name,
                subtitle: "\(date)  \(time) \n 用量: \(dose)",
                showEdit: false,
                showDivider: showDivider
            )
        }
}
extension Date {
    /// 日期格式化工具
    /// - Parameter format: 格式化字串，例如 "yyyyMMdd"
    /// - Returns: 格式化後的日期字串
    func toString(format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
}
}
