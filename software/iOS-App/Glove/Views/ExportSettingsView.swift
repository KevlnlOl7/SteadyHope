import SwiftUI

struct ExportSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: ExportSettingsViewModel

    init(
        loginVM: LoginViewModel,
        medVM: MedicationViewModel,
        dataVM: DataViewModel,
        symptomVM: SymptomViewModel,
        vitalsVM: HealthVitalsViewModel
    ) {
        _viewModel = StateObject(
            wrappedValue: ExportSettingsViewModel(
                loginVM: loginVM,
                medVM: medVM,
                dataVM: dataVM,
                symptomVM: symptomVM,
                vitalsVM: vitalsVM
            )
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if viewModel.currentStep == 1 {
                    stepOneCards
                } else {
                    stepTwoCards
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle("匯出健康報告")
        .sheet(isPresented: $viewModel.showPreviewSheet) {
            if let pdfData = viewModel.generatedPDFData {
                let dateStr = viewModel.startDate.toString(format: "yyyyMMdd")
                PDFPreviewView(
                    pdfData: pdfData,
                    fileName: "帕金森追蹤報告_\(dateStr)"
                )
            }
        }
        .alert("提示", isPresented: $viewModel.showErrorAlert) {
            Button("確定", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    @ViewBuilder
    private var stepOneCards: some View {
        // 日期區間選取卡片
        VStack(alignment: .leading, spacing: 6) {
            Text("請選擇欲匯出的醫療報告期間")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                DatePicker(
                    "開始日期",
                    selection: $viewModel.startDate,
                    in: ...viewModel.endDate,
                    displayedComponents: [.date]
                )
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .environment(\.locale, Locale(identifier: "zh_TW"))
                .padding(.vertical, 12)

                Divider()

                DatePicker(
                    "結束日期",
                    selection: $viewModel.endDate,
                    in: viewModel.startDate...Date(),
                    displayedComponents: [.date]
                )
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                .environment(\.locale, Locale(identifier: "zh_TW"))
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()
        }

        // 報告項目勾選卡片
        VStack(alignment: .leading, spacing: 6) {
            Text("請勾選欲由 AI 整理的報告項目（可複選）")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(viewModel.reportTypeOptions.enumerated()), id: \.element) { index, type in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type)
                                .font(.body)
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                            if type == "看病前準備" {
                                Text("僅供首頁看診提示使用，不會匯入 PDF")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                        Spacer()
                        Image(
                            systemName: viewModel.selectedReportTypes.contains(type)
                                ? "checkmark.square.fill" : "square"
                        )
                        .font(.title3)
                        .foregroundColor(
                            viewModel.selectedReportTypes.contains(type)
                                ? AppTheme.primary(for: colorScheme) : AppTheme.textSecondary(for: colorScheme).opacity(0.4)
                        )
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if viewModel.selectedReportTypes.contains(type) {
                            viewModel.selectedReportTypes.remove(type)
                        } else {
                            viewModel.selectedReportTypes.insert(type)
                        }
                    }

                    if index < viewModel.reportTypeOptions.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()
        }

        // 自訂報告項目卡片
        VStack(alignment: .leading, spacing: 6) {
            Text("自訂報告項目（自由新增）")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach($viewModel.customReportFields) { $field in
                    HStack {
                        TextField("輸入項目名稱（例如：復健狀況）", text: $field.title)
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        Button(role: .destructive) {
                            if let idx = viewModel.customReportFields.firstIndex(where: { $0.id == field.id }) {
                                viewModel.customReportFields.remove(at: idx)
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 10)
                    Divider()
                }

                Button {
                    withAnimation {
                        viewModel.addCustomReportField()
                    }
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("新增自訂項目")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()
        }

        // 下一步按鈕
        Button {
            withAnimation(.spring()) {
                viewModel.currentStep = 2
            }
        } label: {
            HStack {
                Spacer()
                Text("下一步：勾選觀察項目")
                    .font(.headline)
                Image(systemName: "arrow.right.circle.fill")
                Spacer()
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                !viewModel.hasValidSelection ? AppTheme.textSecondary(for: colorScheme).opacity(0.4) : AppTheme.primary(for: colorScheme)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(
                color: viewModel.hasValidSelection ? AppTheme.primary(for: colorScheme).opacity(0.25) : Color.clear,
                radius: 8,
                y: 4
            )
        }
        .disabled(!viewModel.hasValidSelection)

        // 直接預覽 PDF 按鈕
        Button {
            Task {
                await viewModel.preparePDFForPreviewAsync()
            }
        } label: {
            HStack {
                Spacer()
                if viewModel.isGeneratingPDF {
                    ProgressView().padding(.trailing, 8)
                } else {
                    Image(systemName: "doc.richtext.fill")
                }
                Text(viewModel.isGeneratingPDF ? "正在繪製 PDF..." : "無需 AI 彙整預覽 PDF 報告內容")
                    .font(.headline)
                Spacer()
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                (viewModel.isGeneratingPDF || viewModel.hasValidSelection)
                    ? AppTheme.textSecondary(for: colorScheme).opacity(0.4) : AppTheme.primary(for: colorScheme)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(viewModel.isGeneratingPDF || viewModel.hasValidSelection)
    }

    @ViewBuilder
    private var stepTwoCards: some View {
        // 返回第一步按鈕
        Button {
            withAnimation(.spring()) {
                viewModel.currentStep = 1
            }
        } label: {
            HStack {
                Image(systemName: "chevron.left")
                Text("返回重選欄位種類")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundColor(AppTheme.primary(for: colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)

        // 健康觀察主題勾選卡片
        VStack(alignment: .leading, spacing: 6) {
            Text("請勾選 AI 需深入分析的健康主題（可複選）")
                .font(.caption.bold())
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.includeMoodNotes.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(
                                systemName: viewModel.includeMoodNotes
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(
                                viewModel.includeMoodNotes ? AppTheme.primary(for: colorScheme) : AppTheme.textSecondary(for: colorScheme)
                            )
                            Text("引用心情留言板")
                                .font(.subheadline)
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    let allTitlesCount = viewModel.categoryOptions.count
                    let isAllSelected = viewModel.selectedCategories.count == allTitlesCount

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            let allTitles = Set(viewModel.categoryOptions.map { $0.title })
                            if isAllSelected {
                                viewModel.selectedCategories.removeAll()
                            } else {
                                viewModel.selectedCategories = allTitles
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(
                                systemName: isAllSelected
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(isAllSelected ? AppTheme.primary(for: colorScheme) : AppTheme.textSecondary(for: colorScheme))
                            Text("全選主題")
                                .font(.subheadline)
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)

                Divider()

                ForEach(Array(viewModel.categoryOptions.enumerated()), id: \.element.title) { index, item in
                    let isSelected = viewModel.selectedCategories.contains(item.title)
                    let isExpanded = viewModel.expandedCategories.contains(item.title)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 16))
                                .foregroundColor(isSelected ? AppTheme.primary(for: colorScheme) : AppTheme.textSecondary(for: colorScheme))
                                .frame(width: 24, height: 24)

                            Text(item.title)
                                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            Spacer()

                            HStack(spacing: 2) {
                                Text(isExpanded ? "收起" : "說明")
                                    .font(.caption2.bold())
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.textSecondary(for: colorScheme).opacity(0.12))
                            .cornerRadius(12)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .onTapGesture {
                                if isExpanded {
                                    viewModel.expandedCategories.remove(item.title)
                                } else {
                                    viewModel.expandedCategories.insert(item.title)
                                }
                            }

                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(
                                    isSelected ? AppTheme.primary(for: colorScheme) : AppTheme.textSecondary(for: colorScheme).opacity(0.3)
                                )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelected {
                                viewModel.selectedCategories.remove(item.title)
                            } else {
                                viewModel.selectedCategories.insert(item.title)
                            }
                        }

                        if isExpanded {
                            Text(item.description)
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .lineSpacing(2)
                                .padding(.leading, 36)
                        }

                        if item.title == "其他（自由補充）" && isSelected {
                            TextField("請輸入其他狀況說明...", text: $viewModel.customCategoryText, axis: .vertical)
                                .lineLimit(2...5)
                                .padding(10)
                                .background(AppTheme.background(for: colorScheme))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(AppTheme.textSecondary(for: colorScheme).opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.vertical, 12)

                    if index < viewModel.categoryOptions.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()
        }

        // 產生摘要按鈕
        Button {
            Task {
                await viewModel.requestAISummaryAsync()
            }
        } label: {
            HStack {
                Spacer()
                if viewModel.isGeneratingSummary {
                    ProgressView().padding(.trailing, 8)
                    Text("小安正在統整看診溝通卡片...")
                        .font(.headline)
                } else {
                    Image(systemName: "sparkles")
                    Text("產生看診溝通摘要")
                        .font(.headline)
                }
                Spacer()
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                (viewModel.selectedCategories.isEmpty || viewModel.isGeneratingSummary)
                    ? AppTheme.textSecondary(for: colorScheme).opacity(0.4) : AppTheme.primary(for: colorScheme)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(
                color: (viewModel.selectedCategories.isEmpty || viewModel.isGeneratingSummary)
                    ? Color.clear : AppTheme.primary(for: colorScheme).opacity(0.25),
                radius: 8,
                y: 4
            )
        }
        .disabled(viewModel.selectedCategories.isEmpty || viewModel.isGeneratingSummary)

        // 診間溝通摘要卡片群
        if viewModel.hasGeneratedSummary {
            VStack(alignment: .leading, spacing: 6) {
                Text("診間溝通摘要（可直接修改文字內容）")
                    .font(.caption.bold())
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .padding(.horizontal, 4)

                VStack(spacing: 14) {
                    if viewModel.selectedReportTypes.contains("看病前準備") {
                        VStack(alignment: .leading, spacing: 6) {
                            SummaryCardView(
                                title: "看病前準備",
                                badgeColor: .teal,
                                text: $viewModel.preparationBeforeVisit,
                                minHeight: 80
                            )
                            .onChange(of: viewModel.preparationBeforeVisit) {
                                viewModel.savePreparationToHome()
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                Text("此項目僅會顯示至首頁看診提示，不會加入 PDF 報告中。")
                            }
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .padding(.horizontal, 4)
                        }
                    }

                    if viewModel.selectedReportTypes.contains("病人狀況描述") {
                        SummaryCardView(
                            title: "病人狀況描述（日常動作與症狀）",
                            badgeColor: AppTheme.primary(for: colorScheme),
                            text: $viewModel.patientStatusDescription,
                            minHeight: 80
                        )
                    }

                    if viewModel.selectedReportTypes.contains("上次回診差異") {
                        SummaryCardView(
                            title: "與上次回診之差異比較（變化趨勢）",
                            badgeColor: .purple,
                            text: $viewModel.comparisonWithLastVisit,
                            minHeight: 80
                        )
                    }

                    if viewModel.selectedReportTypes.contains("其他科別用藥與特殊補充") {
                        SummaryCardView(
                            title: "其他科別用藥與特殊補充",
                            badgeColor: .green,
                            text: $viewModel.otherMedicationsOrNotes,
                            minHeight: 60
                        )
                    }

                    if viewModel.selectedReportTypes.contains("想問醫生的問題") {
                        SummaryCardView(
                            title: "本次想諮詢醫生的核心問題",
                            badgeColor: .orange,
                            text: $viewModel.questionsForDoctor,
                            minHeight: 80
                        )
                    }

                    ForEach($viewModel.customReportFields) { $field in
                        let displayTitle = field.title.trimmingCharacters(in: .whitespaces).isEmpty ? "自訂項目" : field.title
                        SummaryCardView(
                            title: displayTitle,
                            badgeColor: AppTheme.textSecondary(for: colorScheme),
                            text: $field.content,
                            minHeight: 60
                        )
                    }
                }
                .padding(16)
                .background(AppTheme.cardBackground(for: colorScheme))
                .cornerRadius(15)
                .softCardShadow()

                Text("修改完文字後，請點擊下方「預覽 PDF 報告內容」按鈕，系統才會將內容完整儲存至資料庫與首頁。")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }

            // 預覽 PDF 報告按鈕
            Button {
                Task {
                    await viewModel.preparePDFForPreviewAsync()
                }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isGeneratingPDF {
                        ProgressView().padding(.trailing, 8)
                    } else {
                        Image(systemName: "doc.richtext.fill")
                    }
                    Text(viewModel.isGeneratingPDF ? "正在繪製 PDF..." : "預覽 PDF 報告內容")
                        .font(.headline)
                    Spacer()
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    (viewModel.isGeneratingPDF || !viewModel.hasGeneratedSummary)
                        ? AppTheme.textSecondary(for: colorScheme).opacity(0.4) : AppTheme.primary(for: colorScheme)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(
                    color: (viewModel.isGeneratingPDF || !viewModel.hasGeneratedSummary)
                        ? Color.clear : AppTheme.primary(for: colorScheme).opacity(0.25),
                    radius: 8,
                    y: 4
                )
            }
            .disabled(viewModel.isGeneratingPDF || !viewModel.hasGeneratedSummary)
        }
    }
}
