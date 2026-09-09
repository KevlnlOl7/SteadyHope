import SwiftUI

/// 生理數據填寫與編輯之工作表表單檢視
struct HealthVitalsFormSheet: View {
    @ObservedObject var vitalsVM: HealthVitalsViewModel
    var title: String
    var isEditing: Bool
    var filterDate: Date

    @State private var showDatePickerSheet: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.96, green: 0.97, blue: 0.98)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        timeSection
                        bpAndSugarSection
                        tempAndWeightSection
                        sleepAndFoodSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDatePickerSheet) {
                datePickerSheet
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if isEditing {
                            vitalsVM.editingVitals = nil
                        } else {
                            vitalsVM.showAddVitalsSheet = false
                        }
                    }
                    .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    let isSettedSystolic = !vitalsVM.systolicBP.trimmingCharacters(in: .whitespaces).isEmpty
                    let isSettedDiastolic = !vitalsVM.diastolicBP.trimmingCharacters(in: .whitespaces).isEmpty
                    let isBloodPressureInvalid = isSettedSystolic != isSettedDiastolic

                    Button("儲存") {
                        Task {
                            let dateString = filterDate.toString(format: "yyyy-MM-dd")
                            await vitalsVM.saveRecord(targetDateString: dateString)
                        }
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isBloodPressureInvalid ? .gray : .blue)
                    .disabled(isBloodPressureInvalid)
                }
            }
        }
    }

    /// 測量時間選擇卡片
    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("測量時間")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Button {
                showDatePickerSheet = true
            } label: {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)

                    Text(formattedDateTime(vitalsVM.recordDate))
                        .font(.system(size: 15))
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.6))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
    }

    /// 血壓與血糖填寫卡片
    private var bpAndSugarSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                Text("血壓與血糖")
                    .font(.system(size: 15, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("血壓 (收縮壓 / 舒張壓)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField(
                        "",
                        text: $vitalsVM.systolicBP,
                        prompt: Text("收縮壓").foregroundColor(.gray.opacity(0.6))
                    )
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.96, green: 0.97, blue: 0.98))
                    .cornerRadius(8)

                    Text("/")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    TextField(
                        "",
                        text: $vitalsVM.diastolicBP,
                        prompt: Text("舒張壓").foregroundColor(.gray.opacity(0.6))
                    )
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.96, green: 0.97, blue: 0.98))
                    .cornerRadius(8)

                    Text("mmHg")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                let isSettedSystolic = !vitalsVM.systolicBP.trimmingCharacters(in: .whitespaces).isEmpty
                let isSettedDiastolic = !vitalsVM.diastolicBP.trimmingCharacters(in: .whitespaces).isEmpty

                if isSettedSystolic != isSettedDiastolic {
                    Text("* 血壓欄位需同時填寫收縮壓與舒張壓")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(.top, 2)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("血糖")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField(
                        "",
                        text: $vitalsVM.bloodSugar,
                        prompt: Text("飯前/飯後血糖值").foregroundColor(.gray.opacity(0.6))
                    )
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.96, green: 0.97, blue: 0.98))
                    .cornerRadius(8)

                    Text("mg/dL")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
    }

    /// 體溫與體重填寫卡片
    private var tempAndWeightSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "thermometer.medium")
                    .foregroundColor(.orange)
                Text("體溫與體重")
                    .font(.system(size: 15, weight: .bold))
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("體溫")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        TextField(
                            "",
                            text: $vitalsVM.bodyTemp,
                            prompt: Text("例: 36.5").foregroundColor(.gray.opacity(0.6))
                        )
                        .keyboardType(.decimalPad)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
                        .cornerRadius(8)

                        Text("°C")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("體重")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        TextField(
                            "",
                            text: $vitalsVM.bodyWeight,
                            prompt: Text("例: 65.0").foregroundColor(.gray.opacity(0.6))
                        )
                        .keyboardType(.decimalPad)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
                        .cornerRadius(8)

                        Text("kg")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
    }

    /// 睡眠與飲食填寫卡片
    private var sleepAndFoodSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .foregroundColor(.indigo)
                Text("睡眠與飲食")
                    .font(.system(size: 15, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("睡眠時數")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField(
                        "",
                        text: $vitalsVM.sleepHours,
                        prompt: Text("例: 7.5").foregroundColor(.gray.opacity(0.6))
                    )
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.96, green: 0.97, blue: 0.98))
                    .cornerRadius(8)

                    Text("小時")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("飲食狀況")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                TextField(
                    "",
                    text: $vitalsVM.foodAmount,
                    prompt: Text("例：正常、食慾不佳、半碗").foregroundColor(.gray.opacity(0.6))
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(red: 0.96, green: 0.97, blue: 0.98))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
    }

    /// 日期時間選擇彈窗
    private var datePickerSheet: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "選擇測量時間",
                    selection: $vitalsVM.recordDate,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .tint(.blue)
                .padding()

                Spacer()
            }
            .background(Color(red: 0.96, green: 0.97, blue: 0.98))
            .navigationTitle("選擇測量時間")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        showDatePickerSheet = false
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.blue)
                }
            }
        }
        .presentationDetents([.medium, .height(520)])
    }

    /// 格式化量測日期時間字串
    /// - Parameter date: 欲格式化之 Date 實例
    /// - Returns: 格式化後之繁體中文日期時間字串
    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "yyyy 年 MM 月 dd 日 HH:mm"
        return formatter.string(from: date)
    }
}
