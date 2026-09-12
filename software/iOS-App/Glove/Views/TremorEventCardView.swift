import Charts
import PhotosUI
import SwiftUI
import UIKit

struct TremorEventCardView: View {
    @Binding var event: TremorEvent
    @ObservedObject var dataVM: DataViewModel
    @ObservedObject var loginVM: LoginViewModel
    @Environment(\.colorScheme) private var colorScheme

    let isSimpleMode: Bool
    @Binding var editingEventID: UUID?
    @Binding var tempUserTag: String
    @Binding var tempSelectedImages: [UIImage]
    @Binding var selectedMediaItems: [PhotosPickerItem]
    @Binding var currentPageIndex: Int
    @Binding var previewImage: UIImage?
    @Binding var savingEventID: UUID?
    @Binding var activeInfoSheet: InfoSheetType?
    @Binding var showSaveErrorAlert: Bool
    @Binding var saveErrorMessage: String

    @FocusState.Binding var isFieldFocused: Bool

    @State private var selectedChartTab: Int = 0

    /// 嚴格判定是否為照護者（role == 1）
    private var isCaregiver: Bool {
        if let role = loginVM.userData?.role {
            return role == 1
        }
        if loginVM.boundPartner != nil {
            return true
        }
        return false
    }

    private var isExpanded: Bool {
        dataVM.expandedEventID == event.id
    }

    private var isTagged: Bool {
        !event.userTag.isEmpty && event.userTag != "未標記"
    }

