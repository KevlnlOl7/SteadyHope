import SwiftUI

struct ExportSettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
        VStack(spacing: 0) {
            Form {
                if viewModel.currentStep == 1 {
                    stepOneSection
                } else {
                    stepTwoSection
                }
            }
        }
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

    /// 第一頁視圖區塊：日期、匯出類型選擇與自訂項目
    @ViewBuilder
    private var stepOneSection: some View {
        Section(header: Text("請選擇欲匯出的醫療報告期間")) {
            DatePicker(
                "開始日期",
                selection: $viewModel.startDate,
                in: ...viewModel.endDate,
                displayedComponents: .date
            )
            .environment(\.locale, Locale(identifier: "zh_TW"))

            DatePicker(
                "結束日期",
                selection: $viewModel.endDate,
                in: viewModel.startDate...Date(),
                displayedComponents: .date
            )
            .environment(\.locale, Locale(identifier: "zh_TW"))
        }

        Section(header: Text("請勾選欲由 AI 整理的報告項目（可複選）")) {
            ForEach(viewModel.reportTypeOptions, id: \.self) { type in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(type)
                            .font(.body)
                            .foregroundColor(.primary)
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
                            ? .blue : .gray.opacity(0.4)
                    )
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    if viewModel.selectedReportTypes.contains(type) {
                        viewModel.selectedReportTypes.remove(type)
                    } else {
                        viewModel.selectedReportTypes.insert(type)
                    }
                }
            }
        }

        Section(header: Text("自訂報告項目（自由新增）")) {
            ForEach($viewModel.customReportFields) { $field in
                HStack {
                    TextField("輸入項目名稱（例如：復健狀況）", text: $field.title)
                    Button(role: .destructive) {
                        if let idx = viewModel.customReportFields.firstIndex(
                            where: { $0.id == field.id })
                        {
                            viewModel.customReportFields.remove(at: idx)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .onDelete(perform: viewModel.removeCustomReportField)

            Button(action: {
                withAnimation {
                    viewModel.addCustomReportField()
                }
            }) {
                Label("新增自訂項目", systemImage: "plus.circle.fill")
                    .foregroundColor(.blue)
            }
        }

        Section {
            Button(action: {
                withAnimation(.spring()) {
                    viewModel.currentStep = 2
                }
            }) {
                HStack {
                    Spacer()
                    Text("下一步：勾選觀察項目")
                        .font(.headline)
                    Image(systemName: "arrow.right.circle.fill")
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 4)
            }
            .listRowBackground(
                !viewModel.hasValidSelection ? Color.gray : Color.blue
            )
            .disabled(!viewModel.hasValidSelection)
        }

        Section {
            Button(action: {
                Task {
                    await viewModel.preparePDFForPreviewAsync()
                }
            }) {
                HStack {
                    Spacer()
                    if viewModel.isGeneratingPDF {
                        ProgressView()
                            .padding(.trailing, 8)
                    } else {
                        Image(systemName: "doc.richtext.fill")
                    }
                    Text(
                        viewModel.isGeneratingPDF
                            ? "正在繪製 PDF..." : "無需 AI 彙整預覽 PDF 報告內容"
                    )
                    .font(.headline)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 4)
            }
            .disabled(
                viewModel.isGeneratingPDF || viewModel.hasValidSelection
            )
            .listRowBackground(
                viewModel.isGeneratingPDF || viewModel.hasValidSelection
                    ? Color.gray : Color.blue
            )
        }
    }

    /// 第二頁視圖區塊：觀察健康主題與診間溝通卡片編輯
    @ViewBuilder
    private var stepTwoSection: some View {
        Section {
            Button(action: {
                withAnimation(.spring()) {
                    viewModel.currentStep = 1
                }
            }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("返回重選欄位種類")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
        }

        Section(header: Text("請勾選 AI 需深入分析的健康主題（可複選）")) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.includeMoodNotes.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName: viewModel.includeMoodNotes
                                ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(
                            viewModel.includeMoodNotes ? .blue : .gray
                        )

                        Text("引用心情留言板")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .background(Color.clear)
                }
                .buttonStyle(.plain)

                let allTitlesCount = viewModel.categoryOptions.count
                let isAllSelected =
                    viewModel.selectedCategories.count == allTitlesCount

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let allTitles = Set(
                            viewModel.categoryOptions.map { $0.title }
                        )
                        if isAllSelected {
                            viewModel.selectedCategories.removeAll()
                        } else {
                            viewModel.selectedCategories = allTitles
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName: isAllSelected
                                ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isAllSelected ? .blue : .gray)

                        Text("全選主題")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .background(Color.clear)
                }
                .buttonStyle(.plain)
            }
            .listRowInsets(
                EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            )

            ForEach(viewModel.categoryOptions, id: \.title) { item in
                let isSelected = viewModel.selectedCategories.contains(
                    item.title
                )
                let isExpanded = viewModel.expandedCategories.contains(
                    item.title
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16))
                            .foregroundColor(isSelected ? .blue : .gray)
                            .frame(width: 24, height: 24)

                        Text(item.title)
                            .font(
                                .system(
                                    size: 15,
                                    weight: isSelected ? .semibold : .regular
                                )
                            )
                            .foregroundColor(.primary)

                        Spacer()

                        HStack(spacing: 2) {
                            Text(isExpanded ? "收起" : "說明")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Image(
                                systemName: isExpanded
                                    ? "chevron.up" : "chevron.down"
                            )
                            .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(12)
                        .foregroundColor(.secondary)
                        .onTapGesture {
                            if isExpanded {
                                viewModel.expandedCategories.remove(item.title)
                            } else {
                                viewModel.expandedCategories.insert(item.title)
                            }
                        }

                        Image(
                            systemName: isSelected
                                ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.title3)
                        .foregroundColor(
                            isSelected ? .blue : .gray.opacity(0.3)
                        )
                        .onTapGesture {
                            if isSelected {
                                viewModel.selectedCategories.remove(item.title)
                            } else {
                                viewModel.selectedCategories.insert(item.title)
                            }
                        }
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
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                            .padding(.leading, 32)
                            .padding(.top, 2)
                            .transition(.opacity)
                    }

                    if item.title == "其他（自由補充）" && isSelected {
                        TextField(
                            "請輸入其他狀況說明...",
                            text: $viewModel.customCategoryText,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                        .padding(10)
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                        )
                    }
                }
            }

            // 產生摘要按鈕
            Button(action: {
                Task {
                    await viewModel.requestAISummaryAsync()
                }
            }) {
                HStack {
                    Spacer()
                    if viewModel.isGeneratingSummary {
                        ProgressView()
                            .progressViewStyle(
                                CircularProgressViewStyle(tint: .white)
                            )
                            .padding(.trailing, 8)
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
                .padding(.vertical, 4)
            }
            .listRowBackground(
                (viewModel.selectedCategories.isEmpty
                    || viewModel.isGeneratingSummary) ? Color.gray : Color.blue
            )
            .disabled(
                viewModel.selectedCategories.isEmpty
                    || viewModel.isGeneratingSummary
            )
        }

        if viewModel.hasGeneratedSummary {
            Section(
                header: Text("診間溝通摘要（可直接修改文字內容）"),
                footer: Text("修改完文字後，請點擊下方「預覽 PDF 報告內容」按鈕，系統才會將內容完整儲存至資料庫與首頁喔！")
                    .foregroundColor(.orange)
            ) {
                if viewModel.selectedReportTypes.contains("看病前準備") {
                    VStack(alignment: .leading, spacing: 6) {
                        SummaryCardView(
                            title: "看病前準備",
                            badgeColor: .teal,
                            text: $viewModel.preparationBeforeVisit,
                            minHeight: 80
                        )
                        .onChange(of: viewModel.preparationBeforeVisit) {
                            if let saveMethod = (viewModel as AnyObject).value(
                                forKey: "savePreparationToHome"
                            ) as? () -> Void {
                                saveMethod()
                            }
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                            Text("此項目僅會顯示至首頁看診提示，不會加入 PDF 報告中。")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    }
                }

                if viewModel.selectedReportTypes.contains("病人狀況描述") {
                    SummaryCardView(
                        title: "病人狀況描述（日常動作與症狀）",
                        badgeColor: .blue,
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

                if viewModel.selectedReportTypes.contains("其他科別用藥與特殊補充")
                {
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
                    let displayTitle =
                        field.title.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "自訂項目" : field.title
                    SummaryCardView(
                        title: displayTitle,
                        badgeColor: .gray,
                        text: $field.content,
                        minHeight: 60
                    )
                }
            }
        }

        Section {
            Button(action: {
                Task {
                    await viewModel.preparePDFForPreviewAsync()
                }
            }) {
                HStack {
                    Spacer()
                    if viewModel.isGeneratingPDF {
                        ProgressView()
                            .padding(.trailing, 8)
                    } else {
                        Image(systemName: "doc.richtext.fill")
                    }
                    Text(
                        viewModel.isGeneratingPDF
                            ? "正在繪製 PDF..." : "預覽 PDF 報告內容"
                    )
                    .font(.headline)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 4)
            }
            .disabled(
                viewModel.isGeneratingPDF || !viewModel.hasGeneratedSummary
            )
            .listRowBackground(
                viewModel.isGeneratingPDF || !viewModel.hasGeneratedSummary
                    ? Color.gray : Color.blue
            )
        }
    }
}
