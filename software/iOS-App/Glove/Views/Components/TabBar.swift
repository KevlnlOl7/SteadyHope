import SwiftUI

struct TabBar: View {
    @Binding var selectedTab: Int

    let tabItems: [(title: String, icon: String)]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        
        let itemWidth = CGFloat(tabItems.count) > 0 ? 360 / CGFloat(tabItems.count) : 0
        
        ZStack {
            // 導航列背景
            RoundedRectangle(cornerRadius: 296)
                .foregroundColor(AppTheme.cardBackground(for: colorScheme))
                .frame(width: 360, height: 62)
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
                    radius: 20,
                    x: 0,
                    y: 6
                )

            // 選中的滑動背景
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : AppTheme.background(for: colorScheme))
                .frame(width: max(0, itemWidth - 6), height: 58)
                .cornerRadius(296)
                // 自動根據目前傳入的 index 計算物理位置
                .offset(x: CGFloat(selectedTab) * itemWidth - (360 - itemWidth) / 2)
                .animation(
                    .spring(response: 0.4, dampingFraction: 0.75),
                    value: selectedTab
                )

            // 根據傳入的陣列自動產生按鈕
            HStack(spacing: 0) {
                ForEach(0..<tabItems.count, id: \.self) { index in
                    tabButton(
                        title: tabItems[index].title,
                        icon: tabItems[index].icon,
                        index: index
                    )
                }
            }
            .frame(width: 360)
        }
    }

    /// 單個分頁按鈕
    @ViewBuilder
    func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                selectedTab = index
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(
                selectedTab == index
                    ? AppTheme.primary(for: colorScheme)
                    : AppTheme.textSecondary(for: colorScheme)
            )
        }
    }
}