    /// 只有在「非照護者」且當前事件處於編輯狀態時，才開啟編輯面板
    private var isEditing: Bool {
        !isCaregiver && editingEventID == event.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton

            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    if isEditing {
                        editablePanelView
                    } else {
                        readOnlyPanelView
                    }

                    if !isSimpleMode {
                        Divider().padding(.vertical, 4)
                        eventDetailChartsView
                    }
                }
                .padding()
                .background(AppTheme.background(for: colorScheme))
            }
        }
        .cornerRadius(16)
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
    }

    private var headerButton: some View {
        Button(action: {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation(.spring()) {
                if isExpanded {
                    dataVM.expandedEventID = nil
                    editingEventID = nil
                } else {
                    dataVM.expandedEventID = event.id
                    tempUserTag = (event.userTag == "未標記") ? "" : event.userTag
                    tempSelectedImages = event.selectedImages
                }
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(event.timestamp.toString(format: "HH:mm:ss"))
                            .font(.system(size: isSimpleMode ? 18 : 16, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        if isTagged {
                            Text(event.userTag)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        } else {
                            Text("未標記")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accent(for: colorScheme).opacity(0.12))
                                .foregroundColor(AppTheme.accent(for: colorScheme))
                                .cornerRadius(4)
                        }

                        if event.isMotorActive {
                            HStack(spacing: 2) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                Text("抑震介入")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.primary(for: colorScheme).opacity(0.12))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .cornerRadius(4)
                        }
                    }

                    Text(
                        String(
                            format: "強度: %.2f deg/s | 頻率: %.1f Hz",
                            event.rmsValue,
                            event.dominantFrequency
                        )
                    )
                    .font(isSimpleMode ? .subheadline : .caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(isSimpleMode ? 16 : 14)
            .background(AppTheme.cardBackground(for: colorScheme))
        }
        .buttonStyle(.plain)
    }

    private var readOnlyPanelView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("情境標籤：")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Text(event.userTag.isEmpty ? "未標記" : event.userTag)
                    .font(.system(size: 14))
                    .foregroundColor((event.userTag.isEmpty || event.userTag == "未標記") ? AppTheme.accent(for: colorScheme) : AppTheme.textPrimary(for: colorScheme))
            }

            if !event.selectedImages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("紀錄影像 (點擊放大檢視)：")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    TabView {
                        ForEach(Array(event.selectedImages.enumerated()), id: \.offset) { _, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .cornerRadius(10)
                                .onTapGesture {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        previewImage = img
                                    }
                                }
                        }
                    }
                    .frame(height: 200)
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                }
            }

            if !isCaregiver {
                Button(action: {
                    withAnimation {
                        tempUserTag = (event.userTag == "未標記") ? "" : event.userTag
                        tempSelectedImages = event.selectedImages
                        editingEventID = event.id
                    }
                }) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("補充生活情境與照片")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(AppTheme.primary(for: colorScheme).opacity(0.1))
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var editablePanelView: some View {
        let isCurrentlySaving = savingEventID == event.id

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("填寫發作當下活動：")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                TextField("自訂活動 (如: 拿筷子、看電視)", text: $tempUserTag)
                    .focused($isFieldFocused)
                    .textFieldStyle(.roundedBorder)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dataVM.activityOptions, id: \.self) { tag in
                            Button(action: {
                                tempUserTag = tag
                            }) {
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(tempUserTag == tag ? AppTheme.primary(for: colorScheme) : AppTheme.textSecondary(for: colorScheme).opacity(0.15))
                                    .foregroundColor(tempUserTag == tag ? .white : AppTheme.textPrimary(for: colorScheme))
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
            }

            MediaManagementView(
                tempSelectedImages: $tempSelectedImages,
                selectedMediaItems: $selectedMediaItems,
                currentPageIndex: $currentPageIndex,
                previewImage: $previewImage
            )

            HStack(spacing: 12) {
                Button(action: {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    withAnimation {
                        editingEventID = nil
                    }
                }) {
                    Text("取消")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.textSecondary(for: colorScheme).opacity(0.15))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .cornerRadius(10)
                }

                Button(action: {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    savingEventID = event.id

                    var eventToSave = event
                    let finalTag = tempUserTag.trimmingCharacters(in: .whitespacesAndNewlines)
                    eventToSave.userTag = finalTag.isEmpty ? "未標記" : finalTag
                    eventToSave.selectedImages = tempSelectedImages

                    Task {
                        let success = await dataVM.saveTremorEvent(eventToSave)

                        await MainActor.run {
                            savingEventID = nil
                            if success {
                                withAnimation {
                                    editingEventID = nil
                                }
                            } else {
                                UINotificationFeedbackGenerator().notificationOccurred(.error)
                                saveErrorMessage = "網路連線異常或伺服器未回應，請稍後再試。"
                                showSaveErrorAlert = true
                            }
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        if isCurrentlySaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                            Text("儲存中...")
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("儲存標籤紀錄")
                        }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isCurrentlySaving ? AppTheme.textSecondary(for: colorScheme).opacity(0.4) : AppTheme.primary(for: colorScheme))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isCurrentlySaving)
            }
        }
    }

    private var eventDetailChartsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("圖表類型", selection: $selectedChartTab) {
                Text("強度走勢 (RMS)").tag(0)
                Text("頻率分佈 (PSD)").tag(1)
            }
            .pickerStyle(.segmented)

            if selectedChartTab == 0 {
                eventTrendChartView
            } else {
                let psdData = dataVM.calculatePSDData(from: event.rawWindowData)
                psdDetailChartView(psdData: psdData)
            }
        }
    }

    private func generateSafeXAxisTicks(start: Date, end: Date, strideSeconds: TimeInterval) -> [Date] {
        var ticks: [Date] = []
        var current = start.timeIntervalSince1970
        let endInterval = end.timeIntervalSince1970
        
        while current <= endInterval {
            ticks.append(Date(timeIntervalSince1970: current))
            current += strideSeconds
        }
        return ticks
    }

    private var eventTrendChartView: some View {
        let history = dataVM.getHistory(surrounding: event.timestamp, seconds: 3)
        let localMaxY = dataVM.calculateSafeMaxY(from: history)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                    Text("\(event.timestamp.toString(format: "HH:mm:ss")) 前後 3 秒震動強度走勢")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Button(action: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeInfoSheet = .eventRMSTrend
                        }
                    }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.primary(for: colorScheme).opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            if history.isEmpty {
                Text("無區間數據")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                let startDate = event.timestamp.addingTimeInterval(-3)
                let endDate = event.timestamp.addingTimeInterval(3)
                let safeTicks = generateSafeXAxisTicks(start: startDate, end: endDate, strideSeconds: 1.0)

                Chart {
                    ForEach(history) { point in
                        if point.isMotorActive {
                            RectangleMark(
                                xStart: .value("開始", point.timestamp),
                                xEnd: .value("結束", point.timestamp.addingTimeInterval(0.5)),
                                yStart: .value("底", 0.0),
                                yEnd: .value("頂", localMaxY)
                            )
                            .foregroundStyle(Color.orange.opacity(0.12))
                        }

                        if point.rmsValue.isFinite && !point.rmsValue.isNaN {
                            LineMark(
                                x: .value("時間", point.timestamp),
                                y: .value("強度", point.rmsValue)
                            )
                            .foregroundStyle(AppTheme.primary(for: colorScheme))
                            .lineStyle(StrokeStyle(lineWidth: 2.2))
                            .interpolationMethod(.linear)
                        }

                        if point.rmsValue >= 0.20 && point.rmsValue.isFinite {
                            let isCenterEvent = abs(point.timestamp.timeIntervalSince(event.timestamp)) < 0.35
                            PointMark(
                                x: .value("時間", point.timestamp),
                                y: .value("強度", point.rmsValue)
                            )
                            .foregroundStyle(isCenterEvent ? Color.red : Color.orange)
                            .symbolSize(isCenterEvent ? 85 : 35)
                        }
                    }
                }
                .chartYScale(domain: 0.0...localMaxY)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { val in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        if let doubleVal = val.as(Double.self) {
                            AxisValueLabel {
                                Text(String(format: "%.1f", doubleVal))
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            }
                        }
                    }
                }
                .chartYAxisLabel("震動強度 (deg/s)", position: .top)
                .chartXScale(domain: startDate...endDate)
                .chartXAxis {
                    AxisMarks(position: .bottom, values: safeTicks) { val in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                        
                        if let date = val.as(Date.self) {
                            AxisValueLabel(date.toString(format: "ss") + "s")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary(for: colorScheme))
                        }
                    }
                }
                .frame(height: 160)

                HStack(spacing: 14) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("發作核心點").font(.caption2).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                        Text("顯著震顫 (≥ 0.20)").font(.caption2).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.orange.opacity(0.3)).frame(width: 9, height: 9)
                        Text("馬達介入區間").font(.caption2).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 4, y: 2)
    }

    private func psdDetailChartView(psdData: [DataViewModel.PSDPoint]) -> some View {
        let isSignalReliable = event.rmsValue >= 0.20 && event.rmsValue.isFinite
        let validPowers = psdData.map(\.power).filter { $0.isFinite && !$0.isNaN }
        let maxPowerVal = validPowers.max() ?? 0.1
        let maxPowerDomain = max(0.1, maxPowerVal * 1.2)
        let maxPeak = isSignalReliable ? psdData.max(by: { $0.power < $1.power }) : nil

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.purple)
                    Text("\(event.timestamp.toString(format: "HH:mm:ss")) 的\n震動頻率分佈")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Button(action: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeInfoSheet = .eventPSD
                        }
                    }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 15))
                            .foregroundColor(.purple.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(String(format: "強度: %.2f deg/s", event.rmsValue.isFinite ? event.rmsValue : 0.0))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isSignalReliable ? .purple : AppTheme.textSecondary(for: colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isSignalReliable ? Color.purple.opacity(0.1) : AppTheme.textSecondary(for: colorScheme).opacity(0.1))
                    .cornerRadius(6)
            }

            Chart {
                RectangleMark(
                    xStart: .value("區段開始", 3.0),
                    xEnd: .value("區段結束", 7.0),
                    yStart: .value("底", 0.0),
                    yEnd: .value("頂", maxPowerDomain)
                )
                .foregroundStyle(Color.purple.opacity(0.08))

                ForEach(psdData) { psdPoint in
                    if psdPoint.frequencyHz.isFinite && psdPoint.power.isFinite {
                        BarMark(
                            x: .value("頻率", psdPoint.frequencyHz),
                            y: .value("PSD 能量", isSignalReliable ? psdPoint.power : 0),
                            width: .fixed(5)
                        )
                        .foregroundStyle(
                            (psdPoint.frequencyHz >= 3.0 && psdPoint.frequencyHz <= 7.0) ? Color.purple : AppTheme.textSecondary(for: colorScheme).opacity(0.25)
                        )
                    }
                }

                if let peak = maxPeak, peak.power > 0, peak.frequencyHz.isFinite {
                    RuleMark(x: .value("Peak", peak.frequencyHz))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(Color.red)
                        .annotation(position: .top, alignment: .center) {
                            Text(String(format: "主峰: %.1f Hz", peak.frequencyHz))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .cornerRadius(4)
                        }
                }
            }
            .chartYScale(domain: 0.0...maxPowerDomain)
            .chartXAxis {
                AxisMarks(values: [0, 3, 5, 7, 10, 15]) { val in
                    AxisGridLine()
                    AxisValueLabel {
                        Text("\(val.as(Int.self) ?? 0) Hz")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
            }
            .chartYAxisLabel("PSD 能量 ((deg/s)²/Hz)", position: .top)
            .frame(height: 160)

            HStack(spacing: 15) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.purple.opacity(0.3)).frame(width: 12, height: 12)
                    Text("3-7 Hz (典型震顫區)").font(.caption).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                if isSignalReliable {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                        Text("主要震動頻率").font(.caption).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
    }
}
