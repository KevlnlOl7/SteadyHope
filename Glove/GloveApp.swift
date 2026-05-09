import SwiftUI
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
struct RootView: View {
    @StateObject private var loginVM = LoginViewModel()
    @StateObject private var dataVM = DataViewModel()
    @StateObject private var medVM = MedicationViewModel()
    var body: some View {
        Group {
            if loginVM.isAuthenticated {
                NavigationBarView(loginVM: loginVM,dataVM:dataVM,medVM:medVM)
            } else {
                LoginView(loginVM: loginVM)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: loginVM.isAuthenticated)
    }
}
