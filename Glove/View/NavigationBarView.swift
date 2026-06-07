import SwiftUI

struct NavigationBarView: View {
    @State private var selectedTab: Int = 0
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var dataVM: DataViewModel
    @ObservedObject var medVM: MedicationViewModel

    private let patientTabs = [
        (title: "Home", icon: "house.fill"),
        (title: "Setting", icon: "gearshape.fill"),
        (title: "Data", icon: "chart.bar.fill"),
        (title: "Profile", icon: "person.fill"),
    ]

    private let caregiverTabs = [
        (title: "Care", icon: "person.2.fill"),
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
                if loginVM.userData?.role == "caregiver" {
                    caregiverPages
                } else {
                    patientPages
                }

                // 根據身分帶入對應的動態 TabBar
                if loginVM.userData?.email == "caregiver" {
                    TabBar(
                        selectedTab: $selectedTab,
                        tabItems: caregiverTabs
                    )
                    .padding(.bottom, 10)
                } else {
                    TabBar(
                        selectedTab: $selectedTab,
                        tabItems: patientTabs
                    )
                    .padding(.bottom, 10)
                }
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    @ViewBuilder
    private var patientPages: some View {
        TabView(selection: $selectedTab) {
            IndexView(loginVM: loginVM, dataVM: dataVM, medVM: medVM)
                .tag(0)

            SettingView(loginVM: loginVM)
                .tag(1)

            DataView(loginVM: loginVM, dataVM: dataVM)
                .tag(2)

            ProfileView(loginVM: loginVM, medVM: medVM)
                .tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var caregiverPages: some View {
        TabView(selection: $selectedTab) {
            Caretaker(loginVM: loginVM, dataVM: dataVM, medVM: medVM)
                .tag(0)

            SettingView(loginVM: loginVM)
                .tag(1)

            DataView(loginVM: loginVM, dataVM: dataVM)
                .tag(2)

            ProfileView(loginVM: loginVM, medVM: medVM)
                .tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
