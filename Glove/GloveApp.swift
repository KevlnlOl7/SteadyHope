import SwiftUI
import SwiftData

@main
struct GloveApp: App {
    /// 建立資料的實體儲存庫
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserData.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            LoginView()
        }
        .modelContainer(sharedModelContainer)
    }
}
