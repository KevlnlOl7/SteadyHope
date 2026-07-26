import Combine
import Foundation
import SwiftUI

/// 負責處理醫療報告匯出設定、健康主題篩選與 PDF 範本繪製邏輯的 ViewModel
class ExportSettingsViewModel: ObservableObject {
    let loginVM: LoginViewModel
    let medVM: MedicationViewModel
    let dataVM: DataViewModel

    /// 報告開始日期（預設為 7 天前）
    @Published var startDate =
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

    /// 報告結束日期（預設為今日）
    @Published var endDate = Date()

    /// 步驟管理：1 表示選擇種類，2 表示選擇觀察項目與檢視卡片
    @Published var currentStep = 1

    /// 選擇「其他（自由補充）」時的自訂文字說明
    @Published var customCategoryText: String = ""

    /// 第一頁已勾選的報告彙整種類集合
    @Published var selectedReportTypes: Set<String> = []

    /// 已勾選的健康觀察主題標題集合
    @Published var selectedCategories: Set<String> = []

    /// 已展開說明內文的健康觀察主題集合
    @Published var expandedCategories: Set<String> = []

    /// 診間溝通卡片文字狀態
    @Published var otherMedicationsOrNotes = ""
    @Published var patientStatusDescription = ""
    @Published var comparisonWithLastVisit = ""
    @Published var questionsForDoctor = ""

    /// 狀態管理與 PDF 繪製控制
    @Published var hasGeneratedSummary = false
    @Published var generatedPDFData: Data? = nil
    @Published var showPreviewSheet = false
    @Published var isGeneratingPDF = false
    @Published var includeMoodNotes: Bool = false

    /// 錯誤提示控制
    @Published var showErrorAlert = false
    @Published var errorMessage = ""

    /// 第一頁提供選擇的報告彙整種類選項
    var reportTypeOptions: [String] {
        ReportConfig.reportTypeOptions
    }

    /// 第二頁提供選擇的健康觀察主題清單
    var categoryOptions: [CategoryItem] {
        ReportConfig.defaultCategories
    }

    init(
        loginVM: LoginViewModel,
        medVM: MedicationViewModel,
        dataVM: DataViewModel
    ) {
        self.loginVM = loginVM
        self.medVM = medVM
        self.dataVM = dataVM
    }

    /// 載入與確認連動夥伴資料
    @MainActor
    func loadPartnerIfNeeded() async {
        if loginVM.userData?.role == 1 && loginVM.boundPartner == nil {
            do {
                let bondRepo = UserBondRepository()
                let partner = try await bondRepo.fetchMyBoundPartnerInfo()
                loginVM.boundPartner = partner
                loginVM.isLinked = true
            } catch {
                print("抓取連動夥伴資料失敗: \(error.localizedDescription)")
            }
        }
    }

    /// 撈取相關數據，套用 HTML 樣式範本並繪製 PDF 報告
    @MainActor
    func preparePDFForPreviewAsync() async {
        isGeneratingPDF = true
        await medVM.loadAllRecords()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: endDate)
        let userName = loginVM.partnerName

        let userBirth: String
        if let birthDate = loginVM.userData?.birthday {
            userBirth = formatter.string(from: birthDate)
        } else {
            userBirth = "未設定生日"
        }

        let calendar = Calendar.current
        let filterStart = calendar.startOfDay(for: startDate)
        let filterEnd =
            calendar.date(
                bySettingHour: 23,
                minute: 59,
                second: 59,
                of: endDate
            ) ?? endDate

        let filteredMeds = medVM.medicationList.filter {
            $0.date >= filterStart && $0.date <= filterEnd
        }

        var medicationRowsHTML = ""
        if filteredMeds.isEmpty {
            medicationRowsHTML =
                "<tr><td colspan='3' style='text-align: center; color: #a0aec0;'>此期間內無用藥紀錄</td></tr>"
        } else {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            for med in filteredMeds {
                medicationRowsHTML +=
                    "<tr><td>\(timeFormatter.string(from: med.date))</td><td>\(med.name)</td><td>\(med.dose)</td></tr>"
            }
        }

        let vibrationRowsHTML =
            "<tr><td colspan='4' style='text-align: center; color: #a0aec0;'>此期間內無震動感測數據</td></tr>"

        guard
            let filepath = Bundle.main.path(
                forResource: "report_template",
                ofType: "html"
            ),
            let templateString = try? String(
                contentsOfFile: filepath,
                encoding: .utf8
            )
        else {
            self.errorMessage = "找不到報告 HTML 範本檔案。"
            self.showErrorAlert = true
            self.isGeneratingPDF = false
            return
        }

        let pPre = otherMedicationsOrNotes.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let pStatus = patientStatusDescription.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let pComp = comparisonWithLastVisit.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let pQuest = questionsForDoctor.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let htmlContent =
            templateString
            .replacingOccurrences(of: "{{userName}}", with: userName)
            .replacingOccurrences(of: "{{userBirth}}", with: userBirth)
            .replacingOccurrences(of: "{{startString}}", with: startString)
            .replacingOccurrences(of: "{{endString}}", with: endString)
            .replacingOccurrences(
                of: "{{vibrationRowsHTML}}",
                with: vibrationRowsHTML
            )
            .replacingOccurrences(
                of: "{{medicationRowsHTML}}",
                with: medicationRowsHTML
            )
            .replacingOccurrences(
                of: "{{vitalsRowsHTML}}",
                with:
                    "<tr><td colspan='5' style='text-align: center; color: #a0aec0;'>此期間內無數據</td></tr>"
            )
            .replacingOccurrences(
                of: "{{otherMedicationsOrNotes}}",
                with: (selectedReportTypes.contains("其他科別用藥與特殊補充")
                    && !pPre.isEmpty)
                    ? pPre : "無特別用藥與補充事項"
            )
            .replacingOccurrences(
                of: "{{patientStatusDescription}}",
                with: (selectedReportTypes.contains("病人狀況描述")
                    && !pStatus.isEmpty) ? pStatus : "無特別備註狀況"
            )
            .replacingOccurrences(
                of: "{{comparisonWithLastVisit}}",
                with: (selectedReportTypes.contains("上次回診差異") && !pComp.isEmpty)
                    ? pComp : "未觀察到明顯變化"
            )
            .replacingOccurrences(
                of: "{{questionsForDoctor}}",
                with: (selectedReportTypes.contains("想問醫生的問題")
                    && !pQuest.isEmpty) ? pQuest : "無特定問題"
            )

        PDFDataGenerator.shared.generatePDFData(from: htmlContent) {
            [weak self] data in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isGeneratingPDF = false
                if let pdfData = data {
                    self.generatedPDFData = pdfData
                    self.showPreviewSheet = true
                } else {
                    self.errorMessage = "PDF 產生失敗，請稍後再試。"
                    self.showErrorAlert = true
                }
            }
        }
    }
}
