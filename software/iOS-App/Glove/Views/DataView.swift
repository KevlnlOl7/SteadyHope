import Charts
import PhotosUI
import SwiftUI
import UIKit

struct DataView: View {
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var dataVM: DataViewModel = DataViewModel.shared
    @ObservedObject var bleVM: BluetoothViewModel
    @Environment(\.colorScheme) private var colorScheme

    /// 模式切換與介面展示設定
    @AppStorage("isSimpleModeEnabled") private var isSimpleMode: Bool = false
    @State private var isChartCleared: Bool = false
    @State private var activeInfoSheet: InfoSheetType? = nil

    /// 多媒體選取與預覽狀態
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var previewImage: UIImage? = nil
    @State private var currentPageIndex: Int = 0

    /// 事件編輯與圖表彈窗控制
    @State private var showPSDForEventID: UUID? = nil
    @State private var editingEventID: UUID? = nil
    @State private var tempUserTag: String = ""
    @State private var tempSelectedImages: [UIImage] = []
    @FocusState private var isFieldFocused: Bool

    /// 事件儲存流程與錯誤提示狀態
    @State private var savingEventID: UUID? = nil
    @State private var showSaveErrorAlert: Bool = false
    @State private var saveErrorMessage: String = ""

    /// 歷史補填提醒機制與圖表跳轉控制
    @AppStorage("tremorReminderSnoozedUntil") private var tremorReminderSnoozedUntil: Double = 0
    @AppStorage("tremorReminderIgnoredBefore") private var tremorReminderIgnoredBefore: Double = 0
    @State private var showReminderOptions: Bool = false
    @State private var chartJumpTargetDate: Date? = nil

