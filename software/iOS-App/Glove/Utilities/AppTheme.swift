import SwiftUI

struct AppTheme {
    /// 主要品牌色（淺色模式為深藍色，深色模式為亮藍色）
    /// - Parameter colorScheme: 系統目前的外觀模式
    /// - Returns: 對應的色彩實體
    static func primary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "7CB8F7") : Color(hex: "1D63B8")
    }
    
    /// 強調提示色（淺色模式為溫暖橙色，深色模式為淡金黃色）
    /// - Parameter colorScheme: 系統目前的外觀模式
    /// - Returns: 對應的色彩實體
    static func accent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "F3D37A") : Color(hex: "EAA15F")
    }
    
    /// 畫面全域底色（淺色模式為柔和米白，深色模式為極深碳灰）
    /// - Parameter colorScheme: 系統目前的外觀模式
    /// - Returns: 對應的色彩實體
    static func background(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "131518") : Color(hex: "FBF9F4")
    }
    
    /// 卡片與容器區塊背景色（淺色模式為純白，深色模式為深層表面灰）
    /// - Parameter colorScheme: 系統目前的外觀模式
    /// - Returns: 對應的色彩實體
    static func cardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "1E2228") : Color.white
    }
    
    /// 卡片外框與分隔線顏色（淺色模式為淡米褐邊框，深色模式為低對比金屬灰）
    /// - Parameter colorScheme: 系統目前的外觀模式
    /// - Returns: 對應的色彩實體
    static func cardBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "2B313A") : Color(hex: "EFEAE1")
    }
    
    /// 主要文字與標題顏色（淺色模式為深灰黑，深色模式為高對比白灰）
    /// - Parameter colorScheme: 系統目前的外觀模式
    /// - Returns: 對應的色彩實體
    static func textPrimary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "E2E8F0") : Color(hex: "2C323A")
    }
    
    /// 次要文字、註解與輔助說明顏色（淺色模式為暖調石灰，深色模式為冷調灰藍）
    /// - Parameter colorScheme: 系統目前的外觀模式
    /// - Returns: 對應的色彩實體
    static func textSecondary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "A3ACB9") : Color(hex: "78716C")
    }
}
