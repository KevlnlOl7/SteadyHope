import Foundation

class AssessmentAPIService {

    static let shared = AssessmentAPIService()

    private init() {}

    private let baseURL = "\(APIConfig.baseURL)/assessment"

    /// 提交每日健康評估問卷至伺服器
    /// - Parameters:
    ///   - payload: 包含評估總分、各面向分數與細項作答之請求資料傳輸物件
    ///   - token: 身分驗證 Bearer 權杖字串
    /// - Returns: 伺服器端保存完成後回傳之評估紀錄回應 DTO
    func submitDailyAssessment(
        payload: CreateDailyAssessmentRequestDTO,
        token: String
    ) async throws -> DailyAssessmentResponseDTO {
        guard let url = URL(string: "\(baseURL)/submit") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            throw NetworkError.encodingFailed
        }

        return try await NetworkManager.shared.request(request)
    }

    /// 查詢使用者之每日評估歷史紀錄（若帶入日期則查詢指定單日，若未帶入則查詢全部）
    /// - Parameters:
    ///   - dateString: 查詢日期字串（格式為 yyyy-MM-dd），可選
    ///   - token: 身分驗證 Bearer 權杖字串
    /// - Returns: 符合條件之每日評估紀錄回應 DTO 陣列
    func fetchDailyAssessment(
        dateString: String?,
        token: String
    ) async throws -> [DailyAssessmentResponseDTO] {
        let urlString: String
        if let dateString = dateString, !dateString.isEmpty {
            urlString = "\(baseURL)/search?date=\(dateString)"
        } else {
            urlString = "\(baseURL)/search"
        }

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await NetworkManager.shared.request(request)
    }
    
    /// 刪除指定評估紀錄
    /// - Parameters:
    ///   - recordID: 欲刪除之評估紀錄唯一識別碼
    ///   - token: 身分驗證 Bearer 權杖字串
    func deleteDailyAssessment(
        recordID: Int,
        token: String
    ) async throws {
        guard let url = URL(string: "\(baseURL)/\(recordID)") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        try await NetworkManager.shared.requestData(request)
    }

    func deleteAssessment(recordID: Int, token: String) async throws {
        try await deleteDailyAssessment(recordID: recordID, token: token)
    }
}
