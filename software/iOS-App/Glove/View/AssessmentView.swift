import Foundation
import SwiftUI

struct AssessmentView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = AssessmentViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    dailyQuickSection
                    themeSelectionSection
                    weeklyFullSection
                }
                .padding(16)
            }
            .background(Color(red: 0.96, green: 0.96, blue: 0.97))
            .navigationTitle("症狀評估量表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        AssessmentHistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .imageScale(.medium)
                    }
                }
            }
            .alert("提交成功", isPresented: $viewModel.showSuccessAlert) {
                Button("確定") { dismiss() }
            } message: {
                Text("您的每日評估紀錄已成功儲存。")
            }
            .alert("提示", isPresented: $viewModel.showErrorAlert) {
                Button("確定", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "發生未知錯誤")
            }
        }
    }

    /// 每日快速檢測區塊，固定精選 5 題核心指標進行快篩
    private var dailyQuickSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.orange)
                Text("今日快速檢測")
                    .font(.headline)
            }

            NavigationLink {
                AssessmentFormView(
                    title: "今日狀態快篩",
                    questions: AssessmentBank.questions.filter {
                        [3, 10, 13, 16, 18].contains($0.id)
                    },
                    viewModel: viewModel
                )
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今日狀態 1 分鐘快篩")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                        Text("精選 5 題核心指標：情緒、吞嚥、穿衣、手部與步態")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .foregroundColor(.accentColor)
                }
                .padding(16)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
            }
        }
    }

    /// 主題自選填寫區塊，依據心情、日常與動作分類提供個別填答入口
    private var themeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("主題自選填寫")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(AssessmentSection.allCases) { sec in
                    NavigationLink {
                        AssessmentFormView(
                            title: "\(sec.rawValue) 評估",
                            questions: AssessmentBank.questions.filter {
                                $0.section == sec
                            },
                            viewModel: viewModel
                        )
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: sec.icon)
                                .font(.system(size: 18))
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundColor(.accentColor)
                                .clipShape(Circle())

                            Text(sec.rawValue)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    /// 定期深度評估區塊，提供完整 25 題綜合量表填寫入口
    private var weeklyFullSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("定期深度評估")
                .font(.headline)

            NavigationLink {
                AssessmentFormView(
                    title: "每週完整評估量表",
                    questions: AssessmentBank.questions,
                    viewModel: viewModel
                )
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("完整 25 題綜合量表")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                        Text("建議每週或回診前完整填寫一次")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("開始")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .cornerRadius(16)
                }
                .padding(14)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
            }
        }
    }
}

/// 評估問卷題目填寫子視圖，展示題目清單、單選選項與提交按鈕
private struct AssessmentFormView: View {
    /// 關閉表單畫面環境變數
    @Environment(\.dismiss) private var dismissForm

    /// 導覽列與表單頁面標題
    let title: String

    /// 當前表單包含的評估題目陣列
    let questions: [AssessmentQuestion]

    /// 共享之評估問卷檢視模型
    @ObservedObject var viewModel: AssessmentViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(Array(questions.enumerated()), id: \.element.id) { index, q in
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(index + 1). \(q.title)")
                            .font(.system(size: 16, weight: .bold))

                        Text(q.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        VStack(spacing: 8) {
                            ForEach(q.options) { opt in
                                let isSelected = viewModel.selectedAnswers[q.id]?.id == opt.id
                                Button {
                                    viewModel.selectedAnswers[q.id] = opt
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isSelected ? .accentColor : .gray)
                                            .font(.system(size: 18))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(opt.score) 分 - \(opt.title)")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.primary)
                                            Text(opt.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(
                                        isSelected
                                            ? Color.accentColor.opacity(0.08)
                                            : Color(uiColor: .secondarySystemBackground)
                                    )
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(12)
                }

                Button {
                    Task {
                        await viewModel.submitAssessment()
                    }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        let isAllAnswered = questions.allSatisfy {
                            viewModel.selectedAnswers[$0.id] != nil
                        }
                        Text(
                            isAllAnswered
                                ? "完成並送出"
                                : "還有題目未填寫 (\(questions.filter { viewModel.selectedAnswers[$0.id] != nil }.count)/\(questions.count))"
                        )
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                }
                .background(Color.accentColor)
                .cornerRadius(10)
                .disabled(viewModel.isSubmitting)
                .padding(.top, 10)

                Text("本表單填寫之資料將用於協助 AI 模型彙整與分析您的每日狀態，以提供更精確的評估追蹤與建議。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
            }
            .padding(16)
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.97))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.showSuccessAlert) {
            if viewModel.showSuccessAlert {
                dismissForm()
            }
        }
    }
}