    /// 計算屬性：篩選條件與角色狀態判定
    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(dataVM.selectedFilterDate)
    }

    private var isCaregiver: Bool {
        loginVM.userData?.role == 1 || loginVM.boundPartner != nil
    }

    private var currentStatusText: String {
        if isCaregiver {
            return "照護者家屬"
        }

        if !bleVM.isConnected {
            return "裝置未連線"
        }

        return dataVM.statusText
    }

    /// 計算屬性：標準模式儀表板數值格式化文字
    private var standardFreqDisplayText: String {
        if isChartCleared { return "--" }

        if let point = dataVM.selectedPoint {
            if let event = dataVM.filteredEvents.first(where: { abs($0.timestamp.timeIntervalSince(point.timestamp)) <= 5.0 }) {
                return String(format: "%.1f Hz", event.dominantFrequency)
            }
            return "--"
        }

        if !isCaregiver && !bleVM.isConnected { return "--" }
        return dataVM.dominantFrequencyText
    }

    private var standardRMSDisplayText: String {
        if let selected = dataVM.selectedPoint {
            return String(format: "%.1f", max(0, selected.rmsValue))
        }
        if isChartCleared { return "0.0" }
        if !isCaregiver && !bleVM.isConnected { return "--" }

        let value = dataVM.currentRMS
        guard value.isFinite, !value.isNaN else { return "0.0" }
        return String(format: "%.1f", max(0, value))
    }

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()
                .onTapGesture {
                    isFieldFocused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerView
                        if reminderCandidateCount > 0 { pastUnlabeledAlertBanner }
                        filterAndModeControlBar

                        if isSimpleMode {
                            simpleDashboardCardsView
                            tremorEventsSectionView
                        } else {
                            dashboardCardsView
                            rmsTrendChartView(parentProxy: proxy)
                            tremorEventsSectionView
                        }
                    }
                    .padding(.bottom, 80)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .confirmationDialog("歷史紀錄提醒", isPresented: $showReminderOptions, titleVisibility: .visible) {
            Button("三天內不提醒") {
                tremorReminderSnoozedUntil = Date().addingTimeInterval(3 * 24 * 60 * 60).timeIntervalSince1970
            }
            Button("不再提醒這批紀錄") {
                tremorReminderIgnoredBefore = Date().timeIntervalSince1970
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你可以暫時關閉提醒，或讓目前已存在的舊紀錄不再重複提醒。之後新產生的未標記事件仍會正常提醒。")
        }
        .alert("儲存失敗", isPresented: $showSaveErrorAlert) {
            Button("確定", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
        .onChange(of: dataVM.selectedFilterDate) { _, _ in
            isChartCleared = false
            dataVM.selectedPoint = nil
            dataVM.expandedEventID = nil
        }
        .onAppear {
            dataVM.bindPipeline(bleVM.pipeline)
            Task { await dataVM.loadTremorHistory() }
        }
        .onDisappear {
            isFieldFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .fullScreenCover(
            item: Binding(
                get: { previewImage.map { ImagePreviewItem(image: $0) } },
                set: { previewImage = $0?.image }
            )
        ) { item in
            imagePreview(image: item.image) { previewImage = nil }.background(BackgroundClearView())
        }
        .fullScreenCover(item: $activeInfoSheet) { sheetType in
            DataInfoOverlayView(type: sheetType, activeInfoSheet: $activeInfoSheet).background(BackgroundClearView())
        }
    }

    /// 頂部狀態列視圖
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(titleText)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    if isCaregiver {
                        Text("受照護者")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.primary(for: colorScheme).opacity(0.12))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .cornerRadius(4)
                    }
                }
                .padding(.top, 5)

                HStack(spacing: 6) {
                    Circle().fill(statusColor(currentStatusText)).frame(width: 8, height: 8)
                    Text("狀態：\(currentStatusText)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var titleText: String {
        if isCaregiver { return "\(loginVM.partnerName) 的震動數據" }
        return "即時震動數據"
    }

    /// 歷史補填提醒橫幅與候選事件統計
    private var reminderCandidateCount: Int {
        let ignoredBefore = Date(timeIntervalSince1970: tremorReminderIgnoredBefore)
        let snoozed = Date().timeIntervalSince1970 < tremorReminderSnoozedUntil
        if snoozed { return 0 }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current

        return dataVM.tremorEvents.filter { event in
            !calendar.isDateInToday(event.timestamp) && event.timestamp > ignoredBefore && (event.userTag.isEmpty || event.userTag == "未標記")
        }.count
    }

    private var pastUnlabeledAlertBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppTheme.accent(for: colorScheme))
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 3) {
                Text("歷史紀錄待補填提醒")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Text("尚有 \(reminderCandidateCount) 筆震顫紀錄未填寫情境。補齊後可協助醫師掌握發作規律。")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button {
                let ignoredBefore = Date(timeIntervalSince1970: tremorReminderIgnoredBefore)
                var calendar = Calendar.current
                calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current

                let candidates = dataVM.tremorEvents.filter { event in
                    !calendar.isDateInToday(event.timestamp) && event.timestamp > ignoredBefore && (event.userTag.isEmpty || event.userTag == "未標記")
                }

                guard let earliestUnlabeled = candidates.min(by: { $0.timestamp < $1.timestamp }) else { return }

                withAnimation(.easeInOut) {
                    dataVM.selectedFilterDate = earliestUnlabeled.timestamp
                    chartJumpTargetDate = earliestUnlabeled.timestamp
                    dataVM.expandedEventID = earliestUnlabeled.id
                }
            } label: {
                Text("前往補填")
                    .font(.caption2.bold())
                    .foregroundColor(AppTheme.background(for: colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.accent(for: colorScheme))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button {
                showReminderOptions = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(AppTheme.accent(for: colorScheme).opacity(0.12))
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }

    /// 日期選擇器與檢視模式切換控制列
    private var filterAndModeControlBar: some View {
        HStack {
            HStack(spacing: 6) {
                DatePicker("", selection: $dataVM.selectedFilterDate, displayedComponents: .date)
                    .labelsHidden()
                    .transformEffect(.init(scaleX: 0.9, y: 0.9))

                if !isViewingToday {
                    Button {
                        withAnimation {
                            dataVM.selectedFilterDate = Date()
                            chartJumpTargetDate = Date()
                        }
                        dataVM.selectedPoint = nil
                        dataVM.expandedEventID = nil
                        isChartCleared = false
                    } label: {
                        Text("回到今天")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.primary(for: colorScheme).opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }

            Spacer()

            Toggle(isOn: $isSimpleMode.animation(.spring())) {
                HStack(spacing: 4) {
                    Image(systemName: isSimpleMode ? "eyeglasses" : "chart.xyaxis.line").font(.caption)
                    Text(isSimpleMode ? "簡易模式" : "標準模式").font(.caption).fontWeight(.bold)
                }
                .foregroundColor(isSimpleMode ? .green : AppTheme.textSecondary(for: colorScheme))
            }
            .toggleStyle(SwitchToggleStyle(tint: .green))
            .fixedSize()
        }
        .padding(.horizontal, 20)
    }

    /// 標準模式數據看板視圖
    private var dashboardCardsView: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("主要震動頻率").font(.caption).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    Spacer()
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        withAnimation(.easeInOut(duration: 0.2)) { activeInfoSheet = .frequency }
                    } label: {
                        Image(systemName: "questionmark.circle").font(.caption).foregroundColor(AppTheme.primary(for: colorScheme))
                    }
                }
                Text(standardFreqDisplayText)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("震動強度 (RMS)").font(.caption).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    Spacer()
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        withAnimation(.easeInOut(duration: 0.2)) { activeInfoSheet = .rms }
                    } label: {
                        Image(systemName: "questionmark.circle").font(.caption).foregroundColor(AppTheme.primary(for: colorScheme))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(standardRMSDisplayText)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor((!isCaregiver && !bleVM.isConnected) ? AppTheme.textSecondary(for: colorScheme) : AppTheme.textPrimary(for: colorScheme))
                    Text("deg/s").font(.caption).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()
        }
        .padding(.horizontal, 20)
    }

    /// 簡易模式數據看板視圖與文案狀態計算
    private var simpleDashboardCardsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Text("震顫節奏").font(.system(size: 15, weight: .semibold)).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Button {
                            activeInfoSheet = .frequency
                        } label: {
                            Image(systemName: "questionmark.circle.fill").font(.system(size: 17)).foregroundColor(AppTheme.primary(for: colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                    Text(!isCaregiver && !bleVM.isConnected ? "--" : dataVM.dominantFrequencyText)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.75)
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 112)
                .padding(.horizontal, 8)
                .background(AppTheme.cardBackground(for: colorScheme))
                .cornerRadius(16)
                .softCardShadow()

                VStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Text("抖動幅度").font(.system(size: 15, weight: .semibold)).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Button {
                            activeInfoSheet = .rms
                        } label: {
                            Image(systemName: "questionmark.circle.fill").font(.system(size: 17)).foregroundColor(AppTheme.primary(for: colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(!isCaregiver && !bleVM.isConnected ? "--" : String(format: "%.1f", max(0, dataVM.currentRMS)))
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .minimumScaleFactor(0.75)
                            .foregroundColor((!isCaregiver && !bleVM.isConnected) ? AppTheme.textSecondary(for: colorScheme) : (dataVM.currentRMS >= 0.20 ? .orange : AppTheme.textPrimary(for: colorScheme)))
                            .lineLimit(1)
                        Text("deg/s").font(.caption2).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 112)
                .padding(.horizontal, 8)
                .background(AppTheme.cardBackground(for: colorScheme))
                .cornerRadius(16)
                .softCardShadow()
            }

            HStack(spacing: 10) {
                Circle().fill(simpleStatusColor).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(simpleStatusTitle).font(.system(size: 16, weight: .bold)).foregroundColor(simpleStatusColor)
                    Text(simpleStatusDescription).font(.caption).foregroundColor(AppTheme.textSecondary(for: colorScheme)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(14)
            .softCardShadow()
        }
        .padding(.horizontal, 20)
    }

    private var simpleStatusTitle: String {
        if !isCaregiver && !bleVM.isConnected { return "目前沒有連線" }
        if dataVM.currentRMS >= 0.20 { return "有明顯震顫" }
        return "手部很穩定"
    }

    private var simpleStatusDescription: String {
        if !isCaregiver && !bleVM.isConnected { return "連接裝置後，才會繼續顯示即時震動。" }
        if dataVM.currentRMS >= 0.20 { return "系統目前偵測到比較明顯的手部震動。" }
        return "目前沒有偵測到明顯的手部震動。"
    }

    private var simpleStatusColor: Color {
        if !isCaregiver && !bleVM.isConnected { return AppTheme.textSecondary(for: colorScheme) }
        return dataVM.currentRMS >= 0.20 ? .orange : .green
    }

    /// 建構 RMS 走勢圖表容器視圖
    private func rmsTrendChartView(parentProxy: ScrollViewProxy) -> some View {
        RMSTrendChartViewContainer(
            history: dataVM.rmsTrendHistory,
            events: dataVM.filteredEvents,
            selectedDate: dataVM.selectedFilterDate,
            parentProxy: parentProxy,
            isViewingToday: isViewingToday,
            activeInfoSheet: $activeInfoSheet,
            selectedPoint: dataVM.selectedPoint,
            isChartCleared: $isChartCleared,
            jumpTargetDate: $chartJumpTargetDate,
            onPointSelected: { point in handleChartPointSelection(point, parentProxy: parentProxy) },
            onChartSelectionCleared: {
                dataVM.selectedPoint = nil
                dataVM.expandedEventID = nil
                isChartCleared = true
            },
            onReturnToNow: {
                withAnimation(.easeInOut) {
                    dataVM.selectedFilterDate = Date()
                    chartJumpTargetDate = Date()
                }
                dataVM.selectedPoint = nil
                dataVM.expandedEventID = nil
                isChartCleared = false
            }
        )
    }

    /// 處理圖表點擊選取與事件滾動連動
    private func handleChartPointSelection(_ point: DataViewModel.RMSTrendPoint, parentProxy: ScrollViewProxy) {
        dataVM.selectedPoint = point
        isChartCleared = false

        if let event = dataVM.filteredEvents.min(by: { abs($0.timestamp.timeIntervalSince(point.timestamp)) < abs($1.timestamp.timeIntervalSince(point.timestamp)) }),
          abs(event.timestamp.timeIntervalSince(point.timestamp)) <= 5.0 {
            dataVM.expandedEventID = event.id
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.25)) {
                    parentProxy.scrollTo(event.id, anchor: .center)
                }
            }
        }
    }

    /// 震顫事件分區視圖
    private var tremorEventsSectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.rectangle.portrait.fill").foregroundColor(AppTheme.primary(for: colorScheme))
                let targetPrefix = isCaregiver ? "\(loginVM.partnerName) 的" : ""
                let dateStr = isViewingToday ? "今日" : dataVM.selectedFilterDate.toString(format: "yyyy/MM/dd")
                Text("\(targetPrefix)\(dateStr)震顫紀錄 (\(dataVM.filteredEvents.count) 筆)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Spacer()
            }
            .padding(.horizontal, 20)

            if dataVM.filteredEvents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green.opacity(0.6))
                    Text(isViewingToday ? "今日尚無捕捉到顯著震顫事件" : "該日無顯著震顫事件紀錄")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(AppTheme.cardBackground(for: colorScheme))
                .cornerRadius(20)
                .softCardShadow()
                .padding(.horizontal, 20)
            } else {
                eventListView
            }
        }
    }

    /// 依小時分組呈現之事件垂直清單
    private var eventListView: some View {
        let groupedEvents = Dictionary(grouping: dataVM.filteredEvents) { $0.timestamp.toString(format: "HH:00") }
        let sortedHours = groupedEvents.keys.sorted { $0 > $1 }

        return LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(sortedHours, id: \.self) { hourHeader in
                VStack(alignment: .leading, spacing: 8) {
                    Text(hourHeader)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    ForEach(groupedEvents[hourHeader] ?? []) { event in
                        if let index = dataVM.tremorEvents.firstIndex(where: { $0.id == event.id }) {
                            TremorEventCardView(
                                event: $dataVM.tremorEvents[index],
                                dataVM: dataVM,
                                loginVM: loginVM,
                                isSimpleMode: isSimpleMode,
                                editingEventID: $editingEventID,
                                tempUserTag: $tempUserTag,
                                tempSelectedImages: $tempSelectedImages,
                                selectedMediaItems: $selectedMediaItems,
                                currentPageIndex: $currentPageIndex,
                                previewImage: $previewImage,
                                savingEventID: $savingEventID,
                                activeInfoSheet: $activeInfoSheet,
                                showSaveErrorAlert: $showSaveErrorAlert,
                                saveErrorMessage: $saveErrorMessage,
                                isFieldFocused: $isFieldFocused
                            )
                            .id(event.id)
                        }
                    }
                }
            }
        }
    }

    /// 圖片預覽彈窗視圖建構
    private func imagePreview(image: UIImage, onClose: @escaping () -> Void) -> some View {
        ImagePreview(image: image, onClose: onClose)
    }

    /// 依狀態文字對應指示燈色彩
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "照護者家屬": return AppTheme.primary(for: colorScheme)
        case "資料正常": return .green
        case "資料累積中": return .orange
        case "裝置未連線", "未連線": return AppTheme.textSecondary(for: colorScheme)
        default: return .red
        }
    }
}

