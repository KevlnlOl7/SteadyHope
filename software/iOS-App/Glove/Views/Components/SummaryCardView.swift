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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(badgeColor)
                    .frame(width: 4, height: 14)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .padding(8)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .background(AppTheme.cardBackground(for: colorScheme))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.textSecondary(for: colorScheme).opacity(0.2), lineWidth: 1)
                )
        }
        .padding(.vertical, 4)
    }
}
