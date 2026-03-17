import SwiftUI
struct IndexView: View {
    @ObservedObject var loginVM: LoginViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            if let user = loginVM.currentUser {
                Text("歡迎回來，\(user.userName ?? "使用者")")
                    .font(.title2)
                    .bold()
            }
            Spacer()
            
            Text("這是首頁")
                .foregroundColor(.gray)

            Spacer()

            Button(action: {
                loginVM.logout()
            }) {
                Text("登出帳號")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
        .navigationTitle("首頁")
        .navigationBarBackButtonHidden(true)
    }
}
