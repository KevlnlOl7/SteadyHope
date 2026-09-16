import SwiftUI

struct NavigationBarView: View {
    @State private var selectedTab: Int = 0
    @State private var showBindReminderAlert: Bool = false
    @State private var showAIChat: Bool = false
    @State private var showSideMenu: Bool = false

    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var dataVM: DataViewModel
    @ObservedObject var medVM: MedicationViewModel
    @ObservedObject var bleVM: BluetoothViewModel
    @ObservedObject var symptomVM: SymptomViewModel
    @ObservedObject var vitalsVM: HealthVitalsViewModel

    @StateObject private var planVM = MedicationPlanViewModel()

    @Environment(\.colorScheme) private var colorScheme

    /// 判斷當前是否為尚未完成家屬綁定之照護者
    private var isUnlinkedCaregiver: Bool {
        loginVM.userData?.role == 1 && !loginVM.isLinked
    }

    /// 病患端的分頁標籤與圖示設定
    private let patientTabs = [
        (title: "Home", icon: "house.fill"),
        (title: "Setting", icon: "gearshape.fill"),
        (title: "Daily", icon: "heart.text.clipboard.fill"),
        (title: "Data", icon: "chart.bar.fill"),
        (title: "Medication", icon: "pills.fill"),
    ]

    /// 照護者端的分頁標籤與圖示設定
    private let caregiverTabs = [
        (title: "Home", icon: "house.fill"),
        (title: "Daily", icon: "heart.text.clipboard.fill"),
        (title: "Data", icon: "chart.bar.fill"),
        (title: "Medication", icon: "pills.fill"),
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()
                    .onTapGesture {
                        hideKeyboard()
                    }

                VStack(spacing: 0) {
                    topHeaderBar

                    if loginVM.userData?.role == 1 {
                        caregiverPages
                    } else {
                        patientPages
                    }
                }

                // 根據身分與連線狀態，帶入對應的動態 TabBar
                if loginVM.userData?.role == 1 {
                    if loginVM.isLinked {
                        TabBar(
                            selectedTab: $selectedTab,
                            tabItems: caregiverTabs
                        )
                        .padding(.bottom, 10)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                hideKeyboard()
                            }
                        )
                    }
                } else {
                    TabBar(selectedTab: $selectedTab, tabItems: patientTabs)
                        .padding(.bottom, 10)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                hideKeyboard()
                            }
                        )
                }

                if !isUnlinkedCaregiver {
                    aiFloatingButton
                        .padding(.bottom, 80)
                        .padding(.trailing, 20)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .bottomTrailing
                        )
                }

                // 螢幕左側滑動感應區
                if !showSideMenu {
                    edgeSwipeDetector
                }

                // 側邊選單視圖
                ProfileSideMenuView(
                    isOpen: $showSideMenu,
                    loginVM: loginVM,
                    medVM: medVM,
                    dataVM: dataVM,
                    planVM: planVM,
                    symptomVM: symptomVM,
                    vitalsVM: vitalsVM
                )
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showAIChat) {
                AIChatView()
            }
            .task {
                await loginVM.loadPartnerIfNeeded()
                await medVM.loadAllRecords()
                await planVM.loadAllPlans()
                while !Task.isCancelled {
                    await checkInitialConnectionStatus()
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                }
            }
            .onChange(of: selectedTab) {
                hideKeyboard()
            }
        }
    }

    /// 螢幕左側邊緣滑動手勢偵測區域
    private var edgeSwipeDetector: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .frame(width: 30, height: geometry.size.height)
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onEnded { value in
                            if value.translation.width > 40 && abs(value.translation.width) > abs(value.translation.height) {
                                hideKeyboard()
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showSideMenu = true
                                }
                            }
                        }
                )
        }
        .allowsHitTesting(true)
    }

    /// 頂部自訂選單按鈕列
    private var topHeaderBar: some View {
        HStack {
            Button(action: {
                hideKeyboard()
                withAnimation(.easeInOut(duration: 0.25)) {
                    showSideMenu.toggle()
                }
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .padding(10)
                    .background(AppTheme.cardBackground(for: colorScheme))
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// AI 助理懸浮啟動按鈕
    @ViewBuilder
    private var aiFloatingButton: some View {
        Button {
            hideKeyboard()
            showAIChat = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                Text("小安")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundColor(AppTheme.background(for: colorScheme))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AppTheme.accent(for: colorScheme))
            .clipShape(Capsule())
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12),
                radius: 6,
                x: 0,
                y: 3
            )
        }
    }

    /// 病患端主功能分頁視圖
    @ViewBuilder
    private var patientPages: some View {
        TabView(selection: $selectedTab) {
            IndexView(loginVM: loginVM, dataVM: dataVM, medVM: medVM, bleVM: bleVM, selectedTab: $selectedTab)
                .tag(0)
            SettingView(loginVM: loginVM)
                .tag(1)
            DailyNoteView(loginVM: loginVM)
                .tag(2)
            DataView(loginVM: loginVM, dataVM: dataVM, bleVM: bleVM)
                .tag(3)
            MedicationView(loginVM: loginVM, dataVM: dataVM, bleVM: bleVM)
                .tag(4)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 照護者端主功能分頁視圖
    @ViewBuilder
    private var caregiverPages: some View {
        if loginVM.isLinked {
            TabView(selection: $selectedTab) {
                IndexView(loginVM: loginVM, dataVM: dataVM, medVM: medVM, bleVM: bleVM, selectedTab: $selectedTab)
                    .tag(0)
                DailyNoteView(loginVM: loginVM)
                    .tag(1)
                DataView(loginVM: loginVM, dataVM: dataVM, bleVM: bleVM)
                    .tag(2)
                MedicationView(loginVM: loginVM, dataVM: dataVM, bleVM: bleVM)
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "person.badge.shield.exclamationmark")
                    .font(.system(size: 60))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                Text("尚未綁定被照護者")
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Text("請點擊左上角選單前往「帳號設定」進行配對。")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert("家屬連動提醒", isPresented: $showBindReminderAlert) {
                Button("確定") {}
            } message: {
                Text("您目前尚未連接任何被照護者。\n請至「家屬連動設定」進行家屬連動，\n以解鎖完整功能。")
            }
        }
    }

    /// 檢查照護者之初始連線與病患綁定狀態
    private func checkInitialConnectionStatus() async {
        guard loginVM.userData?.role == 1 else { return }
        let bondRepo = UserBondRepository()
        do {
            let result = try await bondRepo.fetchBoundPatientInfo()
            await MainActor.run {
                let newlyLinked = !result.partnerEmail.isEmpty
                if !loginVM.isLinked && newlyLinked {
                    selectedTab = 0
                }
                loginVM.boundPartner = result
                loginVM.isLinked = newlyLinked
            }
        } catch {
            let errorMsg = error.localizedDescription
            if errorMsg.contains("401") || errorMsg.contains("已在其他裝置登入")
                || errorMsg.contains("登入已失效")
            {
                return
            }
            await MainActor.run {
                loginVM.boundPartner = nil
                loginVM.isLinked = false
                showBindReminderAlert = true
            }
        }
    }
}
