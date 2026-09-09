import SwiftUI
import Combine
import SwiftData

@main
struct GloveApp: App {
    /// 建立資料的實體儲存庫
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserData.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}

/// 應用程式根視圖，負責掌管驗證狀態與畫面流轉
struct RootView: View {
    @StateObject private var loginVM = LoginViewModel()
    @StateObject private var dataVM = DataViewModel()
    @StateObject private var medVM = MedicationViewModel()
    @ObservedObject private var bleVM = BluetoothViewModel.shared
    @StateObject private var symptomVM = SymptomViewModel()
    @StateObject private var vitalsVM = HealthVitalsViewModel()

    var body: some View {
        Group {
            if loginVM.isAuthenticated {
                NavigationBarView(loginVM: loginVM, dataVM: dataVM, medVM: medVM, bleVM: bleVM,symptomVM:symptomVM,vitalsVM: vitalsVM)
            } else {
                LoginView(loginVM: loginVM)
            }
        }
        // 強制讓 SwiftUI 根據登入驗證狀態重新渲染 View 結構
        .id(loginVM.isAuthenticated)
        // 登入狀態切換時的淡入淡出轉場動畫
        .animation(.easeInOut(duration: 0.3), value: loginVM.isAuthenticated)
        // 全域攔截 401 Unauthorized 通知並執行強制登出流程
        .onReceive(
            NotificationCenter.default.publisher(
                for: .didReceive401Unauthorized)
        ) { notification in
            print("[RootView] 收到 401 全域通知，即時執行登出切換機制")

            let message =
                notification.userInfo?["message"] as? String
                ?? "您的帳號已在其他裝置登入，請重新登入。"

            // 發送廣播通知 SwiftUI 狀態即將發生變更
            loginVM.objectWillChange.send()

            // 重置登入驗證狀態並彈出登出提示 Alert
            loginVM.logout()
            loginVM.isAuthenticated = false
            loginVM.sessionExpiredMessage = message
            loginVM.showSessionExpiredAlert = true
        }
    }
}
