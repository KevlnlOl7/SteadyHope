import Foundation

/// 使用者自訂報表欄位資料傳輸物件 (DTO)
struct CustomReportFieldDTO: Codable, Sendable {
    var title: String
    var content: String
}

/// 請求 AI 生成看診溝通卡片摘要之上行資料傳輸物件 (DTO)
struct GenerateConsultationSummaryRequestDTO: Codable, Sendable {
    /// 欲進行健康數據統計與症狀分析的起始日期
    let startDate: Date

    /// 欲進行健康數據統計與症狀分析的結束日期
    let endDate: Date

    /// 選取納入分析的報表圖表類型標籤
    let selectedReportTypes: [String]

    /// 選取納入分析的日常紀錄分類
    let selectedCategories: [String]

    /// 使用者手動輸入的附加或自訂紀錄分類說明（若無則為 nil）
    let customCategoryText: String?

    /// 是否將使用者的每日心情隨筆與語音記事納入 AI 上下文進行身心情緒分析
    let includeMoodNotes: Bool

    /// 使用者額外自訂的報表補充欄位清單（選填，若無則為 nil）
    let customFields: [CustomReportFieldDTO]?
}

/// AI 生成看診溝通卡片摘要之後端下行資料傳輸物件 (DTO)
struct ConsultationSummaryResponseDTO: Codable, Sendable {
    /// 看診前準備建議
    let preparationBeforeVisit: String

    /// 近期病況描述
    let patientStatusDescription: String

    /// 與上次看診對比
    let comparisonWithLastVisit: String

    /// 其他用藥或備註
    let questionsForDoctor: String

    /// 建議向醫師諮詢的問題
    let otherMedicationsOrNotes: String

    /// 自訂欄位摘要結果
    let customFieldsSummary: [CustomReportFieldDTO]
}
