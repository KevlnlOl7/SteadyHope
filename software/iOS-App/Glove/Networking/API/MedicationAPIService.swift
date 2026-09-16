import Foundation

class MedicationAPIService {
    private let baseURL = APIConfig.baseURL

    /// 新增用藥紀錄至遠端伺服器
    /// - Parameter record: 包含用藥詳細資訊之 MedicationRecordDTO 實例
    /// - Returns: 新增成功回傳 true，否則拋出錯誤
    func addMedication(record: MedicationRecordDTO) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/medication/add") else {
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

        try await NetworkManager.shared.requestData(request)
        return true
    }

    /// 依指定日期查詢或獲取全部遠端用藥紀錄清單
    /// - Parameter date: 查詢日期字串（格式：yyyy-MM-dd），若為 nil 則查詢全部紀錄
    /// - Returns: 解碼完成之 MedicationRecordDTO 陣列
    func fetchMedications(for date: String? = nil) async throws -> [MedicationRecordDTO] {
        let urlString: String
        if let targetDate = date {
            urlString = "\(baseURL)/medication/search?date=\(targetDate)"
        } else {
            urlString = "\(baseURL)/medication/search"
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

    /// 根據用藥紀錄 ID 刪除遠端伺服器上的紀錄
    /// - Parameter id: 欲刪除之用藥紀錄 ID
    /// - Returns: 刪除成功回傳 true，否則拋出錯誤
    func deleteMedication(id: Int) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/medication/\(id)") else {
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

    /// 根據用藥紀錄 ID 更新遠端伺服器上的紀錄
    /// - Parameters:
    ///   - id: 欲更新之用藥紀錄 ID
    ///   - record: 包含更新資訊之 UpdateMedicationRequestDTO 實例
    /// - Returns: 更新成功回傳 true，否則拋出錯誤
    func updateMedication(id: Int, record: UpdateMedicationRequestDTO) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/medication/\(id)") else {
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

        try await NetworkManager.shared.requestData(request)
        return true
    }

    /// 建立帶有自訂日期解碼策略的 JSONDecoder
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = customDateDecodingStrategy()
        return decoder
    }

    /// 自訂日期解碼策略，支援 ISO8601 與標準 DateTime 日期格式解析
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
