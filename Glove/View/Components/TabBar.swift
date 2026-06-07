import SwiftUI

struct TabBar: View {
    @Binding var selectedTab: Int

    let tabItems: [(title: String, icon: String)]

    var body: some View {
        ZStack {
            // 導航列背景
            RoundedRectangle(cornerRadius: 296)
                .foregroundColor(Color(red: 0.97, green: 0.97, blue: 0.97))
                .frame(width: 360, height: 62)
                .shadow(
                    color: Color.black.opacity(0.12),
                    radius: 40,
                    x: 0,
                    y: 8
                )

            // 選中的灰色滑動背景
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                .frame(width: 86, height: 58)
                .cornerRadius(296)
                // 自動根據目前傳入的 index 計算物理位置
                .offset(x: CGFloat(selectedTab) * 90 - 135)
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
                    ? Color(red: 0, green: 0.53, blue: 1)
                    : Color(red: 0.1, green: 0.1, blue: 0.1)
            )
        }
    }
}
