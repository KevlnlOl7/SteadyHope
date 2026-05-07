import SwiftUI

struct NavigationBarView: View {
    @State private var selectedTab: Int = 0
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var dataVM: DataViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            
            TabView(selection: $selectedTab) {
                IndexView(loginVM: loginVM,dataVM:dataVM)
                    .tag(0)
                
                SettingView(loginVM: loginVM)
                    .tag(1)
                
                DataView(loginVM: loginVM,dataVM:dataVM)
                    .tag(2)
                
                ProfileView(loginVM: loginVM)
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            // 自定義導航列 UI
            ZStack {
                // 導航列背景
                RoundedRectangle(cornerRadius: 296)
                    .foregroundColor(Color(red: 0.97, green: 0.97, blue: 0.97))
                    .frame(width: 360, height: 62)
                    .shadow(color: Color.black.opacity(0.12), radius: 40, x: 0, y: 8)
                // 選中的灰色滑動背景
                RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                        .frame(width: 86, height: 58)
                        .background(Color(red: 0, green: 0, blue: 0).opacity(0))
                        .cornerRadius(296)
                        .offset(x: CGFloat(selectedTab) * 90 - 135)
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: selectedTab)

                HStack(spacing: 0) {
                    tabButton(title: "Home", icon: "house.fill", index: 0)
                    tabButton(title: "Setting", icon: "gearshape.fill", index: 1)
                    tabButton(title: "Data", icon: "chart.bar.fill", index: 2)
                    tabButton(title: "Profile", icon: "person.fill", index: 3)
                }
                .frame(width: 360)
            }
            .padding(.bottom, 30)
        }
        .ignoresSafeArea(.all, edges: .bottom)
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
            .foregroundColor(selectedTab == index ? Color(red: 0, green: 0.53, blue: 1) : Color(red: 0.1, green: 0.1, blue: 0.1))
        }
    }
}