/// RMS 走勢圖表封裝容器視圖，提供手勢縮放、拖曳平移、時間選取與事件標記渲染機制
private struct RMSTrendChartViewContainer: View {
    /// 外部傳入之數據源與代理器
    let history: [DataViewModel.RMSTrendPoint]
    let events: [TremorEvent]
    let selectedDate: Date
    let parentProxy: ScrollViewProxy
    let isViewingToday: Bool
    let activeInfoSheet: Binding<InfoSheetType?>
    let selectedPoint: DataViewModel.RMSTrendPoint?
    @Binding var isChartCleared: Bool
    let jumpTargetDate: Binding<Date?>
    let onPointSelected: (DataViewModel.RMSTrendPoint) -> Void
    let onChartSelectionCleared: () -> Void
    let onReturnToNow: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// 圖表可視範圍、滾動位置與縮放拖曳狀態
    @State private var visibleDuration: TimeInterval = 60
    @State private var zoomBaseDuration: TimeInterval = 60
    @State private var chartScrollPosition: Date = Date()
    @State private var hasInitializedScrollPosition: Bool = false
    @State private var zoomAnchorDate: Date = Date()
    @State private var isPinching: Bool = false
    @State private var dragStartScrollPosition: Date? = nil

    /// 圖表時間選取器彈窗與選取狀態
    @State private var showTimePicker: Bool = false
    @State private var selectedChartTime: Date = Date()
    @State private var hasSelectedSpecificTime: Bool = false

