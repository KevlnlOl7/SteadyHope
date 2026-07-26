import Foundation

class DailyService {
    static let shared = DailyService()
    private init() {}

    private let baseURL = "\(APIConfig.baseURL)/daily"

    /// 自訂網路錯誤型態
    enum NetworkError: LocalizedError {
        case invalidURL
        case noData
        case serverError(reason: String)
        case decodeError

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "無效的連線網址"
            case .noData: return "伺服器未回傳資料"
            case .serverError(let reason): return reason
            case .decodeError: return "資料解析失敗"
            }
        }
    }

    /// 同步（新增或修改）每日紀錄卡片至伺服器
    /// - Parameters:
    ///   - token: 使用者驗證 Token
    ///   - record: 包含留言內容與卡片資訊的 DailyRequestDTO
    /// - Throws: NetworkError 網址無效、伺服器錯誤或回應異常
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

        if httpResponse.statusCode != 200 {
            let reason = parseServerError(data: data, code: httpResponse.statusCode)
            throw NetworkError.serverError(reason: reason)
        }
    }

    /// 獲取看板上所有的每日紀錄卡片
    /// - Parameter token: 使用者驗證 Token
    /// - Returns: 解碼後的 DailyRecordResponseDTO 陣列
    /// - Throws: NetworkError 網址無效、解析失敗或伺服器錯誤
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

    /// 根據紀錄識別碼刪除伺服器上的每日紀錄卡片
    /// - Parameters:
    ///   - token: 使用者驗證 Token
    ///   - recordID: 紀錄之唯一識別碼 (UUID String)
    /// - Throws: NetworkError 網址無效或伺服器錯誤
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

        // 後端成功處理後回傳 204 No Content
        if httpResponse.statusCode == 204 {
            return
        } else {
            let reason = parseServerError(data: data, code: httpResponse.statusCode)
            throw NetworkError.serverError(reason: reason)
        }
    }

    /// 解析後端錯誤原因的輔助函式
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
