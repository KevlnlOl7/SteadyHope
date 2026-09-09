import Foundation

class AssessmentAPIService {

    static let shared = AssessmentAPIService()

    private init() {}

    /// 提交每日健康評估問卷至伺服器
    /// - Parameters:
    ///   - payload: 包含評估總分、各面向分數與細項作答之請求資料傳輸物件
    ///   - token: 身分驗證 Bearer 權杖字串
    /// - Returns: 伺服器端保存完成後回傳之評估紀錄回應 DTO
    /// - Throws: 當 URL 無效、伺服器狀態碼非 2xx 或 JSON 解碼失敗時拋出例外
    func submitDailyAssessment(
        payload: CreateDailyAssessmentRequestDTO,
        token: String
    ) async throws -> DailyAssessmentResponseDTO {
        guard let url = URL(string: "\(APIConfig.baseURL)/assessment/submit") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(reason: "提交每日評估失敗")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DailyAssessmentResponseDTO.self, from: data)
    }

    /// 查詢使用者之每日評估歷史紀錄（若帶入日期則查詢指定單日，若未帶入則查詢全部）
    /// - Parameters:
    ///   - dateString: 查詢日期字串（格式為 yyyy-MM-dd），可選
    ///   - token: 身分驗證 Bearer 權杖字串
    /// - Returns: 符合條件之每日評估紀錄回應 DTO 陣列
    /// - Throws: 當 URL 無效、伺服器狀態碼非 2xx 或 JSON 解碼失敗時拋出例外
    func fetchDailyAssessment(
        dateString: String?,
        token: String
    ) async throws -> [DailyAssessmentResponseDTO] {
        let urlString: String
        if let dateString = dateString, !dateString.isEmpty {
            urlString = "\(APIConfig.baseURL)/assessment/search?date=\(dateString)"
        } else {
            urlString = "\(APIConfig.baseURL)/assessment/search"
        }

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(reason: "查詢評估紀錄失敗")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([DailyAssessmentResponseDTO].self, from: data)
    }
}
