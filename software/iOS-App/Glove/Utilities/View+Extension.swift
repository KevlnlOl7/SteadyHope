import SwiftUI

extension View {
    /// 強制收起目前畫面的軟體鍵盤
    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    /// 產生通用的用藥紀錄單列視圖元件
    /// - Parameters:
    ///   - date: 格式化後的日期字串 (例如: "3/25")
    ///   - time: 格式化後的時間字串 (例如: "14:30")
    ///   - name: 藥品名稱
    ///   - dose: 包含單位的用量字串 (例如: "1錠")
    ///   - showDivider: 是否在元件下方顯示底線分隔線（預設為 false）
    /// - Returns: 封裝後的 DataRow 視圖
    func medicationRow(
        date: String,
        time: String,
        name: String,
        dose: String,
        showDivider: Bool = false
    ) -> some View {
        DataRow(
            title: name,
            subtitle: "\(date)  \(time) \n 用量: \(dose)",
            showEdit: false,
            showDivider: showDivider
        )
    }
}

extension Date {
    /// 將 Date 物件依指定格式轉化為台灣時間字串
    /// - Parameter format: 日期格式化字串 (例如: "yyyy-MM-dd" 或 "HH:mm")
    /// - Returns: 格式化後的日期時間字串
    func toString(format: String = "yyyy-MM-dd HH:mm:ss") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        return formatter.string(from: self)
    }
}

extension String {
    /// 將字串依指定格式解析為 Date 物件
    /// - Parameter format: 日期格式化字串 (例如: "yyyy-MM-dd" 或 "HH:mm")
    /// - Returns: 解析後的 Date 物件
    func toDate(format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: self)
    }
}

extension Color {
    /// 使用 16 進位 Hex 色碼字串初始化 SwiftUI Color 物件
    /// - Parameter hex: 色碼字串 (支援帶有或不帶有 "#" 之 3 位數與 6 位數格式)
    init(hex: String) {
        let hex = hex.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted
        )
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (
                255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17
            )
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// 將目前的 Color 物件轉換為 16 進位 Hex 色碼字串
    /// - Returns: 帶有 "#" 前綴的 6 位數 Hex 字串 (例如: "#FF5733")，轉換失敗則回傳 nil
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components,
            components.count >= 3
        else { return nil }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(
            format: "#%02lX%02lX%02lX",
            lroundf(r * 255),
            lroundf(g * 255),
            lroundf(b * 255)
        )
    }
}
