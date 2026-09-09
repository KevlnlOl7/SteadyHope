import SwiftUI

struct AssessmentHistoryView: View {
    @StateObject private var viewModel = AssessmentViewModel()

    /// 歷史查詢模式列舉（單日與區間）
    enum QueryMode: String, CaseIterable, Identifiable {
        case singleDay = "單日"
        case dateRange = "區間"

        var id: String { rawValue }
    }

    /// 目前選取之查詢模式，預設為單日
    @State private var queryMode: QueryMode = .singleDay

    /// 單日查詢時所選取的目標日期
    @State private var selectedDate = Date()

    /// 區間查詢開始日期，預設為當前時刻七天前
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

    /// 區間查詢結束日期，預設為當前時刻
    @State private var endDate = Date()

    /// 目前選取以查看詳細作答內容之評估紀錄物件
    @State private var selectedRecord: DailyAssessmentResponseDTO?

    /// 控制是否導覽跳轉至評估詳情頁面
    @State private var showDetail = false

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
                singleDayQueryView
            } else {
                dateRangeQueryView
            }

            historyResultView
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.97).ignoresSafeArea())
        .navigationTitle("歷史填寫紀錄")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showDetail) {
            if let record = selectedRecord {
                AssessmentDetailView(record: record)
            }
        }
        .onChange(of: queryMode) { _, _ in
            viewModel.clearHistory()
        }
    }

    /// 單日查詢模式之月曆選取與送出按鈕視圖
    private var singleDayQueryView: some View {
        VStack(spacing: 16) {
            DatePicker(
                "選擇查詢日期",
                selection: $selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)

            Button {
                Task {
                    await viewModel.fetchHistory(for: selectedDate)
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoadingHistory {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text("查詢當日評估紀錄")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .cornerRadius(10)
            }
            .disabled(viewModel.isLoadingHistory)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        .padding(.horizontal, 16)
    }

    /// 區間查詢模式之起訖日期選擇器與送出按鈕視圖
    private var dateRangeQueryView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                DatePicker(
                    "開始日期",
                    selection: $startDate,
                    displayedComponents: [.date]
                )
                Divider()
                DatePicker(
                    "結束日期",
                    selection: $endDate,
                    in: startDate...,
                    displayedComponents: [.date]
                )
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
                .background(Color.accentColor)
                .cornerRadius(10)
            }
            .disabled(viewModel.isLoadingHistory)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        .padding(.horizontal, 16)
    }

    /// 查詢結果展示視圖，包含載入指示器、無資料提示以及歷史紀錄項目列表
    private var historyResultView: some View {
        Group {
            if viewModel.isLoadingHistory {
                VStack {
                    Spacer()
                    ProgressView("載入評估紀錄中...")
                        .padding()
                    Spacer()
                }
            } else if viewModel.historyRecords.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 42))
                        .foregroundColor(.secondary)
                    Text("尚無評估紀錄")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text(queryMode == .singleDay ? "此日期沒有評估紀錄" : "此日期區間沒有評估紀錄")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(viewModel.historyRecords, id: \.self) { record in
                        Button {
                            selectedRecord = record
                            showDetail = true
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("總分：\(record.totalScore) 分")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.primary)
                                    Text("情緒：\(record.moodScore) | 日常：\(record.adlScore) | 動作：\(record.motorScore)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
