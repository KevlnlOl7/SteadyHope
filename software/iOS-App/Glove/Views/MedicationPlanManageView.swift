import SwiftUI

struct MedicationPlanManageView: View {
    @ObservedObject var planVM: MedicationPlanViewModel
    var currentUserID: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    addOrEditPlanCard
                    configuredPlanListCard
                }
                .padding()
            }
            .background(AppTheme.background(for: colorScheme))
            .navigationTitle("管理每日用藥清單")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                        .font(.body.bold())
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                }
            }
        }
    }

    /// 新增或編輯用藥計畫之輸入表單卡片
    private var addOrEditPlanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(planVM.editingPlanIndex == nil ? "新增每日用藥清單" : "編輯每日用藥清單")
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Spacer()
                if planVM.editingPlanIndex != nil {
                    Button("取消編輯") { planVM.resetPlanForm() }
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            VStack(spacing: 0) {
                // 用藥方式選擇（口服 / 貼片 / 注射）
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.2x2.fill")
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .frame(width: 20)
                    Picker("用藥方式", selection: $planVM.planMedType) {
                        ForEach(MedicationType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: planVM.planMedType) {
                        if planVM.planMedType == .injection {
                            if let injectionPreset = MedicationPresets.allList.first(where: { $0.medType == .injection }) {
                                planVM.planName = injectionPreset.name
                                let doseStr = injectionPreset.commonDoses.first ?? "1ml"
                                planVM.planDose = String(doseStr.filter { $0.isNumber || $0 == "." })
                                planVM.planUnit = String(doseStr.filter { !$0.isNumber && $0 != "." })
                            }
                        } else if planVM.planMedType == .oral {
                            planVM.planName = ""
                            planVM.planDose = ""
                            planVM.planUnit = ""
                        }
                    }
                }
                .padding()

                Divider().padding(.leading, 44)

                if planVM.planMedType == .oral || planVM.planMedType == .injection {
                    HStack(spacing: 12) {
                        Image(systemName: "pill.fill")
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .frame(width: 20)

                        // 藥品名稱輸入框
                        TextField("藥品名稱", text: $planVM.planName)
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        if planVM.planMedType == .oral {
                            Menu {
                                let groupedList = Dictionary(
                                    grouping: MedicationPresets.oralList,
                                    by: { $0.category }
                                )
                                
                                ForEach(groupedList.keys.sorted(), id: \.self) { category in
                                    Section(header: Text(category)) {
                                        ForEach(groupedList[category] ?? []) { item in
                                            Button {
                                                planVM.planName = "\(item.name) (\(item.strength))"

                                                let doseStr = item.commonDoses.first ?? "1顆"
                                                if doseStr == "半顆" {
                                                    planVM.planDose = "0.5"
                                                    planVM.planUnit = "顆"
                                                } else {
                                                    planVM.planDose = String(
                                                        doseStr.filter { $0.isNumber || $0 == "." }
                                                    )
                                                    let unit = String(
                                                        doseStr.filter { !$0.isNumber && $0 != "." }
                                                    )
                                                    planVM.planUnit = unit.isEmpty ? "顆" : unit
                                                }
                                            } label: {
                                                Text("\(item.name) (\(item.strength))")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("快選")
                                        .font(.subheadline.bold())
                                    Image(systemName: "chevron.down")
                                        .font(.caption.bold())
                                }
                                .foregroundColor(AppTheme.primary(for: colorScheme))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.primary(for: colorScheme).opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding()

                    Divider().padding(.leading, 44)

                    HStack(spacing: 12) {
                        Image(systemName: "scalemass.fill")
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .frame(width: 20)
                        TextField("用量", text: $planVM.planDose)
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                        TextField("單位", text: $planVM.planUnit)
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            .frame(width: 100)
                        Spacer()
                    }
                    .padding()

                    Divider().padding(.leading, 44)
                }

                // 重複頻率設定
                HStack(spacing: 12) {
                    Image(systemName: "repeat")
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .frame(width: 20)
                    Text("重複")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Spacer()
                    Picker("重複", selection: $planVM.repeatFrequency) {
                        ForEach(RepeatFrequency.allCases) { freq in
                            Text(freq.rawValue).tag(freq)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.primary(for: colorScheme))
                }
                .padding()

                // 自訂重複規則入口
                if planVM.repeatFrequency == .custom {
                    Divider().padding(.leading, 44)
                    NavigationLink {
                        CustomRepeatView(planVM: planVM)
                    } label: {
                        HStack {
                            Text("自訂重複細節")
                                .font(.subheadline)
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            Spacer()
                            Text(planVM.customRepeatSummaryText)
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                        .padding()
                    }
                }

                Divider().padding(.leading, 44)

                // 時間點選定區域
                if planVM.planMedType == .patch {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .frame(width: 20)
                        Text("每日貼片時間")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Spacer()
                        DatePicker("", selection: $planVM.inputTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.fill")
                                .foregroundColor(AppTheme.primary(for: colorScheme))
                                .frame(width: 20)
                            Text("服藥時間")
                                .font(.subheadline)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            Spacer()
                            DatePicker("", selection: $planVM.inputTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Button { planVM.addTimePoint() } label: {
                                Text("新增時間")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.primary(for: colorScheme).opacity(0.12))
                                    .foregroundColor(AppTheme.primary(for: colorScheme))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }

                        if planVM.selectedTimes.isEmpty {
                            Text("請選擇時間並點擊「新增時間」")
                                .font(.caption2)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .padding(.leading, 32)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(planVM.selectedTimes, id: \.self) { time in
                                        HStack(spacing: 4) {
                                            Text(time.toString(format: "HH:mm"))
                                                .font(.subheadline.bold())
                                            Button { planVM.removeTimePoint(time) } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.white.opacity(0.8))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(AppTheme.primary(for: colorScheme))
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                    }
                                }
                                .padding(.leading, 32)
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(AppTheme.background(for: colorScheme))
            .cornerRadius(10)

            // 提交 / 儲存按鈕
            Button {
                planVM.savePlan(currentUserID: currentUserID)
            } label: {
                HStack {
                    Image(systemName: planVM.editingPlanIndex == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                    Text(planVM.isPatchButtonDisabled ? "已建立貼片處方 (每日固定貼 1 次)" : (planVM.editingPlanIndex == nil ? "加入每日用藥清單" : "儲存修改"))
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(planVM.isFormInvalid ? AppTheme.textSecondary(for: colorScheme).opacity(0.4) : (planVM.editingPlanIndex == nil ? AppTheme.primary(for: colorScheme) : Color.green))
                .cornerRadius(10)
            }
            .disabled(planVM.isFormInvalid)
        }
        .padding()
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
    }

    /// 已設定排程清單檢視卡片
    private var configuredPlanListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("已設定用藥清單 (\(planVM.planList.count) 筆)")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            Divider()

            if planVM.planList.isEmpty {
                Text("目前尚未建立固定用藥處方")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(planVM.planList.enumerated()), id: \.offset) { index, plan in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(plan.name).font(.body.bold())
                                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                    if !plan.dose.isEmpty {
                                        Text("(\(plan.dose))")
                                            .font(.subheadline)
                                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                    }
                                }
                                Text("服藥時間：\(planVM.formatPlanTimes(plan))")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                Text("重複週期：\(plan.repeatSummary)")
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.primary(for: colorScheme))
                            }
                            Spacer()

                            Text(plan.medType.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(plan.medType == .patch ? AppTheme.accent(for: colorScheme).opacity(0.15) : AppTheme.primary(for: colorScheme).opacity(0.15))
                                .foregroundColor(plan.medType == .patch ? AppTheme.accent(for: colorScheme) : AppTheme.primary(for: colorScheme))
                                .cornerRadius(4)

                            Button { planVM.loadPlanForEditing(at: index) } label: {
                                Image(systemName: "pencil")
                                    .font(.subheadline)
                                    .foregroundColor(AppTheme.primary(for: colorScheme))
                                    .padding(.leading, 8)
                            }
                            .buttonStyle(.plain)

                            Button { planVM.deletePlan(at: index) } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline)
                                    .foregroundColor(.red.opacity(0.7))
                                    .padding(.leading, 6)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)

                        if index < planVM.planList.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.03), radius: 3)
    }
}

/// 自訂週期細部設定檢視（支援依天、週、月設定頻率與特定日期）
struct CustomRepeatView: View {
    @ObservedObject var planVM: MedicationPlanViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            Section {
                Picker("頻率", selection: $planVM.customUnit) {
                    ForEach(CustomRepeatUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .tint(AppTheme.primary(for: colorScheme))

                Stepper(value: $planVM.customInterval, in: 1...99) {
                    HStack {
                        Text("每")
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        Spacer()
                        Text("\(planVM.customInterval) \(planVM.customUnit.rawValue)")
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
            } footer: {
                Text(planVM.customRepeatFooterText)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            if planVM.customUnit == .week {
                Section(header: Text("重複日期")) {
                    ForEach(Weekday.allCases) { day in
                        HStack {
                            Text(day.shortName)
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            Spacer()
                            if planVM.selectedWeekdays.contains(day) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(AppTheme.primary(for: colorScheme))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if planVM.selectedWeekdays.contains(day) {
                                planVM.selectedWeekdays.remove(day)
                            } else {
                                planVM.selectedWeekdays.insert(day)
                            }
                        }
                    }
                }
            }

            if planVM.customUnit == .month {
                Section(header: Text("日期")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)")
                                .font(.subheadline.bold())
                                .frame(width: 36, height: 36)
                                .background(planVM.selectedMonthDays.contains(day) ? AppTheme.primary(for: colorScheme) : Color.clear)
                                .foregroundColor(planVM.selectedMonthDays.contains(day) ? .white : AppTheme.textPrimary(for: colorScheme))
                                .clipShape(Circle())
                                .onTapGesture {
                                    if planVM.selectedMonthDays.contains(day) {
                                        planVM.selectedMonthDays.remove(day)
                                    } else {
                                        planVM.selectedMonthDays.insert(day)
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle("自訂")
        .navigationBarTitleDisplayMode(.inline)
    }
}
