import SwiftUI

struct ProfileView: View {
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var medVM: MedicationViewModel
    @State private var isPresentingMedication = false

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("使用者個人資料")
                            .font(.system(size: 24, weight: .bold))
                    }
                    Spacer()
                }
                .padding(.horizontal, 25)
                .padding(.top, 20)
                .padding(.bottom, 10)

                ScrollView {
                    VStack(spacing: 20) {

                        HStack {
                            Text(loginVM.userData?.userName ?? "用戶")
                                .font(.system(size: 50, weight: .bold))
                                .foregroundColor(.primary.opacity(0.7))
                            Spacer()
                        }
                        .padding(.horizontal, 30)
                        .frame(height: 100)

                        VStack(spacing: 0) {
                            DataRow(title: "個人資料")
                            NavigationLink(
                                destination: MedicationView(
                                    loginVM: loginVM,
                                    medVM: medVM
                                )
                            ) {
                                DataRow(title: "用藥資料", text: "查看")
                            }
                            DataRow(title: "帳號設定", showDivider: false)
                        }
                        .background(Color.white)
                        .cornerRadius(15)
                        .padding(.horizontal, 20)
                        .shadow(
                            color: Color.black.opacity(0.05),
                            radius: 10,
                            y: 5
                        )

                        Button(action: {
                            loginVM.logout()
                        }) {
                            Text("登出")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 120, height: 48)
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(24)
                                .shadow(
                                    color: Color.black.opacity(0.2),
                                    radius: 10,
                                    y: 5
                                )
                        }
                        .padding(.top, 30)

                        Color.clear.frame(height: 100)
                    }
                }
            }
        }
    }
}
