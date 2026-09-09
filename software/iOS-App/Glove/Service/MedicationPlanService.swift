import Foundation

class MedicationPlanService {
    private let baseURL = APIConfig.baseURL

    /// 新增或更新用藥排程至遠端伺服器
    /// - Parameter plan: 欲儲存之用藥計畫 DTO
    /// - Returns: 儲存成功回傳 true，否則回傳 false
    /// - Throws: 網路請求異常或驗證錯誤時拋出 Validation 錯誤
    func savePlan(plan: MedicationPlanDTO) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/medication-plan/save") else {
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

        request.httpBody = try encoder.encode(plan)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Validation.server(message: "伺服器回應異常")
        }

        return httpResponse.statusCode == 200 || httpResponse.statusCode == 201
    }

    /// 從遠端伺服器取得所有用藥計畫清單
    /// - Returns: 用藥計畫 DTO 陣列
    /// - Throws: 網路請求異常或資料解碼失敗時拋出錯誤
    func fetchAllPlans() async throws -> [MedicationPlanDTO] {
        guard let url = URL(string: "\(baseURL)/medication-plan/all") else {
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

        return try decoder.decode([MedicationPlanDTO].self, from: data)
    }

    /// 根據用藥計畫 ID 刪除遠端伺服器上的排程
    /// - Parameter id: 欲刪除之用藥計畫 ID
    /// - Returns: 刪除成功回傳 true，否則回傳 false
    /// - Throws: 網路請求異常或驗證錯誤時拋出 Validation 錯誤
    func deletePlan(id: Int) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/medication-plan/\(id)") else {
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

    /// 自訂日期解碼策略，支援常見的後端日期字串格式解析
    /// - Returns: JSONDecoder 之 DateDecodingStrategy 策略
    private func customDateDecodingStrategy() -> JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // 純日期格式 (yyyy-MM-dd)
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateOnlyFormatter.timeZone = Calendar.current.timeZone

            if let date = dateOnlyFormatter.date(from: dateString) {
                return date
            }

            // ISO8601 含毫秒
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds
            ]

            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            // ISO8601 標準格式
            isoFormatter.formatOptions = [
                .withInternetDateTime
            ]

            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            // 標準日期時間格式 (yyyy-MM-dd'T'HH:mm:ss)
            let dateTimeFormatter = DateFormatter()
            dateTimeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            dateTimeFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateTimeFormatter.timeZone = TimeZone(secondsFromGMT: 0)

            if let date = dateTimeFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "無法解析日期格式: \(dateString)"
            )
        }
    }
}
