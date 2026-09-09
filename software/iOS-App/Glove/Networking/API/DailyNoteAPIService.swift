import Foundation

/// 負責處理日常紀錄（Daily Record）遠端 API 同步、查詢與刪除之服務類別
class DailyNoteAPIService {
    /// 靜態單例存取點
    static let shared = DailyNoteAPIService()
    
    private init() {}

    /// API 基礎路徑
    private let baseURL = "\(APIConfig.baseURL)/daily"

    /// 同步單筆日常紀錄至伺服器
    /// - Parameters:
    ///   - token: 使用者驗證 Token
    ///   - record: 欲同步之 DailyRequestDTO 物件
    func syncRecord(token: String, record: DailyRequestDTO) async throws {
        guard let url = URL(string: "\(baseURL)/sync") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            request.httpBody = try encoder.encode(record)
        } catch {
            throw NetworkError.encodingFailed
        }

        try await NetworkManager.shared.requestData(request)
    }

    /// 取得伺服器內所有的日常歷史紀錄
    /// - Parameter token: 使用者驗證 Token
    /// - Returns: 歷史紀錄陣列
    func getAllRecords(token: String) async throws -> [DailyRecordResponseDTO] {
        guard let url = URL(string: "\(baseURL)/all") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await NetworkManager.shared.request(request)
    }

    /// 刪除指定 ID 之日常紀錄
    /// - Parameters:
    ///   - token: 使用者驗證 Token
    ///   - recordID: 紀錄之識別碼
    func deleteRecord(token: String, recordID: String) async throws {
        guard let url = URL(string: "\(baseURL)/\(recordID)") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        try await NetworkManager.shared.requestData(request)
    }
}
