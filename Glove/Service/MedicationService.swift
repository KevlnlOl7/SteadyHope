import Foundation

class MedicationService {

    private let baseURL = APIConfig.baseURL

    /// 新增用藥紀錄
    func addMedication(record: MedicationRecord) async throws -> Bool {
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Validation.server(message: "伺服器回應異常")
        }

        return httpResponse.statusCode == 200 || httpResponse.statusCode == 201
    }

    /// 依日期查詢用藥紀錄
    func fetchMedications(for date: String) async throws -> [MedicationRecord] {
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

        return try decoder.decode([MedicationRecord].self, from: data)
    }

    /// 刪除用藥紀錄
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
