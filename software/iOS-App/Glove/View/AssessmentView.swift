import Foundation
import SwiftUI

struct AssessmentView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var loginVM: LoginViewModel
    
    @StateObject private var viewModel = AssessmentViewModel()

    /// 判斷當前使用者是否為照護者 (role == 1 或已綁定被照護者)
    private var isCaregiver: Bool {
        loginVM.userData?.role == 1 || loginVM.boundPartner != nil
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isCaregiver {
                    AssessmentHistoryView()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            dailyQuickSection
                            themeSelectionSection
                            weeklyFullSection
                            
                            aiNoticeCard
                            
                            Spacer()
                        }
                        .padding(16)
                    }
                    .background(Color(red: 0.96, green: 0.96, blue: 0.97))
                }
            }
            .navigationTitle(isCaregiver ? "評估歷史紀錄" : "症狀評估量表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isCaregiver {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink {
                            AssessmentHistoryView()
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .imageScale(.medium)
                        }
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
    
    private var aiNoticeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                
                Text("關於症狀評估量表的說明")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            Divider()
                .background(Color.blue.opacity(0.2))
            
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("智慧化數據分析：填寫的資料將由 AI 模型進行綜合彙整與趨勢追蹤，提供更精準的照護建議。")
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.blue)
                }
                
                Label {
                    Text("定期追蹤的價值：持續記錄有助於醫療團隊在您回診時，更全面地了解日常病況變化。")
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.blue)
                }
            }
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .lineSpacing(3)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.94, green: 0.97, blue: 1.0))
                .shadow(color: Color.blue.opacity(0.06), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.blue.opacity(0.15), lineWidth: 1)
        )
        .padding(.top, 12)
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
