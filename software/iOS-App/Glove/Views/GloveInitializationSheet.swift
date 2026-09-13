import SwiftUI

struct GloveInitializationSheet: View {
    @ObservedObject private var bleVM = BluetoothViewModel.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// 初始化收緊量（cm）
    @State private var calibrationTakeUpCm: Double = BluetoothViewModel.initialTakeUpDefaultCm
    @State private var isAdjusting: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(AppTheme.primary(for: colorScheme))
                            Text("手套初始配戴校準")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        }

                        Text("進入此畫面後會先暫停自動抑震。請戴妥手套並保持手指自然放鬆，再用下方 Slider 調整初始收緊量，最多 14 cm。放開 Slider 後，手套會自動將馬達移動到指定位置。")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .lineSpacing(4)
                    }
                    .padding(18)
                    .background(AppTheme.cardBackground(for: colorScheme))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)

                    VStack(spacing: 20) {
                        HStack {
                            Text("初始收緊量")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            Spacer()

                            Text(String(format: "%.1f cm", calibrationTakeUpCm))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.primary(for: colorScheme))
                        }

                        Slider(
                            value: $calibrationTakeUpCm,
                            in: BluetoothViewModel.initialTakeUpMinCm...BluetoothViewModel.initialTakeUpMaxCm,
                            step: 0.5,
                            onEditingChanged: { editing in
                                isAdjusting = editing
                                if !editing {
                                    bleVM.sendInitialTakeUpCm(calibrationTakeUpCm)
                                }
                            }
                        )
                        .accentColor(AppTheme.primary(for: colorScheme))

                        HStack {
                            Text("0 cm")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            Spacer()
                            Text("最多 14 cm")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        }

                        Text("目前基準線長：\(Int(BluetoothViewModel.initialCableHomeMm - calibrationTakeUpCm * 10.0)) mm")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    .padding(20)
                    .background(AppTheme.cardBackground(for: colorScheme))
                    .cornerRadius(18)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("目前模式：MANUAL 微調")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppTheme.accent(for: colorScheme))
                        Text("按下「完成並啟用自動抑震」後才會送出 AUTO 指令。若目前馬達正在回位或執行上一筆調整，手套 會先完成安全動作，再使用這個基準長度進入自動模式。")
                            .font(.system(size: 11.5))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(AppTheme.accent(for: colorScheme).opacity(0.08))
                    .cornerRadius(12)

                    Spacer()

                    Button(action: {
                        confirmComfortablePosition()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("完成並啟用自動抑震")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.primary(for: colorScheme))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                        .shadow(color: AppTheme.primary(for: colorScheme).opacity(0.3), radius: 8, y: 4)
                    }
                    .disabled(isAdjusting)
                    .opacity(isAdjusting ? 0.6 : 1.0)
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("手套配戴初始化")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        // 取消時維持 MANUAL，避免尚未確認的長度直接進入自動抑震。
                        dismiss()
                    }
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }
            .onAppear {
                calibrationTakeUpCm = min(
                    max(bleVM.initialTakeUpCm, BluetoothViewModel.initialTakeUpMinCm),
                    BluetoothViewModel.initialTakeUpMaxCm
                )
                // 進入初始化畫面時立刻停止自動 Gate 控制權。
                bleVM.setAutomaticSuppression(false)
            }
        }
    }

    /// 將目前 Slider 值再次送出，並切回 AUTO。
    private func confirmComfortablePosition() {
        bleVM.sendInitialTakeUpCm(calibrationTakeUpCm)
        bleVM.setAutomaticSuppression(true)
        dismiss()
    }
}
