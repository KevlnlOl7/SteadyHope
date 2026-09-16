import SwiftUI

struct SettingView: View {
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject private var bleVM = BluetoothViewModel.shared
    @Environment(\.colorScheme) private var colorScheme

    @FocusState private var isInputFocused: Bool

    @State private var inputOffsetString: String = ""
    @State private var isDraggingSlider: Bool = false

    @State private var isShowingInitializationSheet: Bool = false
    
    /// 判斷當前藍牙連線是否處於失敗或未尋獲裝置狀態
    private var isFailed: Bool {
        bleVM.statusMessage.contains("失敗")
            || bleVM.statusMessage.contains("未找到")
    }

    /// 依據當前藍牙連線與掃描階段計算對應呈現之圖示名稱
    private var statusIconName: String {
        if !bleVM.isBluetoothPoweredOn {
            return "antenna.radiowaves.left.and.right.slash"
        } else if bleVM.isConnected {
            return "checkmark.circle.fill"
        } else if bleVM.isScanning {
            return "antenna.radiowaves.left.and.right"
        } else if isFailed {
            return "exclamationmark.circle.fill"
        } else {
            return "hand.raised.slash.fill"
        }
    }

    /// 依據藍牙運作狀態計算主要情境識別色彩
    private var statusColor: Color {
        if !bleVM.isBluetoothPoweredOn {
            return AppTheme.accent(for: colorScheme)
        } else if bleVM.isConnected {
            return .green
        } else if bleVM.isScanning {
            return AppTheme.primary(for: colorScheme)
        } else if isFailed {
            return .red
        } else {
            return AppTheme.textSecondary(for: colorScheme)
        }
    }

    /// 根據藍牙狀態動態決定操作按鈕背景色
    private var actionButtonColor: Color {
        if !bleVM.isBluetoothPoweredOn {
            return AppTheme.textSecondary(for: colorScheme).opacity(0.6)
        } else if bleVM.isScanning {
            return AppTheme.primary(for: colorScheme).opacity(0.7)
        } else {
            return AppTheme.primary(for: colorScheme)
        }
    }

