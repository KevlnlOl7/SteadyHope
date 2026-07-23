import Foundation

class MedicationService {

    private let baseURL = APIConfig.baseURL

    /// 新增用藥紀錄至伺服器
    /// - Parameter record: 包含用藥詳細資訊的 MedicationRecordDTO
    /// - Returns: 新增成功與否（HTTP 200 或 201 時回傳 true）
    /// - Throws: Validation.server 網路連線錯誤、URL 格式錯誤或權限不足
    func addMedication(record: MedicationRecordDTO) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/medication/add") else {
            throw Validation.server(message: "URL 格式錯誤")
        }
        guard let token = AuthManager.shared.getToken() else {
            throw Validation.server(message: "權限不足，請重新登入")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        request.httpBody = try encoder.encode(record)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Validation.server(message: "伺服器回應異常")
        }

        return httpResponse.statusCode == 200 || httpResponse.statusCode == 201
    }

    /// 依指定日期查詢伺服器上的用藥紀錄
    /// - Parameter date: 查詢日期字串 (格式: yyyy-MM-dd)
    /// - Returns: 解碼後的 MedicationRecordDTO 陣列
    /// - Throws: Validation.server 網路錯誤、權限不足，或 DecodingError 日期解析失敗
    func fetchMedications(for date: String) async throws -> [MedicationRecordDTO] {
        guard let url = URL(string: "\(baseURL)/medication/search?date=\(date)")
        else {
            throw Validation.server(message: "URL 格式錯誤")
        }

        guard let token = AuthManager.shared.getToken() else {
            throw Validation.server(message: "權限不足，請重新登入")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw Validation.server(message: "獲取資料失敗")
        }

        let decoder = JSONDecoder()

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]

            if let date = formatter.date(from: dateString) { return date }

            formatter.formatOptions = [
                .withInternetDateTime, .withFractionalSeconds,
            ]

            if let date = formatter.date(from: dateString) { return date }

            let fallback = DateFormatter()
            fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            fallback.locale = Locale(identifier: "en_US_POSIX")

            if let date = fallback.date(from: dateString) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "無法解析日期格式: \(dateString)"
            )
        }

        return try decoder.decode([MedicationRecordDTO].self, from: data)
    }

    /// 根據用藥紀錄 ID 刪除伺服器上的紀錄
    /// - Parameter id: 用藥紀錄唯一識別碼
    /// - Returns: 刪除成功與否（HTTP 200 或 204 時回傳 true）
    /// - Throws: Validation.server 網路連線錯誤、URL 格式錯誤或權限不足
    func deleteMedication(id: Int) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/medication/\(id)") else {
            throw Validation.server(message: "URL 格式錯誤")
        }
        guard let token = AuthManager.shared.getToken() else {
            throw Validation.server(message: "權限不足")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Validation.server(message: "伺服器回應異常")
        }

        return httpResponse.statusCode == 204 || httpResponse.statusCode == 200
    }
}