    /// 圖表手勢點選命中與選取狀態
    @State private var chartSelectedDate: Date? = nil
    @State private var chartTappedPointID: UUID? = nil
    @State private var chartTappedPointTimestamp: Date? = nil
    @State private var lastTappedDate: Date? = nil

    /// 圖表尺寸與時間範圍常數
    private let minimumVisibleDuration: TimeInterval = 3
    private let maximumVisibleDuration: TimeInterval = 24 * 60 * 60
    private let chartHeight: CGFloat = 285

    /// 時區與邊界時間計算屬性
    private var taipeiCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return calendar
    }

    private var dayStart: Date {
        taipeiCalendar.startOfDay(for: selectedDate)
    }

    private var dayEnd: Date {
        let tomorrow = taipeiCalendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(24 * 60 * 60)

        if isViewingToday {
            return min(tomorrow, Date())
        }

        return tomorrow
    }

    private var dayLastSecond: Date {
        if isViewingToday {
            return Date()
        }
        return dayEnd.addingTimeInterval(-1)
    }

    /// 可視範圍與左右滾動邊界計算屬性
    private var clampedVisibleDuration: TimeInterval {
        min(max(visibleDuration, minimumVisibleDuration), maximumVisibleDuration)
    }

    private var maxLeadingDate: Date {
        max(dayStart, dayEnd.addingTimeInterval(-clampedVisibleDuration))
    }

    private var clampedChartScrollPosition: Date {
        min(max(chartScrollPosition, dayStart), maxLeadingDate)
    }

    private var visibleEndDate: Date {
        let calculatedEnd = clampedChartScrollPosition.addingTimeInterval(clampedVisibleDuration)
        return min(calculatedEnd, dayEnd)
    }

    /// 圖表可視與緩衝數據集合
    private var visibleHistory: [DataViewModel.RMSTrendPoint] {
        history.filter {
            $0.timestamp >= clampedChartScrollPosition && $0.timestamp <= visibleEndDate
        }
    }

    private var bufferedHistory: [DataViewModel.RMSTrendPoint] {
        let buffer = max(clampedVisibleDuration * 1.5, 5)
        let start = clampedChartScrollPosition.addingTimeInterval(-buffer)
        let end = visibleEndDate.addingTimeInterval(buffer)

        return history.filter {
            $0.timestamp >= start && $0.timestamp <= end
        }
    }

    private var bufferedEvents: [TremorEvent] {
        let buffer = max(clampedVisibleDuration * 1.5, 5)
        let start = clampedChartScrollPosition.addingTimeInterval(-buffer)
        let end = visibleEndDate.addingTimeInterval(buffer)

        return events.filter {
            $0.timestamp >= start && $0.timestamp <= end
        }
    }

    /// 圖表座標軸動態刻度與標籤計算屬性
    private var dynamicMaxY: Double {
        let values = bufferedHistory
            .map(\.rmsValue)
            .filter { $0.isFinite && !$0.isNaN }

        guard let maximum = values.max() else {
            return 0.5
        }

        return max(0.5, maximum * 1.15)
    }

    private var xAxisStride: TimeInterval {
        switch clampedVisibleDuration {
        case ...6: return 1
        case ...15: return 2
        case ...30: return 5
        case ...60: return 10
        case ...120: return 20
        case ...300: return 60
        case ...600: return 120
        case ...1800: return 300
        case ...3600: return 600
        case ...7200: return 1200
        case ...21600: return 3600
        case ...43200: return 7200
        default: return 14400
        }
    }

    private var visibleXAxisTicks: [Date] {
        let step = xAxisStride
        let startInterval = clampedChartScrollPosition.timeIntervalSince1970
        let endInterval = visibleEndDate.timeIntervalSince1970

        let bufferedStart = max(dayStart.timeIntervalSince1970, startInterval - step)
        let bufferedEnd = min(dayEnd.timeIntervalSince1970, endInterval + step)
        let alignedStart = floor(bufferedStart / step) * step

        var current = alignedStart
        var ticks: [Date] = []

        while current <= bufferedEnd {
            let date = Date(timeIntervalSince1970: current)
            if date >= dayStart && date <= dayEnd {
                ticks.append(date)
            }
            current += step
        }

        return ticks
    }

    private func xAxisLabel(for date: Date) -> String {
        switch clampedVisibleDuration {
        case ...120:
            return "\(taipeiCalendar.component(.second, from: date))s"
        case ...3600:
            return "\(taipeiCalendar.component(.minute, from: date))m"
        default:
            return "\(taipeiCalendar.component(.hour, from: date))h"
        }
    }

    /// 標題時間與即時狀態追蹤判定屬性
    private var visibleHeaderTime: Date {
        let center = clampedChartScrollPosition.addingTimeInterval(clampedVisibleDuration * 0.5)
        return min(max(center, dayStart), dayLastSecond)
    }

    private var isAtCurrentTime: Bool {
        guard isViewingToday else { return false }
        let now = Date()
        return visibleEndDate >= now.addingTimeInterval(-2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chartHeaderView

            if history.isEmpty {
                emptyChartView
            } else {
                HStack {
                    Spacer()
                    Text("deg/s")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .padding(.trailing, 2)
                }
                .padding(.bottom, -2)

                mainChartArea
                chartFooterLegendView
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(20)
        .softCardShadow()
        .padding(.horizontal, 20)
        .sheet(isPresented: $showTimePicker) {
            NavigationStack {
                VStack(spacing: 20) {
                    Text("選擇圖表時間")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    DatePicker(
                        "時間",
                        selection: $selectedChartTime,
                        in: dayStart...dayLastSecond,
                        displayedComponents: [.hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()

                    Text(selectedChartTime.toString(format: "yyyy/MM/dd HH:mm"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.primary(for: colorScheme))

                    if isViewingToday {
                        Button {
                            hasSelectedSpecificTime = false
                            selectedChartTime = Date()
                            clearChartSelection()
                            isChartCleared = false
                            onReturnToNow()
                            showTimePicker = false

                            DispatchQueue.main.async {
                                moveToDate(Date(), animated: false)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                Text("回到現在")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(AppTheme.primary(for: colorScheme).opacity(0.10))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }

                    Spacer()
                }
                .padding()
                .background(AppTheme.background(for: colorScheme))
                .navigationTitle("查看時間")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            showTimePicker = false
                        }
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("前往") {
                            hasSelectedSpecificTime = true
                            clearChartSelection()

                            let safeTime = min(max(selectedChartTime, dayStart), dayLastSecond)
                            selectedChartTime = safeTime
                            moveToDate(safeTime, animated: true)
                            showTimePicker = false
                        }
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            initializeScrollPositionIfNeeded()
        }
        .onChange(of: selectedDate) { _, _ in
            hasInitializedScrollPosition = false
            hasSelectedSpecificTime = false
            chartSelectedDate = nil
            clearChartSelection()
            initializeScrollPositionIfNeeded()
        }
        .onChange(of: history.last?.timestamp) { _, _ in
            guard isViewingToday else { return }
            guard !hasSelectedSpecificTime else { return }

            moveToDate(Date(), animated: false)
        }
        .onChange(of: jumpTargetDate.wrappedValue) { _, newDate in
            guard let newDate else { return }

            clearChartSelection()
            moveToDate(newDate, animated: true)

            DispatchQueue.main.async {
                jumpTargetDate.wrappedValue = nil
            }
        }
    }

    /// 圖表本體與手勢互動區塊視圖
    @ViewBuilder
    private var mainChartArea: some View {
        let currentMaxY = self.dynamicMaxY
        let safeXAxisTicks = self.visibleXAxisTicks

        GeometryReader { geometry in
            Chart {
                ForEach(bufferedHistory) { point in
                    if point.isMotorActive {
                        RectangleMark(
                            xStart: .value("開始", point.timestamp),
                            xEnd: .value("結束", point.timestamp.addingTimeInterval(0.5)),
                            yStart: .value("底", 0.0),
                            yEnd: .value("頂", currentMaxY)
                        )
                        .foregroundStyle(Color.orange.opacity(0.10))
                    }

                    if point.rmsValue.isFinite && !point.rmsValue.isNaN {
                        LineMark(
                            x: .value("時間", point.timestamp),
                            y: .value("強度", max(0, point.rmsValue))
                        )
                        .foregroundStyle(AppTheme.primary(for: colorScheme))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.linear)
                    }

                    if isTappedPoint(point) {
                        PointMark(
                            x: .value("時間", point.timestamp),
                            y: .value("強度", max(0, point.rmsValue))
                        )
                        .foregroundStyle(Color.red)
                        .symbolSize(100)
                    }
                }

                ForEach(bufferedEvents) { event in
                    PointMark(
                        x: .value("事件時間", event.timestamp),
                        y: .value("事件強度", max(0, event.rmsValue))
                    )
                    .foregroundStyle(isEventCorrespondingToTappedPoint(event) ? Color.red : Color.orange)
                    .symbolSize(isEventCorrespondingToTappedPoint(event) ? 100 : 34)
                }
            }
            .chartXScale(domain: clampedChartScrollPosition...visibleEndDate)
            .chartYScale(domain: 0.0...currentMaxY)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.gray.opacity(0.3))

                    if let doubleVal = value.as(Double.self) {
                        AxisValueLabel {
                            Text(String(format: "%.1f", doubleVal))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom, values: safeXAxisTicks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.gray.opacity(0.3))

                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(xAxisLabel(for: date))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary(for: colorScheme))
                                .padding(.top, 4)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .chartGesture { proxy in
                SpatialTapGesture()
                    .onEnded { tapValue in
                        let location = tapValue.location
                        guard let date = proxy.value(atX: location.x, as: Date.self),
                              let value = proxy.value(atY: location.y, as: Double.self)
                        else { return }

                        handleChartTap(at: date, yValue: value)
                    }
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if !isPinching {
                            isPinching = true
                            zoomAnchorDate = visibleHeaderTime
                        }

                        let magnification = max(value.magnification, 0.05)
                        let newDuration = min(max(zoomBaseDuration / magnification, minimumVisibleDuration), maximumVisibleDuration)
                        visibleDuration = newDuration

                        let maxLeading = max(dayStart, dayEnd.addingTimeInterval(-newDuration))
                        let newLeading = zoomAnchorDate.addingTimeInterval(-newDuration * 0.5)

                        chartScrollPosition = min(max(newLeading, dayStart), maxLeading)
                    }
                    .onEnded { _ in
                        zoomBaseDuration = clampedVisibleDuration
                        isPinching = false
                        keepScrollPositionInsideDay()
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard !isPinching else { return }

                        let width = max(geometry.size.width, 1)
                        let secondsPerPoint = clampedVisibleDuration / width

                        if dragStartScrollPosition == nil {
                            dragStartScrollPosition = chartScrollPosition
                        }

                        guard let startPosition = dragStartScrollPosition else { return }

                        let deltaSeconds = Double(value.translation.width) * secondsPerPoint
                        let proposedLeading = startPosition.addingTimeInterval(-deltaSeconds)
                        let maxLeading = max(dayStart, dayEnd.addingTimeInterval(-clampedVisibleDuration))

                        chartScrollPosition = min(max(proposedLeading, dayStart), maxLeading)
                    }
                    .onEnded { _ in
                        dragStartScrollPosition = nil
                    }
            )
        }
        .frame(height: chartHeight)
    }

    /// 圖表頂部標題列視圖
    private var chartHeaderView: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                Text("\(visibleHeaderTime.toString(format: "HH:mm")) 震動強度走勢")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Button {
                    activeInfoSheet.wrappedValue = .chart
                } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.primary(for: colorScheme).opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            Button {
                selectedChartTime = min(max(visibleHeaderTime, dayStart), dayLastSecond)
                showTimePicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("選擇時間")
                }
                .font(.caption2.weight(.bold))
                .foregroundColor(AppTheme.primary(for: colorScheme))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppTheme.primary(for: colorScheme).opacity(0.10))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }

    /// 圖表無數據佔位視圖
    private var emptyChartView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 30))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))

            Text("\(selectedDate.toString(format: "MM/dd")) 尚無連續走勢資料")
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Text("選擇時間後，可查看該時段的震動資料")
                .font(.caption2)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity, minHeight: chartHeight)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(15)
    }

    /// 滾動位置初始化處理
    private func initializeScrollPositionIfNeeded() {
        guard !hasInitializedScrollPosition else { return }
        hasInitializedScrollPosition = true

        if let jumpDate = jumpTargetDate.wrappedValue {
            moveToDate(jumpDate, animated: false)
            DispatchQueue.main.async {
                jumpTargetDate.wrappedValue = nil
            }
        } else if isViewingToday {
            moveToDate(Date(), animated: false)
        } else if let latest = history.last?.timestamp {
            moveToDate(latest, animated: false)
        } else {
            moveToDate(dayStart, animated: false)
        }
    }

    /// 移動圖表可視範圍至指定時間
    private func moveToDate(_ target: Date, animated: Bool) {
        let safeTarget = min(max(target, dayStart), dayEnd)
        let maxLeading = max(dayStart, dayEnd.addingTimeInterval(-clampedVisibleDuration))

        let isTargetNow = isViewingToday && safeTarget >= Date().addingTimeInterval(-10)
        let multiplier: TimeInterval = isTargetNow ? 1.0 : 0.5
        let leading = safeTarget.addingTimeInterval(-clampedVisibleDuration * multiplier)
        let clampedLeading = min(max(leading, dayStart), maxLeading)

        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                chartScrollPosition = clampedLeading
            }
        } else {
            chartScrollPosition = clampedLeading
        }
    }

    /// 限制圖表滾動範圍於指定日期區間內
    private func keepScrollPositionInsideDay() {
        let maxLeading = max(dayStart, dayEnd.addingTimeInterval(-clampedVisibleDuration))
        chartScrollPosition = min(max(chartScrollPosition, dayStart), maxLeading)
    }

    /// 清空圖表點選選取標記
    private func clearChartSelection() {
        chartTappedPointID = nil
        chartTappedPointTimestamp = nil
        lastTappedDate = nil
        chartSelectedDate = nil
    }

    /// 處理圖表點擊選取與最近鄰點匹配演算法
    private func handleChartTap(at tappedDate: Date, yValue: Double) {
        lastTappedDate = tappedDate
        let maxY = dynamicMaxY
        let xTolerance = dynamicHitTolerance
        let yTolerance = max(maxY * 0.20, 15.0)

        let significantPoints = bufferedHistory
            .filter {
                $0.rmsValue.isFinite &&
                !$0.rmsValue.isNaN &&
                $0.rmsValue >= 0.20 &&
                abs($0.rmsValue - yValue) <= yTolerance
            }
            .sorted {
                abs($0.timestamp.timeIntervalSince(tappedDate)) < abs($1.timestamp.timeIntervalSince(tappedDate))
            }

        let validEvents = bufferedEvents
            .filter {
                let clampedRMS = max(0, min($0.rmsValue, maxY))
                return abs(clampedRMS - yValue) <= yTolerance
            }
            .sorted {
                abs($0.timestamp.timeIntervalSince(tappedDate)) < abs($1.timestamp.timeIntervalSince(tappedDate))
            }

        let nearestPoint = significantPoints.first
        let nearestEvent = validEvents.first

        let pointDistance = nearestPoint.map { abs($0.timestamp.timeIntervalSince(tappedDate)) } ?? .greatestFiniteMagnitude
        let eventDistance = nearestEvent.map { abs($0.timestamp.timeIntervalSince(tappedDate)) } ?? .greatestFiniteMagnitude

        if let point = nearestPoint,
           pointDistance <= xTolerance,
           pointDistance <= eventDistance {
            chartTappedPointID = point.id
            chartTappedPointTimestamp = point.timestamp
            chartSelectedDate = point.timestamp
            onPointSelected(point)
            return
        }

        if let event = nearestEvent,
           eventDistance <= xTolerance {
            if let point = significantPoints.min(by: {
                abs($0.timestamp.timeIntervalSince(event.timestamp)) < abs($1.timestamp.timeIntervalSince(event.timestamp))
            }) {
                chartTappedPointID = point.id
                chartTappedPointTimestamp = point.timestamp
                chartSelectedDate = point.timestamp
                onPointSelected(point)
            }
            return
        }

        let fallbackTolerance = min(xTolerance * 1.5, 15.0)
        if let point = significantPoints.first,
           abs(point.timestamp.timeIntervalSince(tappedDate)) <= fallbackTolerance {
            chartTappedPointID = point.id
            chartTappedPointTimestamp = point.timestamp
            chartSelectedDate = point.timestamp
            onPointSelected(point)
            return
        }

        clearChartSelection()
        onChartSelectionCleared()
    }

    /// 依可視時間跨度動態計算之點選容許誤差
    private var dynamicHitTolerance: TimeInterval {
        switch clampedVisibleDuration {
        case ...10: return 1.0
        case ...30: return 3.0
        case ...60: return 5.0
        case ...120: return 8.0
        case ...300: return 12.0
        case ...600: return 20.0
        case ...1800: return 30.0
        case ...3600: return 60.0
        case ...21600: return 120.0
        default: return 180.0
        }
    }

    /// 判斷數據點是否為當前選取點
    private func isTappedPoint(_ point: DataViewModel.RMSTrendPoint) -> Bool {
        guard let chartTappedPointID else { return false }
        return point.id == chartTappedPointID
    }

    /// 判斷事件是否與當前選取點之時間相符
    private func isEventCorrespondingToTappedPoint(_ event: TremorEvent) -> Bool {
        guard let tappedTimestamp = chartTappedPointTimestamp else { return false }
        return abs(tappedTimestamp.timeIntervalSince(event.timestamp)) <= 0.5
    }

    /// 圖表底部圖例說明視圖
    private var chartFooterLegendView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                    Text("顯著震顫(點擊跳轉至下方事件)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange.opacity(0.3))
                        .frame(width: 9, height: 9)
                    Text("馬達啟動區間")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                    Text("目前選取")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }
        }
    }
}
