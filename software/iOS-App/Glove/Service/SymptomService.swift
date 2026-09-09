import Foundation

class SymptomService {
    private let baseURL = APIConfig.baseURL

    /// 新增症狀紀錄至遠端伺服器
    /// - Parameter record: 包含症狀詳細資訊之 SymptomRecordDTO 實例
    /// - Returns: 新增成功回傳 true，否則回傳 false
    /// - Throws: 網路請求異常或驗證錯誤時拋出 Validation 錯誤
    func addSymptom(record: SymptomRecordDTO) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/symptom/add") else {
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

    /// 依指定日期查詢或獲取全部遠端症狀紀錄清單
    /// - Parameter date: 查詢日期字串（格式：yyyy-MM-dd），若為 nil 則查詢全部紀錄
    /// - Returns: 解碼完成之 SymptomRecordDTO 陣列
    /// - Throws: 網路請求失敗、伺服器異常或資料解碼錯誤時拋出錯誤
    func fetchSymptoms(for date: String? = nil) async throws -> [SymptomRecordDTO] {
        let urlString: String
        if let targetDate = date {
            urlString = "\(baseURL)/symptom/search?date=\(targetDate)"
        } else {
            urlString = "\(baseURL)/symptom/search"
        }

        guard let url = URL(string: urlString) else {
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
        decoder.dateDecodingStrategy = customDateDecodingStrategy()

        return try decoder.decode([SymptomRecordDTO].self, from: data)
    }

    /// 根據症狀紀錄 ID 刪除遠端伺服器上的紀錄
    /// - Parameter id: 欲刪除之症狀紀錄 ID
    /// - Returns: 刪除成功回傳 true，否則回傳 false
    /// - Throws: 網路請求異常或驗證錯誤時拋出 Validation 錯誤
    func deleteSymptom(id: Int) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/symptom/\(id)") else {
            throw Validation.server(message: "URL 格式錯誤")
        }
        guard let token = AuthManager.shared.getToken() else {
            throw Validation.server(message: "權限不足，請重新登入")
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

    /// 根據症狀紀錄 ID 更新遠端伺服器上的紀錄
    /// - Parameters:
    ///   - id: 欲更新之症狀紀錄 ID
    ///   - record: 包含更新資訊之 UpdateSymptomRequestDTO 實例
    /// - Returns: 更新成功回傳 true，否則回傳 false
    /// - Throws: 網路請求異常或驗證錯誤時拋出 Validation 錯誤
    func updateSymptom(id: Int, record: UpdateSymptomRequestDTO) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/symptom/\(id)") else {
            throw Validation.server(message: "URL 格式錯誤")
        }
        guard let token = AuthManager.shared.getToken() else {
            throw Validation.server(message: "權限不足，請重新登入")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(record)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Validation.server(message: "伺服器回應異常")
        }
        return httpResponse.statusCode == 200
    }

    /// 自訂日期解碼策略，支援 ISO8601 與標準 DateTime 日期格式解析
    /// - Returns: JSONDecoder 之 DateDecodingStrategy 策略
    private func customDateDecodingStrategy() -> JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            isoFormatter.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds
            ]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            let fallbackFormatter = DateFormatter()
            fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
            fallbackFormatter.timeZone = TimeZone(secondsFromGMT: 0)

            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "無法解析日期格式: \(dateString)"
            )
        }
    }
}
