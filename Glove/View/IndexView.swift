import SwiftUI

struct IndexView: View {
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var dataVM: DataViewModel
    @State private var batteryLevel: Int = 80

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // 疾病階段
                VStack(alignment: .center) {
                    Text("疾病階段")
                        .font(.system(size: 20, weight: .bold))
                        .padding(5)
                    if let user = loginVM.userData {
                        Text("\(user.diseaseStage)")
                            .font(.system(size: 30, weight: .bold))
                    } else {
                        Text("無資料,請至個人資料修改")
                            .font(.system(size: 25, weight: .bold))
                            .foregroundColor(.gray)
                            
                    }
                    Spacer()
                }
                .padding()
                .frame(width: 350, height: 120)
                .background(Color.white)
                .cornerRadius(15)
                .shadow(color: Color.black.opacity(0.05), radius: 5, y: 5)

                HStack(spacing: 15) {
                    // 電量
                    VStack(alignment: .leading) {
                        HStack {
                            BatteryIcon(level: batteryLevel)
                            Spacer()
                        }
                        Spacer()
                        HStack(alignment: .bottom, spacing: 2) {
                                Text("\(batteryLevel)")
                                    .font(.system(size: 60, weight: .medium))
                                Text("%")
                                    .font(.system(size: 30))
                                    .padding(.bottom, 8)
                            }
                            .frame(maxWidth: .infinity,alignment: .trailing)
                    }
                    .padding()
                    .frame(width: 165, height: 165)
                    .background(Color.white)
                    .cornerRadius(15)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, y: 5)
                    
                    // 上次抖動時間
                    VStack(alignment: .leading,spacing: 6) {
                        HStack(alignment: .bottom, spacing: 2) {
                            Image(systemName: "clock.badge.exclamationmark")
                                        .font(.system(size: 15))
                                        .foregroundColor(.blue)
                            Text(" 上次抖動時間")
                                .font(.system(size: 15))
                                .bold()
                        }
                        .frame(maxWidth: .infinity,alignment: .leading)
                        Spacer()
                        
                        HStack(alignment: .bottom, spacing: 2) {
                                Text(dataVM.lastVibrationDate)
                                    .font(.system(size: 30, weight: .medium))
                                    .bold()
                            }
                            .padding(.leading, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                        HStack(alignment: .bottom) {
                            Text(dataVM.lastVibrationTime)
                                .font(.system(size: 40, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        Spacer()
                        
                    }
                    .padding()
                    .frame(width: 165, height: 165)
                    .background(Color.white)
                    .cornerRadius(15)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, y: 5)
                }
                Spacer()
            }
            .padding(.top, 50)
        }
    }
}
// 電池圖標組件
struct BatteryIcon: View {
    var level: Int
    var body: some View {
        ZStack(alignment: .leading) {
            // 外框
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.black, lineWidth: 1.5)
                .frame(width: 25, height: 12)
            
            // 內部電量條
            RoundedRectangle(cornerRadius: 1)
                .fill(level >= 80 ? Color.green : (level <= 20 ? Color.red : Color.yellow))
                .frame(width: CGFloat(min(max(level, 0), 100)) / 100 * 21, height: 8)
                .offset(x: 2)
            
            // 電池頭
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.black)
                .frame(width: 2, height: 5)
                .offset(x:27)
        }
    }
}
