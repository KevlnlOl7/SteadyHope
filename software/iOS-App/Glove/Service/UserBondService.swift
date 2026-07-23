import Foundation

class UserBondService {
    static let shared = UserBondService()
    private init() {}

    private let baseURL = "\(APIConfig.baseURL)/users/bonds"

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
            case .decodeError: return "資料解析失敗，請確認格式"
            }
        }
    }

    /// 請求生成 6 位數安全配對碼（限被照護者/病患端呼叫）
    /// - Parameter token: 使用者驗證 Token
    /// - Returns: 包含配對碼與過期時間的 PairingCodeResponseDTO
    /// - Throws: NetworkError 網路或解析錯誤
    func fetchPairingCode(token: String) async throws -> PairingCodeResponseDTO {
        guard let url = URL(string: "\(baseURL)/generate-code") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noData
        }

        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(PairingCodeResponseDTO.self, from: data)
        } else {
            let reason = parseServerError(data: data, code: httpResponse.statusCode)
            throw NetworkError.serverError(reason: reason)
        }
    }

    /// 獲取目前綁定的對象資訊（雙向通用 API，限已連動者呼叫）
    /// - Parameter token: 使用者驗證 Token
    /// - Returns: 包含目前連動夥伴基本資料的 LinkedPartnerResponseDTO
    /// - Throws: NetworkError 網路或解析錯誤（404 代表未綁定）
    func getMyBoundPartner(token: String) async throws -> LinkedPartnerResponseDTO {
        guard let url = URL(string: "\(baseURL)/partner") else {
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
            return try decoder.decode(LinkedPartnerResponseDTO.self, from: data)
        } else if httpResponse.statusCode == 404 {
            throw NetworkError.serverError(reason: "目前尚未綁定任何連動對象")
        } else {
            let reason = parseServerError(data: data, code: httpResponse.statusCode)
            throw NetworkError.serverError(reason: reason)
        }
    }

    /// 發起雙向驗證綁定請求（限照護者/家屬端呼叫）
    /// - Parameters:
    ///   - token: 使用者驗證 Token
    ///   - patientEmail: 病患的電子郵件
    ///   - pairingCode: 病患提供的配對碼
    /// - Returns: 綁定成功後回傳的通用關聯結構 LinkedPartnerResponseDTO
    /// - Throws: NetworkError 網路或解析錯誤
    func linkPatient(token: String, patientEmail: String, pairingCode: String) async throws -> LinkedPartnerResponseDTO {
        guard let url = URL(string: "\(baseURL)/link") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let bodyObj = LinkPatientRequest(
            patientEmail: patientEmail,
            pairingCode: pairingCode
        )
        request.httpBody = try JSONEncoder().encode(bodyObj)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noData
        }

        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(LinkedPartnerResponseDTO.self, from: data)
        } else {
            let reason = parseServerError(data: data, code: httpResponse.statusCode)
            throw NetworkError.serverError(reason: reason)
        }
    }

    /// 綁定請求用的內部傳輸結構
    private struct LinkPatientRequest: Encodable {
        let patientEmail: String
        let pairingCode: String
    }

    /// 解析後端錯誤原因的輔助函式
    /// - Parameters:
    ///   - data: 伺服器回傳的 Data
    ///   - code: HTTP 狀態碼
    /// - Returns: 解析後的錯誤字串說明
    private func parseServerError(data: Data, code: Int) -> String {
        struct VaporError: Decodable {
            let reason: String
        }
        if let serverError = try? JSONDecoder().decode(VaporError.self, from: data) {
            return serverError.reason
        }
        return "連動失敗，錯誤碼：\(code)"
    }
}
