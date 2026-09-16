import SwiftUI

/// 生理健康數據分頁檢視，負責展示生理量測清單與詳細數據卡片
struct HealthVitalsTabView: View {
    @ObservedObject var vitalsVM: HealthVitalsViewModel
    var isCaregiver: Bool
    var filterDate: Date
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundColor(.red)
                    Text("生理健康數值")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Spacer()

                    if !isCaregiver {
                        Button {
                            vitalsVM.clearInputs()
                            vitalsVM.recordDate = filterDate
                            vitalsVM.showAddVitalsSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("記錄生理數據")
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 4)

                if vitalsVM.isLoading {
                    ProgressView("載入中...")
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .padding(.vertical, 30)
                } else if vitalsVM.vitalsList.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 36))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.5))
                        Text("今日尚無生理數據紀錄")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(AppTheme.cardBackground(for: colorScheme))
                    .cornerRadius(12)
                    .softCardShadow()
                } else {
                    ForEach(vitalsVM.vitalsList) { item in
                        vitalsCard(item)
                    }
                }
            }
            .padding()
        }
        .background(AppTheme.background(for: colorScheme))
    }

    /// 單張生理數據摘要卡片
    /// - Parameter item: 生理量測回應傳輸物件
    private func vitalsCard(_ item: HealthVitalsResponseDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .font(.caption)
                    Text(item.date.toString(format: "HH:mm"))
                        .font(.subheadline.bold())
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                }

                Spacer()

                if !isCaregiver {
                    Menu {
                        Button {
                            vitalsVM.startEditing(item)
                        } label: {
                            Label("編輯紀錄", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            if let recordID = item.id {
                                Task {
                                    let dateString = filterDate.toString(format: "yyyy-MM-dd")
                                    await vitalsVM.deleteRecord(
                                        id: recordID,
                                        targetDateString: dateString
                                    )
                                }
                            }
                        } label: {
                            Label("刪除紀錄", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.caption.bold())
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .padding(4)
                    }
                }
            }
            Divider()

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                if let s = item.systolicBP, let d = item.diastolicBP, !s.isEmpty || !d.isEmpty {
                    vitalItemView(
                        icon: "heart.fill",
                        color: .red,
                        title: "血壓",
                        value: "\(s)/\(d) mmHg"
                    )
                }
                if let sugar = item.bloodSugar, !sugar.isEmpty {
                    vitalItemView(
                        icon: "drop.fill",
                        color: .purple,
                        title: "血糖",
                        value: "\(sugar) mg/dL"
                    )
                }
                if let temp = item.bodyTemp, !temp.isEmpty {
                    vitalItemView(
                        icon: "thermometer.medium",
                        color: .orange,
                        title: "體溫",
                        value: "\(temp) °C"
                    )
                }
                if let weight = item.bodyWeight, !weight.isEmpty {
                    vitalItemView(
                        icon: "scalemass.fill",
                        color: AppTheme.primary(for: colorScheme),
                        title: "體重",
                        value: "\(weight) kg"
                    )
                }
                if let sleep = item.sleepHours, !sleep.isEmpty {
                    vitalItemView(
                        icon: "moon.stars.fill",
                        color: .indigo,
                        title: "睡眠",
                        value: "\(sleep) 小時"
                    )
                }
                if let food = item.foodAmount, !food.isEmpty {
                    vitalItemView(
                        icon: "fork.knife",
                        color: .green,
                        title: "飲食",
                        value: food
                    )
                }
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(12)
        .softCardShadow()
    }

    /// 單一生理項目資訊標籤元件
    /// - Parameters:
    ///   - icon: SF Symbols 圖示名稱
    ///   - color: 圖示主題色彩
    ///   - title: 項目標題文字
    ///   - value: 量測數值文字
    private func vitalItemView(
        icon: String,
        color: Color,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }
            Spacer()
        }
        .padding(8)
        .background(AppTheme.background(for: colorScheme))
        .cornerRadius(8)
    }
}
