import SwiftUI

struct AssessmentDetailView: View {
    let record: DailyAssessmentResponseDTO

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Text("評估總分")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("\(record.totalScore)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.accentColor)

                    Divider()

                    HStack(spacing: 20) {
                        scoreBadge(title: "情緒指標", score: record.moodScore)
                        scoreBadge(title: "日常生活", score: record.adlScore)
                        scoreBadge(title: "動作評估", score: record.motorScore)
                    }
                }
                .padding(20)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 12) {
                    Text("詳細作答內容")
                        .font(.headline)
                        .padding(.horizontal, 4)

                    if record.parsedDetails.isEmpty {
                        Text("無詳細作答題目資料")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(Array(record.parsedDetails.enumerated()), id: \.element.questionId) { index, detail in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(index + 1). \(detail.title)")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.primary)

                                HStack {
                                    Text("選填結果：\(detail.selectedOptionTitle)")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Text("+\(detail.score) 分")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                            .padding(14)
                            .background(Color.white)
                            .cornerRadius(10)
                            .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.97))
        .navigationTitle("歷史紀錄詳情")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 各面向指標得分徽章元件
    /// - Parameters:
    ///   - title: 指標分類名稱
    ///   - score: 該指標所得分數
    /// - Returns: 分數展示視圖元件
    @ViewBuilder
    private func scoreBadge(title: String, score: Int) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(score) 分")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}
