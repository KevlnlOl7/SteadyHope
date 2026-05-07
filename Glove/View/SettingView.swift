import SwiftUI

struct SettingView: View {
    @ObservedObject var loginVM: LoginViewModel
    @State private var batteryLevel: Int = 80
    @State private var intensity: Double = 0.5
    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()
            
            VStack(spacing: 25) {
                Text("手套設定與狀態")
                    .font(.system(size: 24, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 25)
                    .padding(.top, 20)

                // 電量
                VStack(spacing: 15) {
                    HStack {
                        Text("目前裝置電量")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        BatteryIcon(level: batteryLevel)
                    }
                    
                    HStack(alignment: .bottom, spacing: 2) {
                        Text("\(batteryLevel)")
                            .font(.system(size: 60, weight: .medium))
                        Text("%")
                            .font(.system(size: 24))
                            .padding(.bottom, 10)
                    }
                }
                .padding(25)
                .frame(width: 350)
                .background(Color.white)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)

                // 功能設定列表
                VStack(spacing: 0) {
                    SettingRow(icon: "bolt.fill", title: "連線狀態", value: "已連線", showDivider: true)
                }
                .background(Color.white)
                .cornerRadius(15)
                .padding(.horizontal, 25)
                
                // 強度 Slider
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.blue)
                        Text("手套運作強度")
                            .font(.system(size: 16, weight: .medium))
                        Spacer()
                        Text("\(Int(intensity * 100))%")
                            .foregroundColor(.blue)
                            .fontWeight(.bold)
                    }
                    
                    Slider(value: $intensity, in: 0...1)
                        .accentColor(.blue)
                    
                    HStack {
                        Text("弱").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text("強").font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(20)
                .background(Color.white)
                .cornerRadius(15)
                .padding(.horizontal, 25)

                Spacer()
            }
        }
    }
}

// 列表行組件
struct SettingRow: View {
    var icon: String
    var title: String
    var value: String
    var showDivider: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 30)
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                Text(value)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .padding()
            
            if showDivider {
                Divider().padding(.leading, 50)
            }
        }
    }
}
