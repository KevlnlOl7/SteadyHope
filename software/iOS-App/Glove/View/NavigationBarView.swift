import SwiftUI

struct NavigationBarView: View {
    @State private var selectedTab: Int = 0
    @State private var showBindReminderAlert: Bool = false
    @State private var showAIChat: Bool = false
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var dataVM: DataViewModel
    @ObservedObject var medVM: MedicationViewModel
    @ObservedObject var bleVM: BluetoothViewModel

    /// 病患端的分頁標籤與圖示設定
    private let patientTabs = [
        (title: "Home", icon: "house.fill"),
        (title: "Setting", icon: "gearshape.fill"),
        (title: "Daily", icon: "heart.text.clipboard.fill"),
        (title: "Data", icon: "chart.bar.fill"),
        (title: "Profile", icon: "person.fill"),
    ]

    /// 照護者端的分頁標籤與圖示設定
    private let caregiverTabs = [
        (title: "Daily", icon: "heart.text.clipboard.fill"),
        (title: "Setting", icon: "gearshape.fill"),
        (title: "Monitor", icon: "chart.xyaxis.line"),
        (title: "Profile", icon: "person.crop.circle.badge.checkmark"),
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(red: 0.97, green: 0.97, blue: 0.97)
                    .ignoresSafeArea()

                // 根據身分載入不同的內容
                if loginVM.userData?.role == 1 {
                    caregiverPages
                } else {
                    patientPages
                }

                // 根據身分與連線狀態，帶入對應的動態 TabBar
                if loginVM.userData?.role == 1 {
                    if loginVM.isLinked {
                        TabBar(
                            selectedTab: $selectedTab,
                            tabItems: caregiverTabs
                        )
                        .padding(.bottom, 10)
                    }
                } else {
                    TabBar(
                        selectedTab: $selectedTab,
                        tabItems: patientTabs
                    )
                    .padding(.bottom, 10)
                }

                aiFloatingButton
                    .padding(.bottom, 80)
                    .padding(.trailing, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            }
            .navigationTitle("")
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showAIChat) {
                AIChatView()
            }
            .task {
                await loginVM.loadPartnerIfNeeded()
                
                // 進入畫面後，定時同步並檢查家屬綁定連線狀態
                while !Task.isCancelled {
                    await checkInitialConnectionStatus()
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                }
            }
        }
    }

        @Environment(\.colorScheme) private var colorScheme
        @ViewBuilder
        private var aiFloatingButton: some View {
            Button {
                showAIChat = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                    Text("小安")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(
                        colors: [
                            AppTheme.accent(for: colorScheme),
                            Color(hex: "F2B278")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .shadow(
                    color: AppTheme.accent(for: colorScheme).opacity(0.35),
                    radius: 6,
                    x: 0,
                    y: 3
                )
            }
        }
    
    /// 病患端專用的分頁視圖
    @ViewBuilder
    private var patientPages: some View {
        TabView(selection: $selectedTab) {
            IndexView(loginVM: loginVM, dataVM: dataVM, medVM: medVM)
                .tag(0)

            SettingView(loginVM: loginVM)
                .tag(1)

            DailyView(loginVM: loginVM)
                .tag(2)

            DataView(loginVM: loginVM, dataVM: dataVM,bleVM:bleVM)
                .tag(3)

            ProfileView(loginVM: loginVM, medVM: medVM, dataVM: dataVM)
                .tag(4)

        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 照護者端專用的分頁視圖
    @ViewBuilder
    private var caregiverPages: some View {
        if loginVM.isLinked {
            // 已綁定病患：顯示完整的 4 個分頁
            TabView(selection: $selectedTab) {
                DailyView(loginVM: loginVM)
                    .tag(0)

                SettingView(loginVM: loginVM)
                    .tag(1)

                DataView(loginVM: loginVM, dataVM: dataVM,bleVM:bleVM)
                    .tag(2)

                ProfileView(loginVM: loginVM, medVM: medVM, dataVM: dataVM)
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // 未綁定病患：僅顯示個人資料頁，並彈出連動提醒
            NavigationStack {
                ProfileView(loginVM: loginVM, medVM: medVM, dataVM: dataVM)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 10)
            .alert("家屬連動提醒", isPresented: $showBindReminderAlert) {
                Button("確定") {
                }
            } message: {
                Text("您目前尚未連接任何被照護者。\n請點選「帳號設定」進行家屬連動，\n以解鎖完整功能。")
            }
        }
    }

    /// 初始化時檢查照護者端目前的綁定連線狀態
    private func checkInitialConnectionStatus() async {
        guard loginVM.userData?.role == 1 else { return }

        let bondRepo = UserBondRepository()
        do {
            let result = try await bondRepo.fetchMyBoundPartnerInfo()

            await MainActor.run {
                let newlyLinked = !result.partnerEmail.isEmpty

                // 首度切換為已連線狀態時，自動將選取 Tab 重置至第一個分頁
                if !loginVM.isLinked && newlyLinked {
                    selectedTab = 0
                }
                loginVM.isLinked = newlyLinked
            }
        } catch {
            let errorMsg = error.localizedDescription

            // 若為 401 授權失效等錯誤，不觸發綁定提醒，改由全域廣播處理登出
            if errorMsg.contains("401") || errorMsg.contains("已在其他裝置登入")
                || errorMsg.contains("登入已失效")
            {
                return
            }

            await MainActor.run {
                loginVM.isLinked = false
                showBindReminderAlert = true
            }
        }
    }
}
