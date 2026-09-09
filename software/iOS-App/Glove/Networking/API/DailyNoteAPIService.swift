import Foundation

/// 負責處理日常紀錄（Daily Record）遠端 API 同步、查詢與刪除之服務類別
class DailyNoteAPIService {
    /// 靜態單例存取點
    static let shared = DailyNoteAPIService()
    
    private init() {}

    /// API 基礎路徑
    private let baseURL = "\(APIConfig.baseURL)/daily"

    /// 檢查 HTTP 回應狀態碼是否為 401，若為 401 則發送全域廣播通知並拋出錯誤
    /// - Parameters:
    ///   - httpResponse: HTTP URL 回應物件
    ///   - data: 伺服器回傳之 Data
    private func checkStatusCode(_ httpResponse: HTTPURLResponse, data: Data) throws {
        if httpResponse.statusCode == 401 {
            let reason = parseServerError(data: data, code: 401)
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .didReceive401Unauthorized,
                    object: nil,
                    userInfo: ["message": reason]
                )
            }
            throw NetworkError.serverError(reason: reason)
        }
    }

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
        request.httpBody = try encoder.encode(record)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noData
        }

        try checkStatusCode(httpResponse, data: data)

        if httpResponse.statusCode != 200 {
            let reason = parseServerError(data: data, code: httpResponse.statusCode)
            throw NetworkError.serverError(reason: reason)
        }
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noData
        }

        try checkStatusCode(httpResponse, data: data)

        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                return try decoder.decode([DailyRecordResponseDTO].self, from: data)
            } catch {
                throw NetworkError.decodeError
            }
        } else {
            let reason = parseServerError(data: data, code: httpResponse.statusCode)
            throw NetworkError.serverError(reason: reason)
        }
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noData
        }

        try checkStatusCode(httpResponse, data: data)

        if httpResponse.statusCode == 204 {
            return
        } else {
            let reason = parseServerError(data: data, code: httpResponse.statusCode)
            throw NetworkError.serverError(reason: reason)
        }
    }

    /// 解析伺服器回傳之錯誤訊息 JSON
    /// - Parameters:
    ///   - data: 伺服器回傳的 Data
    ///   - code: HTTP 狀態碼
    /// - Returns: 解析後的錯誤說明字串
    private func parseServerError(data: Data, code: Int) -> String {
        struct VaporError: Decodable {
            let reason: String
        }
        if let serverError = try? JSONDecoder().decode(VaporError.self, from: data) {
            return serverError.reason
        }
        return "連線失敗，錯誤碼：\(code)"
    }
}