    /// 根據藍牙狀態動態決定操作按鈕文字
    private var actionButtonTitle: String {
        if bleVM.isBluetoothUnauthorized {
            return "前往設定授權藍牙"
        } else if !bleVM.isBluetoothPoweredOn {
            return "前往設定開啟藍牙"
        } else if bleVM.isScanning {
            return "正在搜尋手套..."
        } else if isFailed {
            return "重新嘗試連線"
        } else {
            return "開始連線手套"
        }
    }

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        Text("手套設定與狀態")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 25)
                            .padding(.top, 18)

                        if bleVM.isConnected {
                            connectedPanel
                        } else {
                            disconnectedPanel
                        }

                        Spacer(minLength: 30)
                    }
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: isInputFocused) { _, newValue in
                    if newValue {
                        Task {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo("LengthInputCard", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: bleVM.isConnected)
            .animation(.easeInOut(duration: 0.3), value: bleVM.isBluetoothPoweredOn)
        }
        .sheet(isPresented: $isShowingInitializationSheet) {
            GloveInitializationSheet()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            hideKeyboard()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button(action: {
                    togglePositiveNegative()
                }) {
                    Text("+ / -")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.primary(for: colorScheme).opacity(0.12))
                        .cornerRadius(6)
                }

                Spacer()

                Button("完成") {
                    hideKeyboard()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.primary(for: colorScheme))
            }
        }
    }

    /// 已成功建立連線時之手套資訊與參數控制面板
    private var connectedPanel: some View {
        VStack(spacing: 20) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 20, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("手套已連線")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Text("運作狀態正常")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        bleVM.disconnect()
                    }
                }) {
                    Text("中斷連線")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
            .padding(.horizontal, 25)

            VStack(spacing: 15) {
                HStack {
                    Text("目前裝置電量")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    Spacer()
                    BatteryIcon(level: bleVM.batteryLevel)
                }

                HStack(alignment: .bottom, spacing: 2) {
                    Text("\(bleVM.batteryLevel)")
                        .font(.system(size: 60, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Text("%")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .padding(.bottom, 10)
                }
            }
            .padding(25)
            .frame(maxWidth: .infinity)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
            .padding(.horizontal, 25)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(bleVM.isMotorEnabled ? Color.green.opacity(0.15) : AppTheme.textSecondary(for: colorScheme).opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: bleVM.isMotorEnabled ? "bolt.fill" : "bolt.slash.fill")
                        .foregroundColor(bleVM.isMotorEnabled ? .green : AppTheme.textSecondary(for: colorScheme))
                        .font(.system(size: 16))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        bleVM.isMotorEnabled
                            ? "馬達已啟動"
                            : (bleVM.isAutomaticSuppressionEnabled ? "自動抑震監測中" : "手動微調模式")
                    )
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(bleVM.isMotorEnabled ? .green : AppTheme.textPrimary(for: colorScheme))

                    Text(
                        bleVM.isMotorEnabled
                            ? "手套正在調整拉力或回到定位"
                            : (bleVM.isAutomaticSuppressionEnabled
                                ? "手套處於監測狀態，偵測到顯著震顫時將自動介入；您也可以隨時使用下方微調"
                                : "已暫停自動抑震；您仍可手動微調鬆緊度，防護機制維持運作")
                    )
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()
            }
            .padding(14)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(bleVM.isMotorEnabled ? Color.green.opacity(0.3) : AppTheme.textSecondary(for: colorScheme).opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
            .padding(.horizontal, 25)
            .animation(.easeInOut(duration: 0.25), value: bleVM.isMotorEnabled)
            automaticModeCard
            initializationCard
            lengthAdjustmentCard
                .id("LengthInputCard")
        }
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity
            )
        )
    }
    
    /// 手套初始化入口卡片
    private var initializationCard: some View {
        Button(action: {
            isShowingInitializationSheet = true
        }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.primary(for: colorScheme).opacity(0.12))
                        .frame(width: 42, height: 42)

                    Image(systemName: "slider.horizontal.2.square")
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .font(.system(size: 20, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("初始化手套配戴長度")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text("重新校準初始拉力與基準舒適鬆緊度")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
            .padding(.horizontal, 25)
        }
        .buttonStyle(.plain)
    }

    private var automaticModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("抑震控制模式")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Text(bleVM.isAutomaticSuppressionEnabled ? "開啟自動抑震功能" : "暫停自動抑震功能，可進入初始化視窗進行調整")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()

                Text(bleVM.isAutomaticSuppressionEnabled ? "AUTO" : "MANUAL")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(bleVM.isAutomaticSuppressionEnabled ? .green : AppTheme.accent(for: colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((bleVM.isAutomaticSuppressionEnabled ? Color.green : AppTheme.accent(for: colorScheme)).opacity(0.12))
                    .clipShape(Capsule())
            }

            Button(action: {
                bleVM.setAutomaticSuppression(!bleVM.isAutomaticSuppressionEnabled)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: bleVM.isAutomaticSuppressionEnabled ? "pause.circle.fill" : "play.circle.fill")
                    Text(bleVM.isAutomaticSuppressionEnabled ? "暫停自動抑震並進入微調" : "啟用自動抑震")
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundColor(.white)
                .background(bleVM.isAutomaticSuppressionEnabled ? AppTheme.accent(for: colorScheme) : AppTheme.primary(for: colorScheme))
                .cornerRadius(12)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
        .padding(.horizontal, 25)
    }
    
    /// 收線長度微調滑桿控制、手動數值輸入與操作限制說明卡片
    private var lengthAdjustmentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "ruler.fill")
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                Text("收線長度微調")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Spacer()

                let offsetMmInt = Int(round(bleVM.lengthOffsetMm * 10))
                let formattedValue = String(format: "%@%d mm", offsetMmInt > 0 ? "+" : "", offsetMmInt)
                Text(formattedValue)
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }

            Slider(
                value: $bleVM.lengthOffsetMm,
                in: -BluetoothViewModel.maxLengthAdjustmentCm...BluetoothViewModel.maxLengthAdjustmentCm,
                step: 0.5,
                onEditingChanged: { editing in
                    isDraggingSlider = editing
                    if editing {
                        isInputFocused = false
                    } else {
                        bleVM.commitSliderLengthAdjustment()
                        DispatchQueue.main.async {
                            isDraggingSlider = false
                            syncInputTextWithSlider()
                        }
                    }
                }
            )
            .accentColor(AppTheme.primary(for: colorScheme))
            .disabled(isInputFocused)
            .opacity(isInputFocused ? 0.55 : 1.0)

            HStack {
                Text("拉緊 (-50 mm)")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                Spacer()
                Text("基準 (0 mm)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Spacer()
                Text("放鬆 (+50 mm)")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            HStack(spacing: 8) {
                Text("手動輸入目標值")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .fixedSize()

                Spacer()

                HStack(spacing: 6) {
                    Button(action: {
                        togglePositiveNegative()
                    }) {
                        Text(inputOffsetString.hasPrefix("-") ? "-" : "+")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .frame(width: 32, height: 32)
                            .background(AppTheme.primary(for: colorScheme).opacity(0.12))
                            .cornerRadius(8)
                    }

                    TextField("0 ~ 50", text: $inputOffsetString)
                        .keyboardType(.numberPad)
                        .focused($isInputFocused)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .frame(width: 70)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(AppTheme.background(for: colorScheme))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isInputFocused ? AppTheme.primary(for: colorScheme) : Color.clear, lineWidth: 1.5)
                        )
                        .onChange(of: isInputFocused) { _, newValue in
                            if !newValue {
                                commitManualInput()
                            }
                        }

                    Text("mm")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .fixedSize()

                    if isInputFocused {
                        Button(action: {
                            hideKeyboard()
                        }) {
                            Text("確定")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.primary(for: colorScheme))
                                .cornerRadius(8)
                        }
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale))
                    }
                }
            }
            .padding(.top, 4)

            if bleVM.isMotorEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                    Text("馬達運轉抑制中，已暫停長度微調（待命中即可調整）")
                        .font(.caption2)
                }
                .foregroundColor(AppTheme.accent(for: colorScheme))
                .padding(.top, 2)
                .transition(.opacity)
            }

            Divider()
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                    Text("收線長度微調使用說明")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("• 0mm 為系統預設基準長度，向左滑動為拉緊以增加支撐，向右滑動為放線放鬆（以5mm為微調單位）。")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .lineSpacing(2)

                    Text("• 可透過滑桿拖曳或手動輸入數值、兩者操作互斥以防衝與，輸入範圍為 -50至+50mm。")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .lineSpacing(2)

                    Text("• 請於馬達待命（未啟動）時進行調整，當馬達正啟動制廠頭時，控制項目將暫時鎖定以確保安全。")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .lineSpacing(2)

                    Text("• 手套內建防拉扯與最大行程保護機制，請安心依照電際配戴感受進行微調。")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .lineSpacing(2)
                }
            }
            .padding(14)
            .background(AppTheme.primary(for: colorScheme).opacity(0.08))
            .cornerRadius(12)
        }
        .padding(20)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
        .padding(.horizontal, 25)
        .onAppear {
            syncInputTextWithSlider()
        }
        .onChange(of: bleVM.lengthOffsetMm) { _, _ in
            if !isInputFocused {
                syncInputTextWithSlider()
            }
        }
    }

    /// 未建立連線時之提示與手動掃描連線面板
    private var disconnectedPanel: some View {
        VStack(spacing: 20) {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.1))
                        .frame(width: 84, height: 84)

                    Image(systemName: statusIconName)
                        .font(.system(size: 38, weight: .medium))
                        .foregroundColor(statusColor)
                }
                .padding(.top, 10)

                VStack(spacing: 6) {
                    Text(
                        !bleVM.isBluetoothPoweredOn
                            ? (bleVM.isBluetoothUnauthorized
                                ? "藍牙未授權" : "手機藍牙未開啟") : "智慧手套尚未連線"
                    )
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Text(bleVM.statusMessage)
                        .font(.system(size: 13))
                        .foregroundColor(statusColor)
                        .multilineTextAlignment(.center)
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        bleVM.startScan()
                    }
                }) {
                    HStack(spacing: 8) {
                        if bleVM.isScanning {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }

                        Image(
                            systemName: !bleVM.isBluetoothPoweredOn
                                ? "gearshape.fill" : "wave.3.right"
                        )
                        .font(.system(size: 14))

                        Text(actionButtonTitle)
                            .font(.system(size: 15, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(actionButtonColor)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(bleVM.isScanning)
                .padding(.horizontal, 5)

                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .font(.system(size: 12))
                        Text("確認手套電源已開啟")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .font(.system(size: 12))
                        Text("請將手機靠近手套設備")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(25)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
            .padding(.horizontal, 25)
            .padding(.top, 10)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                )
            )

            if !bleVM.isBluetoothPoweredOn {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppTheme.accent(for: colorScheme))
                        .font(.system(size: 18))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            bleVM.isBluetoothUnauthorized
                                ? "尚未允許此 App 使用藍牙" : "偵測到手機藍牙已關閉"
                        )
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(AppTheme.accent(for: colorScheme))

                        Text(
                            bleVM.isBluetoothUnauthorized
                                ? "請點擊上方按鈕前往「設定」開啟藍牙權限"
                                : "請點擊上方按鈕前往「設定」開啟藍牙; 若設定已開啟或顯示「想要使用藍牙進行新連線」, 請由右上角下滑開啟「控制中心」點亮藍牙。( 因 iOS 機制中控制中心未點亮僅是暫停新連線, 設定仍維持開啟 )"
                        )
                        .font(.system(size: 11.5))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(14)
                .background(AppTheme.accent(for: colorScheme).opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal, 25)
                .transition(.opacity)
            }
        }
    }

    /// 切換手動輸入欄位之正負號前綴
    private func togglePositiveNegative() {
        let trimmed = inputOffsetString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("-") {
            inputOffsetString = String(trimmed.dropFirst())
        } else if !trimmed.isEmpty && trimmed != "0" {
            inputOffsetString = "-" + trimmed
        } else {
            inputOffsetString = "-"
        }
    }

    /// 將滑桿目前的長度設定同步至文字輸入框
    private func syncInputTextWithSlider() {
        let mmValue = Int(round(bleVM.lengthOffsetMm * 10))
        inputOffsetString = "\(mmValue)"
    }

    /// 驗證並送出手動輸入之毫米數值至手套硬體端
    private func commitManualInput() {
        let trimmed = inputOffsetString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedMm = Double(trimmed) else {
            syncInputTextWithSlider()
            return
        }

        let maxMm = Double(BluetoothViewModel.maxLengthAdjustmentMm)
        let clampedMm = min(max(parsedMm, -maxMm), maxMm)
        let targetCm = round(clampedMm) / 10.0

        bleVM.sendManualLengthInputCm(targetCm)

        inputOffsetString = "0"
        bleVM.lengthOffsetMm = 0.0
    }
}
