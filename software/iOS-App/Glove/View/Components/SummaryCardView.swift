import SwiftUI

/// 客製化診間溝通摘要卡片，提供標題色條與可編輯之文字區域
struct SummaryCardView: View {
    /// 卡片標題
    let title: String
    
    /// 左側標示色條色彩
    let badgeColor: Color
    
    /// 可編輯之文字內容綁定
    @Binding var text: String
    
    /// 文字編輯區塊最小高度
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(badgeColor)
                    .frame(width: 4, height: 14)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }

            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
        }
        .padding(.vertical, 4)
    }
}
