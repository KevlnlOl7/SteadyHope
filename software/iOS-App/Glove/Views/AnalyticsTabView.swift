import Charts
import SwiftUI

/// 藥效波動與震動數據圖表分析
struct AnalyticsTabView: View {
    @ObservedObject var medVM: MedicationViewModel
    @ObservedObject var dataVM: DataViewModel

    /// 查詢目標日期
    var selectedDate: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 標題與分析用途說明
                VStack(alignment: .leading, spacing: 6) {
                    Text("藥效波動分析")
                        .font(.title2.bold())
                    Text("結合手套感測器紀錄之「即時震動強度 (RMS)」與「服藥時間」，評估藥效作用期與衰退期（OFF 時期）。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // 核心圖表呈現區塊
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("震動強度與用藥時間軸疊加")
                            .font(.headline)
                        Spacer()
                        legendBadge(color: .blue, title: "震動 RMS")
                        legendBadge(color: .purple, title: "服藥點")
                    }

                    let tremorPoints = displayTremorData

                    if tremorPoints.isEmpty && todayMedications.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 36))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("目前尚無震動或服藥數據")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    } else {
                        Chart {
                            // 震動強度折線與漸層面積
                            ForEach(tremorPoints) { point in
                                LineMark(
                                    x: .value("時間", point.timestamp),
                                    y: .value("強度", point.rmsValue)
                                )
                                .foregroundStyle(Color.blue)
                                .interpolationMethod(.monotone)

                                AreaMark(
                                    x: .value("時間", point.timestamp),
                                    y: .value("強度", point.rmsValue)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.25), Color.blue.opacity(0.0)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                if isShortDuration || tremorPoints.count < 30 {
                                    PointMark(
                                        x: .value("時間", point.timestamp),
                                        y: .value("強度", point.rmsValue)
                                    )
                                    .foregroundStyle(Color.blue)
                                    .symbolSize(25)
                                }
                            }

                            // 當日服藥時間標記垂直線
                            ForEach(todayMedications) { med in
                                RuleMark(
                                    x: .value("服藥時間", med.date)
                                )
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                                .foregroundStyle(Color.purple)
                                .annotation(position: .top, alignment: .center) {
                                    VStack(spacing: 2) {
                                        Image(systemName: med.medType == .patch ? "figure.stand" : "pill.fill")
                                            .font(.system(size: 9))
                                        Text(med.name)
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.12))
                                    .foregroundColor(.purple)
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                                    )
                                }
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: true))
                        .chartXScale(domain: xAxisDomain)
                        .chartXAxis {
                            if isShortDuration {
                                AxisMarks { value in
                                    AxisGridLine()
                                    if let date = value.as(Date.self) {
                                        AxisValueLabel("\(date.toString(format: "HH:mm:ss"))")
                                    }
                                }
                            } else {
                                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                                    AxisGridLine()
                                    if let date = value.as(Date.self) {
                                        AxisValueLabel("\(date.toString(format: "HH:mm"))")
                                    }
                                }
                            }
                        }
                        .frame(height: 220)
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
                .padding(.horizontal)

                // 臨床數據關聯摘要卡片
                VStack(alignment: .leading, spacing: 12) {
                    Text("數據關聯摘要")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.blue)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("藥效起效與衰退觀察")
                                .font(.subheadline.bold())
                            Text("可觀察服藥點 (紫色虛線) 之後，震動強度 (藍色曲線) 下降之時間差；若震動強度再度升高，即提示藥效衰退期 (Wearing-off)。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
    }

    /// 取得震動強度數據（優先過濾當日紀錄，若無資料則回傳完整歷史清單以避免畫面空白）
    private var displayTremorData: [DataViewModel.RMSTrendPoint] {
        let filtered = dataVM.rmsTrendHistory.filter {
            Calendar.current.isDate($0.timestamp, inSameDayAs: selectedDate)
        }
        return filtered.isEmpty ? dataVM.rmsTrendHistory : filtered
    }

    /// 篩選選取日期當天之服藥紀錄清單
    private var todayMedications: [MedicationRecord] {
        medVM.medicationList.filter {
            Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        }
    }

    /// 綜合震動數據與服藥紀錄之所有時間戳記清單
    private var allTimestamps: [Date] {
        let tremorTimes = displayTremorData.map { $0.timestamp }
        let medTimes = todayMedications.map { $0.date }
        return (tremorTimes + medTimes).sorted()
    }

    /// 判斷整體時間跨度（服藥時間與震動量測點）是否小於 1 小時
    private var isShortDuration: Bool {
        let times = allTimestamps
        guard let first = times.first, let last = times.last else { return false }
        return last.timeIntervalSince(first) < 3600
    }

    /// 動態推算圖表 X 軸之最佳顯示範圍區間
    private var xAxisDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? selectedDate

        let times = allTimestamps
        guard let first = times.first, let last = times.last else {
            return startOfDay...endOfDay
        }

        // 短時間跨度處理（加入邊緣緩衝以利細節觀察）
        if isShortDuration {
            let diff = last.timeIntervalSince(first)
            let buffer = max(diff * 0.25, 10.0)
            return first.addingTimeInterval(-buffer)...last.addingTimeInterval(buffer)
        }

        // 跨度較大時展示整日 24 小時時間軸
        return startOfDay...endOfDay
    }

    /// 圖表圖例標記元件
    /// - Parameters:
    ///   - color: 圖例指示顏色
    ///   - title: 圖例說明標題
    private func legendBadge(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
    }
}
