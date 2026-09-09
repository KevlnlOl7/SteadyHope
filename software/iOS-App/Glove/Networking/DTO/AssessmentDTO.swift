import Foundation

/// 每日健康評估問卷個別題目作答細項資料傳輸物件 (DTO)
struct AssessmentAnswerDetailDTO: Codable, Hashable {
    let questionId: Int
    let section: String
    let title: String
    let score: Int
    let selectedOptionTitle: String
}

/// 提交每日健康評估問卷請求資料傳輸物件 (DTO)
struct CreateDailyAssessmentRequestDTO: Codable {
    let date: Date
    let totalScore: Int
    let moodScore: Int
    let adlScore: Int
    let motorScore: Int
    let details: [AssessmentAnswerDetailDTO]?
}

/// 伺服器端每日健康評估紀錄回應資料傳輸物件 (DTO)
struct DailyAssessmentResponseDTO: Codable, Identifiable, Hashable {
    let id: Int?
    let date: Date
    let totalScore: Int
    let moodScore: Int
    let adlScore: Int
    let motorScore: Int
    let detailsJson: String?
    let createdAt: Date?

    /// 自動將 JSON 字串解析為結構化作答細項陣列
    var parsedDetails: [AssessmentAnswerDetailDTO] {
        guard let detailsJson = detailsJson,
              let data = detailsJson.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([AssessmentAnswerDetailDTO].self, from: data)) ?? []
    }
}
