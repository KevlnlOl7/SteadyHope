import SwiftUI
import Charts

struct DataView: View {
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var dataVM = DataViewModel()
    @State private var selectedDate = Date()

        var body: some View {
            ZStack {
                Color(red: 0.97, green: 0.97, blue: 0.97).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("震動數據分析")
                                    .font(.system(size: 28, weight: .bold))
                                Text("監測手套即時回傳之震動頻率")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 25)
                        .padding(.top, 20)

                        // 震動圖表
                        VStack(alignment: .leading, spacing: 15) {
                            HStack {
                                Image(systemName: "waveform.path.ecg")
                                    .foregroundColor(.blue)
                                Text("目前震動狀態")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            // 圖表框
                            Chart {
                            }
                            .frame(height: 220)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(20)
                        .padding(.horizontal)
                        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)

                        // 統計資訊
                        VStack(alignment: .leading, spacing: 15) {
                            Text("數據統計")
                                .font(.system(size: 18, weight: .bold))
                            
                            HStack(spacing: 20) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("平均強度").font(.system(size: 14)).foregroundColor(.secondary)
                                    Text("\(String(format: "%.1f", dataVM.avgStrength))%").font(.system(size: 26, weight: .bold))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Divider().frame(height: 40)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("最高震幅").font(.system(size: 14)).foregroundColor(.secondary)
                                    Text("\(String(format: "%.1f", dataVM.maxStrength))%").font(.system(size: 26, weight: .bold))
                                        .foregroundColor(dataVM.maxStrength > 75 ? .red : .primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(15)
                            
                            HStack {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.badge.exclamationmark")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 20))
                                    
                                    Text("上次抖動時間")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                
                                Spacer()
                                
                                Text(dataVM.lastVibrationTime)
                                    .font(.system(size: 18, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                            }
                            .padding(20)
                            .background(Color.white)
                            .cornerRadius(15)
                            .padding(.horizontal)
                            .shadow(color: Color.black.opacity(0.03), radius: 5, y: 2)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(20)
                        .padding(.horizontal)
                    }
                }
            }
        }
    }
