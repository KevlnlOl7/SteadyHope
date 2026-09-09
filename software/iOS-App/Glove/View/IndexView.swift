import SwiftUI

struct IndexView: View {
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var dataVM: DataViewModel
    @ObservedObject var medVM: MedicationViewModel
    @ObservedObject var bleVM: BluetoothViewModel

    /// 當日健康評估問卷業務邏輯檢視模型
    @StateObject private var assessmentVM = AssessmentViewModel()

    /// 底部導覽列當前選取之分頁索引雙向綁定
    @Binding var selectedTab: Int

    /// 控制每日評估問卷填寫彈窗之顯示狀態
    @State private var showAssessmentSheet: Bool = false

    /// 讀取看診溝通卡片匯出設定所儲存的「看病前準備」備忘文字
    @AppStorage(ExportSettingsViewModel.homePreparationKey)
    private var homePreparationNote: String = ""

    /// 記錄使用者點擊關閉按鈕隱藏評估橫幅的日期字串（格式：yyyy-MM-dd）
    @AppStorage("assessmentBannerDismissedDate")
    private var assessmentBannerDismissedDate: String = ""

    /// 判斷當前使用者角色是否為病患本人（角色代碼 0 為患者）
    private var isPatient: Bool {
        loginVM.userData?.role == 0
    }

    /// 取得當前本機之年月日日期字串
    private var todayDateString: String {
        Date().toString(format: "yyyy-MM-dd")
    }

    /// 判斷每日評估提醒橫幅是否應顯示：使用者為患者本人、今日尚未完成評估且今日尚未手動關閉橫幅
    private var shouldShowAssessmentBanner: Bool {
        isPatient && !assessmentVM.hasFilledToday && assessmentBannerDismissedDate != todayDateString
    }

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if shouldShowAssessmentBanner {
                        assessmentReminderBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "list.clipboard.fill")
                                .foregroundColor(.blue)
                            Text("看診前準備")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                        }

                        if homePreparationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("目前尚無看診準備清單，\n可於健康報告匯出中勾選生成。")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                Text(homePreparationNote)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                    .lineSpacing(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: 120)
                    .background(Color.white)
                    .cornerRadius(15)
                    .shadow(color: Color.black.opacity(0.05), radius: 5, y: 5)
                    .padding(.horizontal, 20)

                    HStack(spacing: 15) {
                        if isPatient {
                            Button {
                                switchTab(to: 1)
                            } label: {
                                VStack(alignment: .leading) {
                                    HStack {
                                        BatteryIcon(level: bleVM.batteryLevel)
                                        Spacer()
                                    }
                                    Spacer()
                                    HStack(alignment: .bottom, spacing: 2) {
                                        if bleVM.isConnected {
                                            Text("\(bleVM.batteryLevel)")
                                                .font(.system(size: 60, weight: .medium))
                                                .foregroundColor(.primary)
                                            Text("%")
                                                .font(.system(size: 30))
                                                .foregroundColor(.primary)
                                                .padding(.bottom, 8)
                                        } else {
                                            Text("未連接手套")
                                                .font(.system(size: 22, weight: .medium))
                                                .foregroundColor(.gray)
                                                .padding(.bottom, 12)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .padding()
                                .frame(width: 165, height: 165)
                                .background(Color.white)
                                .cornerRadius(15)
                                .shadow(color: Color.black.opacity(0.05), radius: 5, y: 5)
                            }
                            .buttonStyle(CardPressableButtonStyle())
                        } else {
                            VStack(alignment: .leading, spacing: 20) {
                                Image(systemName: "person.crop.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 36))

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("當前被照護者")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)

                                    Text(loginVM.partnerName)
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                            }
                            .padding()
                            .frame(width: 165, height: 165, alignment: .leading)
                            .background(Color.white)
                            .cornerRadius(15)
                            .shadow(color: Color.black.opacity(0.05), radius: 5, y: 5)
                        }

                        Button {
                            switchTab(to: isPatient ? 3 : 2)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .bottom, spacing: 2) {
                                    Image(systemName: "clock.badge.exclamationmark")
                                        .font(.system(size: 15))
                                        .foregroundColor(.blue)
                                    Text(" 上次抖動時間")
                                        .font(.system(size: 15))
                                        .bold()
                                        .foregroundColor(.primary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Spacer()

                                HStack(alignment: .bottom, spacing: 2) {
                                    Text(dataVM.lastVibrationDate)
                                        .font(.system(size: 30, weight: .medium))
                                        .bold()
                                        .foregroundColor(.primary)
                                }
                                .padding(.leading, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                HStack(alignment: .bottom) {
                                    Text(dataVM.lastVibrationTime)
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundColor(.primary)
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
                        .buttonStyle(CardPressableButtonStyle())
                    }

                    Button {
                        switchTab(to: isPatient ? 4 : 3)
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("今日用藥資料")
                                    .font(.system(size: 16))
                                    .bold()
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 15)

                            Divider()

                            let todayRecords = medVM.medicationList.filter { record in
                                Calendar.current.isDateInToday(record.date)
                            }

                            if todayRecords.isEmpty {
                                Text("目前尚無資料")
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 40)
                                    .frame(maxWidth: .infinity)
                                Spacer()
                            } else {
                                ScrollView {
                                    VStack(spacing: 0) {
                                        ForEach(todayRecords) { med in
                                            medicationRow(
                                                date: med.date.toString(format: "M/d"),
                                                time: med.date.toString(format: "HH:mm"),
                                                name: med.name,
                                                dose: med.dose,
                                                showDivider: true
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: 350, height: 260)
                        .background(Color.white)
                        .cornerRadius(15)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, y: 5)
                    }
                    .buttonStyle(CardPressableButtonStyle())

                    Spacer(minLength: 20)
                }
                .padding(.top, 20)
            }
        }
        .onAppear {
            Task {
                let today = Date().toString(format: "yyyy-MM-dd")
                await medVM.loadRecords(for: today)
                await assessmentVM.checkTodayAssessmentStatus()
            }
        }
        .sheet(isPresented: $showAssessmentSheet) {
            AssessmentView(loginVM: loginVM)
        }
        .onChange(of: showAssessmentSheet) {
            if !showAssessmentSheet {
                Task {
                    await assessmentVM.checkTodayAssessmentStatus()
                }
            }
        }
    }

    /// 今日評估未填寫提醒橫幅視圖，引導患者快速進行症狀快篩
    private var assessmentReminderBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 3) {
                Text("今日尚未填寫症狀評估")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                Text("花 1 分鐘填寫今日狀態快篩，協助掌握病情。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button {
                showAssessmentSheet = true
            } label: {
                Text("立即評估")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut) {
                    assessmentBannerDismissedDate = todayDateString
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }

    /// 帶有彈性動畫效果之主要分頁切換方法
    /// - Parameter index: 目標分頁索引編號
    private func switchTab(to index: Int) {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedTab = index
        }
    }
}

/// 卡片元件專用之按壓回饋按鈕樣式，包含縮放、白色高光及邊框反白效果
struct CardPressableButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.35 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        Color.blue.opacity(configuration.isPressed ? 0.45 : 0),
                        lineWidth: configuration.isPressed ? 1.5 : 0
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
