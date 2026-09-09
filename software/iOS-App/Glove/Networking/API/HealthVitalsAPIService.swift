import Foundation

class HealthVitalsAPIService {
    static let shared = HealthVitalsAPIService()
    private init() {}

    private let baseURL = "\(APIConfig.baseURL)/vitals"

    /// 新增生理數據紀錄至遠端伺服器
    /// - Parameter record: 包含生理量測資訊之 CreateHealthVitalsRequestDTO 實例
    /// - Returns: 伺服器回傳之 HealthVitalsResponseDTO 實例
    func addVitals(record: CreateHealthVitalsRequestDTO) async throws -> HealthVitalsResponseDTO {
        guard let url = URL(string: "\(baseURL)/add") else {
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
            request.httpBody = try encoder.encode(record)
        } catch {
            throw NetworkError.encodingFailed
        }

        return try await NetworkManager.shared.request(request, decoder: makeDecoder())
    }

    /// 依指定日期查詢或獲取全部生理數據清單
    /// - Parameter date: 查詢日期字串（格式：yyyy-MM-dd），若為 nil 則查詢全部紀錄
    /// - Returns: 解碼完成之 HealthVitalsResponseDTO 陣列
    func fetchVitals(for date: String? = nil) async throws -> [HealthVitalsResponseDTO] {
        let urlString: String
        if let targetDate = date {
            urlString = "\(baseURL)/search?date=\(targetDate)"
        } else {
            urlString = "\(baseURL)/search"
        }

        guard let url = URL(string: urlString) else {
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

    /// 編輯指定 ID 之生理數據紀錄
    /// - Parameters:
    ///   - recordID: 欲更新之生理量測紀錄 ID
    ///   - record: 欲更新欄位之 UpdateHealthVitalsRequestDTO 實例
    /// - Returns: 伺服器更新完成後回傳之 HealthVitalsResponseDTO 實例
    func updateVitals(recordID: Int, record: UpdateHealthVitalsRequestDTO) async throws -> HealthVitalsResponseDTO {
        guard let url = URL(string: "\(baseURL)/\(recordID)") else {
            throw NetworkError.invalidURL
        }
        guard let token = AuthManager.shared.getToken() else {
            throw NetworkError.unauthorized
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            request.httpBody = try encoder.encode(record)
        } catch {
            throw NetworkError.encodingFailed
        }

        return try await NetworkManager.shared.request(request, decoder: makeDecoder())
    }

    /// 刪除指定 ID 之生理數據紀錄
    /// - Parameter recordID: 欲刪除之生理量測紀錄 ID
    /// - Returns: 刪除成功回傳 true，否則拋出錯誤
    func deleteVitals(recordID: Int) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/\(recordID)") else {
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

    /// 自訂日期解碼策略，支援 ISO8601（含毫秒與標準）及標準 DateTime 日期格式解析
    private func customDateDecodingStrategy() -> JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            isoFormatter.formatOptions = [.withInternetDateTime]
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
