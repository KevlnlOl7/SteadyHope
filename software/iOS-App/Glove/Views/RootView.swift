import SwiftUI
import Combine

struct RootView: View {
    @StateObject private var loginVM = LoginViewModel()
    @StateObject private var dataVM = DataViewModel()
    @StateObject private var medVM = MedicationViewModel()
    @ObservedObject private var bleVM = BluetoothViewModel.shared
    @StateObject private var symptomVM = SymptomViewModel()
    @StateObject private var vitalsVM = HealthVitalsViewModel()

    @State private var showWhatsNewSheet: Bool = false
    private let lastSeenVersionKey = "last_seen_app_version"

    var body: some View {
        Group {
            if loginVM.isAuthenticated {
                NavigationBarView(
                    loginVM: loginVM,
                    dataVM: dataVM,
                    medVM: medVM,
                    bleVM: bleVM,
                    symptomVM: symptomVM,
                    vitalsVM: vitalsVM
                )
            } else {
                LoginView(loginVM: loginVM)
            }
        }
        .id(loginVM.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: loginVM.isAuthenticated)
        .onAppear {
            NotificationScheduler.shared.requestAuthorization()
            checkVersionUpdate()
        }
        .sheet(isPresented: $showWhatsNewSheet) {
            WhatsNewSheetView(
                version: AppConfig.appVersion,
                onDismiss: {
                    UserDefaults.standard.set(AppConfig.appVersion, forKey: lastSeenVersionKey)
                    showWhatsNewSheet = false
                }
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didReceive401Unauthorized)
        ) { notification in
            let message =
                notification.userInfo?["message"] as? String
                ?? "您的帳號已在其他裝置登入，請重新登入。"

            loginVM.objectWillChange.send()
            loginVM.logout()
            loginVM.isAuthenticated = false
            loginVM.sessionExpiredMessage = message
            loginVM.showSessionExpiredAlert = true
        }
    }

    private func checkVersionUpdate() {
        let lastSeenVersion = UserDefaults.standard.string(forKey: lastSeenVersionKey)
        if lastSeenVersion != AppConfig.appVersion {
            showWhatsNewSheet = true
        }
    }
}

