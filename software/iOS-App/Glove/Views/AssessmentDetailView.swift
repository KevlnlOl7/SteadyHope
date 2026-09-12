import SwiftUI

struct AssessmentDetailView: View {
    let record: DailyAssessmentResponseDTO
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    Text("評估總分")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                    HStack(alignment: .bottom, spacing: 4) {
                        Text("\(record.totalScore)")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                        
                        Text("/ \(record.parsedDetails.count * 4)")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .padding(.bottom, 6)
                    }
                    
                    Text("本次共填寫 \(record.parsedDetails.count) 題")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                    Divider()
                        .padding(.vertical, 4)

                    HStack(spacing: 20) {
                        scoreBadge(title: "情緒指標", score: record.moodScore)
                        scoreBadge(title: "日常生活", score: record.adlScore)
                        scoreBadge(title: "動作評估", score: record.motorScore)
                    }
                }
                .padding(20)
                .background(AppTheme.cardBackground(for: colorScheme))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 12) {
                    Text("詳細作答內容")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        .padding(.horizontal, 4)

                    if record.parsedDetails.isEmpty {
                        Text("無詳細作答題目資料")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(Array(record.parsedDetails.enumerated()), id: \.element.questionId) { index, detail in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(index + 1). \(detail.title)")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                                HStack {
                                    Text("選填結果：\(detail.selectedOptionTitle)")
                                        .font(.subheadline)
                                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                                    Spacer()

                                    Text("+\(detail.score) 分")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppTheme.primary(for: colorScheme))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(AppTheme.primary(for: colorScheme).opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                            .padding(14)
                            .background(AppTheme.cardBackground(for: colorScheme))
                            .cornerRadius(10)
                            .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                        Text("量表說明")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    }
                    Text("量表題目參考自台灣動作障礙學會。單一題目分數介於 0-4 分，分數越高代表該症狀對日常生活的影響越顯著。此總分紀錄為病患日常自我主觀評估，重點在於長期趨勢變化，供臨床醫師問診時參考。")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .lineSpacing(4)
                }
                .padding(16)
                .background(AppTheme.primary(for: colorScheme).opacity(0.08))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.primary(for: colorScheme).opacity(0.15), lineWidth: 1)
                )
            }
            .padding(16)
        }
        .background(AppTheme.background(for: colorScheme))
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
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            Text("\(score) 分")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
    }
}
