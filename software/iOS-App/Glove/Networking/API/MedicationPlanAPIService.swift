import Foundation

class MedicationPlanAPIService {
    private let baseURL = APIConfig.baseURL

    /// 新增或更新用藥排程至遠端伺服器
    /// - Parameter plan: 欲儲存之用藥計畫 DTO
    /// - Returns: 儲存成功回傳 true，否則拋出錯誤
    func savePlan(plan: MedicationPlanDTO) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/medication-plan/save") else {
            throw NetworkError.invalidURL
        }
        guard let token = AuthManager.shared.getToken() else {
            throw NetworkError.unauthorized
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            request.httpBody = try encoder.encode(plan)
        } catch {
            throw NetworkError.encodingFailed
        }

        try await NetworkManager.shared.requestData(request)
        return true
    }

    /// 從遠端伺服器取得所有用藥計畫清單
    /// - Returns: 用藥計畫 DTO 陣列
    func fetchAllPlans() async throws -> [MedicationPlanDTO] {
        guard let url = URL(string: "\(baseURL)/medication-plan/all") else {
            throw NetworkError.invalidURL
        }
        guard let token = AuthManager.shared.getToken() else {
            throw NetworkError.unauthorized
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await NetworkManager.shared.request(request, decoder: makeDecoder())
    }

    /// 根據用藥計畫 ID 刪除遠端伺服器上的排程
    /// - Parameter id: 欲刪除之用藥計畫 ID
    /// - Returns: 刪除成功回傳 true，否則拋出錯誤
    func deletePlan(id: Int) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/medication-plan/\(id)") else {
            throw NetworkError.invalidURL
        }
        guard let token = AuthManager.shared.getToken() else {
            throw NetworkError.unauthorized
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        try await NetworkManager.shared.requestData(request)
        return true
    }

    /// 建立帶有自訂日期解碼策略的 JSONDecoder
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = customDateDecodingStrategy()
        return decoder
    }

    /// 自訂日期解碼策略，支援常見的後端日期字串格式解析
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
