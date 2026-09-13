import Foundation

class AssessmentRepository {

    static let shared = AssessmentRepository()

    private let apiService = AssessmentAPIService.shared

    private init() {}

    /// 提交每日健康評估問卷，內部自動自 AuthManager 獲取最新權杖進行驗證
    /// - Parameter payload: 包含總分、各面向得分與細項作答內容之請求 DTO
    /// - Returns: 伺服器端保存完成之評估紀錄回應 DTO
    /// - Throws: 當找不到有效登入憑證或網路傳輸錯誤時拋出例外
    func submitAssessment(
        payload: CreateDailyAssessmentRequestDTO
    ) async throws -> DailyAssessmentResponseDTO {
        // 從 AuthManager 取得驗證 Token
        guard let token = AuthManager.shared.getToken() else {
            throw NetworkError.serverError(reason: "找不到登入憑證，請重新登入")
        }

        return try await apiService.submitDailyAssessment(payload: payload, token: token)
    }

    /// 查詢使用者的歷史評估紀錄清單（可指定單一日期，若不指定則帶入 nil 取得全部）
    /// - Parameter dateString: 查詢日期字串（格式為 yyyy-MM-dd），可選
    /// - Returns: 符合條件之評估紀錄回應 DTO 陣列
    /// - Throws: 當找不到有效登入憑證或網路傳輸錯誤時拋出例外
    func fetchAssessment(
        dateString: String? = nil
    ) async throws -> [DailyAssessmentResponseDTO] {
        guard let token = AuthManager.shared.getToken() else {
            throw NetworkError.serverError(reason: "找不到登入憑證，請重新登入")
        }

        return try await apiService.fetchDailyAssessment(dateString: dateString, token: token)
    }
    
    /// 刪除指定評估紀錄
    /// - Parameter recordID: 欲刪除之問卷紀錄唯一識別碼
    func deleteAssessment(recordID: Int) async throws {
        guard let token = AuthManager.shared.getToken() else {
            throw NetworkError.unauthorized
        }
        try await AssessmentAPIService.shared.deleteDailyAssessment(
            recordID: recordID,
            token: token
        )
    }
}
