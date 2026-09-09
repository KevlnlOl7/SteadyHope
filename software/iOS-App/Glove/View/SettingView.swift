import SwiftUI

struct SettingView: View {
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject private var bleVM = BluetoothViewModel.shared

    @FocusState private var isInputFocused: Bool

    @State private var inputOffsetString: String = ""
    @State private var isDraggingSlider: Bool = false

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
            return .orange
        } else if bleVM.isConnected {
            return .green
        } else if bleVM.isScanning {
            return .blue
        } else if isFailed {
            return .red
        } else {
            return .secondary
        }
    }

    /// 根據藍牙狀態動態決定操作按鈕背景色
    private var actionButtonColor: Color {
        if !bleVM.isBluetoothPoweredOn {
            return Color.gray.opacity(0.6)
        } else if bleVM.isScanning {
            return Color.blue.opacity(0.7)
        } else {
            return Color.blue
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
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        Text("手套設定與狀態")
                            .font(.system(size: 28, weight: .bold))
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
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(6)
                }

                Spacer()

                Button("完成") {
                    hideKeyboard()
                }
                .font(.system(size: 16, weight: .semibold))
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
                    Text("運作狀態正常")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
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
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
            .padding(.horizontal, 25)

            VStack(spacing: 15) {
                HStack {
                    Text("目前裝置電量")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    BatteryIcon(level: bleVM.batteryLevel)
                }

                HStack(alignment: .bottom, spacing: 2) {
                    Text("\(bleVM.batteryLevel)")
                        .font(.system(size: 60, weight: .medium))
                    Text("%")
                        .font(.system(size: 24))
                        .padding(.bottom, 10)
                }
            }
            .padding(25)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
            .padding(.horizontal, 25)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(bleVM.isMotorEnabled ? Color.green.opacity(0.15) : Color.gray.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: bleVM.isMotorEnabled ? "bolt.fill" : "bolt.slash.fill")
                        .foregroundColor(bleVM.isMotorEnabled ? .green : .secondary)
                        .font(.system(size: 16))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(bleVM.isMotorEnabled ? "馬達已啟動 (抑制震顫中)" : "馬達待命中 (未啟動)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(bleVM.isMotorEnabled ? .green : .primary)

                    Text(bleVM.isMotorEnabled ? "智慧手套正在即時輸出動態阻尼拉力" : "手套處於監測狀態，偵測到顯著震顫時將自動介入")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(14)
            .background(Color.white)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(bleVM.isMotorEnabled ? Color.green.opacity(0.3) : Color.gray.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
            .padding(.horizontal, 25)
            .animation(.easeInOut(duration: 0.25), value: bleVM.isMotorEnabled)

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

    /// 收線長度微調滑桿控制、手動數值輸入與操作限制說明卡片
    private var lengthAdjustmentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "ruler.fill")
                    .foregroundColor(.blue)
                Text("收線長度微調")
                    .font(.system(size: 16, weight: .medium))
                Spacer()

                let offsetMmInt = Int(round(bleVM.lengthOffsetMm * 10))
                let formattedValue = String(format: "%@%d mm", offsetMmInt > 0 ? "+" : "", offsetMmInt)
                Text(formattedValue)
                    .foregroundColor(.blue)
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
            .accentColor(.blue)
            .disabled(bleVM.isMotorEnabled || isInputFocused)
            .opacity((bleVM.isMotorEnabled || isInputFocused) ? 0.45 : 1.0)

            HStack {
                Text("拉緊 (-50 mm / -5 cm)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("基準 (0 mm)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                Text("放鬆 (+50 mm / +5 cm)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Text("手動輸入目標值")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize()

                Spacer()

                HStack(spacing: 6) {
                    Button(action: {
                        togglePositiveNegative()
                    }) {
                        Text(inputOffsetString.hasPrefix("-") ? "-" : "+")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.blue)
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(8)
                    }
                    .disabled(bleVM.isMotorEnabled)

                    TextField("0 ~ 50", text: $inputOffsetString)
                        .keyboardType(.numberPad)
                        .focused($isInputFocused)
                        .disabled(bleVM.isMotorEnabled)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isInputFocused ? Color.blue : Color.clear, lineWidth: 1.5)
                        )
                        .onChange(of: isInputFocused) { _, newValue in
                            if !newValue {
                                commitManualInput()
                            }
                        }

                    Text("mm")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
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
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .opacity(bleVM.isMotorEnabled ? 0.45 : 1.0)
            }
            .padding(.top, 4)

            if bleVM.isMotorEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                    Text("馬達運轉抑制中，已暫停長度微調（待命中即可調整）")
                        .font(.caption2)
                }
                .foregroundColor(.orange)
                .padding(.top, 2)
                .transition(.opacity)
            }

            Divider()
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.blue)
                    Text("收線長度微調使用說明")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("• Slider 每次代表一筆『相對調整』命令；向左為拉緊、向右為放鬆，以 5 mm 為步進，放開後送出一次並自動回到 0。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)

                    Text("• Slider 與手動輸入的單次命令範圍皆為 -50 至 +50 mm（-5 至 +5 cm）；STM32 仍會依實際線長安全範圍拒絕超行程命令。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)

                    Text("• 請於馬達待命（未啟動）時進行調整；當馬達正啟動抑制震顫時，控制項目將暫時鎖定以確保安全。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)

                    Text("• 手套內建防拉扯與最大行程保護機制，請安心依照實際配戴感受進行微調。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }
            }
            .padding(14)
            .background(Color(red: 0.95, green: 0.97, blue: 1.0))
            .cornerRadius(12)
        }
        .padding(20)
        .background(Color.white)
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
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                        Text("確認手套電源已開啟")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                        Text("請將手機靠近手套設備")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(25)
            .background(Color.white)
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
                        .foregroundColor(.orange)
                        .font(.system(size: 18))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            bleVM.isBluetoothUnauthorized
                                ? "尚未允許此 App 使用藍牙" : "偵測到手機藍牙已關閉"
                        )
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.orange)

                        Text(
                            bleVM.isBluetoothUnauthorized
                                ? "請點擊上方按鈕前往「設定」開啟藍牙權限"
                                : "請點擊上方按鈕前往「設定」開啟藍牙; 若設定已開啟或顯示「想要使用藍牙進行新連線」, 請由右上角下滑開啟「控制中心」點亮藍牙。( 因 iOS 機制中控制中心未點亮僅是暫停新連線, 設定仍維持開啟 )"
                        )
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(14)
                .background(Color.orange.opacity(0.1))
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
