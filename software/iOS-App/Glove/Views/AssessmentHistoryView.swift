import SwiftUI

struct AssessmentHistoryView: View {
    @StateObject private var viewModel = AssessmentViewModel()
    @Environment(\.colorScheme) private var colorScheme

    /// 歷史查詢模式列舉（單日與區間）
    enum QueryMode: String, CaseIterable, Identifiable {
        case singleDay = "單日"
        case dateRange = "區間"

        var id: String { rawValue }
    }

    /// 目前選取之查詢模式
    @State private var queryMode: QueryMode = .singleDay

    /// 單日查詢時所選取的目標日期
    @State private var selectedDate: Date? = nil
    /// 當前月曆瀏覽的月份基準日期
    @State private var currentMonth: Date = Date()
    /// 區間查詢開始日期
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    /// 區間查詢結束日期
    @State private var endDate = Date()

    /// 目前選取之評估紀錄物件
    @State private var selectedRecord: DailyAssessmentResponseDTO?
    /// 控制是否導覽跳轉至評估詳情頁面
    @State private var showDetail = false

    /// 月曆計算用之本機日曆實體
    private let calendar = Calendar.current
    /// 星期標題文字陣列
    private let daysOfWeek = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(spacing: 16) {
            Picker("查詢方式", selection: $queryMode) {
                Text("單日").tag(QueryMode.singleDay)
                Text("區間").tag(QueryMode.dateRange)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if queryMode == .singleDay {
                singleDayCalendarPickerView
            } else {
                dateRangeQueryView
            }

            historyResultView
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("歷史填寫紀錄")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showDetail) {
            if let record = selectedRecord {
                AssessmentDetailView(record: record, assessmentVM: viewModel)
            }
        }
        .onChange(of: queryMode) {
            viewModel.clearHistory()
            if queryMode == .singleDay, let date = selectedDate {
                Task { await viewModel.fetchHistory(for: date) }
            }
        }
        .task {
            await viewModel.fetchAvailableRecordDates()
            let todayStr = Date().toString(format: "yyyy-MM-dd")
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"

            if viewModel.availableDateStrings.contains(todayStr) {
                selectedDate = Date()
                await viewModel.fetchHistory(for: Date())
            } else if let latestStr = viewModel.availableDateStrings.sorted(by: >).first,
                      let latestDate = formatter.date(from: latestStr) {
                selectedDate = latestDate
                currentMonth = latestDate
                await viewModel.fetchHistory(for: latestDate)
            }
        }
    }

    /// 單日月曆選取視圖
    private var singleDayCalendarPickerView: some View {
        VStack(spacing: 12) {
            HStack {
                Text(monthYearString(from: currentMonth))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .padding(8)
                        .background(AppTheme.textSecondary(for: colorScheme).opacity(0.12))
                        .clipShape(Circle())
                }

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .padding(8)
                        .background(AppTheme.textSecondary(for: colorScheme).opacity(0.12))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 4)

            HStack {
                ForEach(daysOfWeek, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .frame(maxWidth: .infinity)
                }
            }

            let days = daysInCurrentMonthGrid()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(days, id: \.self) { date in
                    if let date = date {
                        let dateStr = date.toString(format: "yyyy-MM-dd")
                        let hasData = viewModel.availableDateStrings.contains(dateStr)
                        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false

                        Button {
                            guard hasData else { return }
                            selectedDate = date
                            Task {
                                await viewModel.fetchHistory(for: date)
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.system(size: 15, weight: isSelected ? .bold : .regular))
                                    .foregroundColor(
                                        isSelected
                                            ? .white
                                            : (hasData ? AppTheme.textPrimary(for: colorScheme) : AppTheme.textSecondary(for: colorScheme).opacity(0.3))
                                    )

                                Circle()
                                    .fill(
                                        isSelected
                                            ? Color.white
                                            : (hasData ? AppTheme.primary(for: colorScheme) : Color.clear)
                                    )
                                    .frame(width: 4, height: 4)
                            }
                            .frame(width: 36, height: 36)
                            .background(isSelected ? AppTheme.primary(for: colorScheme) : Color.clear)
                            .clipShape(Circle())
                        }
                        .disabled(!hasData)
                    } else {
                        Color.clear.frame(width: 36, height: 36)
                    }
                }
            }

            HStack(spacing: 6) {
                Circle().fill(AppTheme.primary(for: colorScheme)).frame(width: 6, height: 6)
                Text("有填寫紀錄之日期")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                Spacer()
            }
            .padding(.top, 4)
            .padding(.leading, 4)
        }
        .padding(14)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        .padding(.horizontal, 16)
    }

    /// 區間查詢模式視圖
    private var dateRangeQueryView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                DatePicker(
                    "開始日期",
                    selection: $startDate,
                    displayedComponents: [.date]
                )
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Divider()
                DatePicker(
                    "結束日期",
                    selection: $endDate,
                    in: startDate...,
                    displayedComponents: [.date]
                )
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }

            Button {
                Task {
                    await viewModel.fetchHistoryRange(from: startDate, to: endDate)
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoadingHistory {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text("查詢區間評估紀錄")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.primary(for: colorScheme))
                .cornerRadius(10)
            }
            .disabled(viewModel.isLoadingHistory)
        }
        .padding(16)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        .padding(.horizontal, 16)
    }

    /// 歷史清單結果視圖
    private var historyResultView: some View {
        Group {
            if viewModel.isLoadingHistory {
                VStack {
                    Spacer()
                    ProgressView("載入評估紀錄中...")
                        .padding()
                    Spacer()
                }
            } else if viewModel.groupedHistoryRecords.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 42))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    Text("尚無評估紀錄")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Text(queryMode == .singleDay ? "請點選有藍點標記的日期查看" : "此日期區間沒有評估紀錄")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    Spacer()
                }
            } else {
                List {
                    ForEach(viewModel.groupedHistoryRecords) { group in
                        Section(header: Text(group.dateText)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        ) {
                            ForEach(group.records, id: \.self) { record in
                                Button {
                                    selectedRecord = record
                                    showDetail = true
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("總分：\(record.totalScore) 分")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                            Text("情緒：\(record.moodScore) | 日常：\(record.adlScore) | 動作：\(record.motorScore)")
                                                .font(.subheadline)
                                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 依指定月數調整當前瀏覽月份
    /// - Parameter value: 增減的月份數值
    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    /// 將日期格式化為「年與月」之顯示文字
    /// - Parameter date: 欲轉換的日期物件
    /// - Returns: 格式化後的年文字串
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter.string(from: date)
    }

    /// 計算當前瀏覽月份之日期陣列，補齊前方星期對齊空白
    /// - Returns: 包含日期與留白 nil 之可選日期陣列
    private func daysInCurrentMonthGrid() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else {
            return []
        }

        let firstDayOfMonth = monthInterval.start
        let weekday = calendar.component(.weekday, from: firstDayOfMonth)
        let leadingSpaces = weekday - 1

        guard let daysRange = calendar.range(of: .day, in: .month, for: currentMonth) else {
            return []
        }

        var grid: [Date?] = Array(repeating: nil, count: leadingSpaces)

        for day in daysRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                grid.append(date)
            }
        }

        return grid
    }
}
