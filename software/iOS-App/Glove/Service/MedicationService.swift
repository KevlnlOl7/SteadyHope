import Foundation

class MedicationService {
    private let baseURL = APIConfig.baseURL

    /// 新增用藥紀錄至遠端伺服器
    /// - Parameter record: 包含用藥詳細資訊之 MedicationRecordDTO 實例
    /// - Returns: 新增成功回傳 true，否則回傳 false
    /// - Throws: 網路連線錯誤、URL 格式錯誤或權限不足時拋出 Validation 錯誤
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

    /// 依指定日期查詢或獲取全部遠端用藥紀錄清單
    /// - Parameter date: 查詢日期字串（格式：yyyy-MM-dd），若為 nil 則查詢全部紀錄
    /// - Returns: 解碼完成之 MedicationRecordDTO 陣列
    /// - Throws: 網路請求失敗、伺服器異常或資料解碼錯誤時拋出錯誤
    func fetchMedications(for date: String? = nil) async throws -> [MedicationRecordDTO] {
        let urlString: String
        if let targetDate = date {
            urlString = "\(baseURL)/medication/search?date=\(targetDate)"
        } else {
            urlString = "\(baseURL)/medication/search"
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

        return try decoder.decode([MedicationRecordDTO].self, from: data)
    }

    /// 根據用藥紀錄 ID 刪除遠端伺服器上的紀錄
    /// - Parameter id: 欲刪除之用藥紀錄 ID
    /// - Returns: 刪除成功回傳 true，否則回傳 false
    /// - Throws: 網路請求異常或驗證錯誤時拋出 Validation 錯誤
    func deleteMedication(id: Int) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/medication/\(id)") else {
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

    /// 根據用藥紀錄 ID 更新遠端伺服器上的紀錄
    /// - Parameters:
    ///   - id: 欲更新之用藥紀錄 ID
    ///   - record: 包含更新資訊之 UpdateMedicationRequestDTO 實例
    /// - Returns: 更新成功回傳 true，否則回傳 false
    /// - Throws: 網路請求異常或驗證錯誤時拋出 Validation 錯誤
    func updateMedication(id: Int, record: UpdateMedicationRequestDTO) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/medication/\(id)") else {
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

            // ISO8601 標準格式
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            // ISO8601 含毫秒格式
            isoFormatter.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds
            ]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            // 標準日期時間格式 (yyyy-MM-dd'T'HH:mm:ss)
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
