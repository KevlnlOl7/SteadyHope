import Foundation

/// 健康觀察方向項目資料模型
struct CategoryItem: Identifiable, Hashable {
    let id = UUID()
    /// 主題標題
    let title: String
    /// 詳細說明文字
    let description: String
    /// SFSymbols 圖示名稱
    let icon: String
}
