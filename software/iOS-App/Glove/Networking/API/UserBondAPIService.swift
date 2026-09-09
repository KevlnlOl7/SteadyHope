import Foundation

class UserBondAPIService {
    static let shared = UserBondAPIService()
    private init() {}

    private let baseURL = "\(APIConfig.baseURL)/users/bonds"

    /// 請求生成 6 位數安全配對碼（限病患端呼叫）
    /// - Parameter token: 使用者驗證 Token
    /// - Returns: 包含配對碼與過期時間的 PairingCodeResponseDTO
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

    /// 病患端獲取已連動的照護者列表
    /// - Parameter token: 使用者驗證 Token
    /// - Returns: 照護者陣列 [LinkedPartnerResponseDTO]
    func getBoundCaregivers(token: String) async throws -> [LinkedPartnerResponseDTO] {
        guard let url = URL(string: "\(baseURL)/caregivers") else {
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
            return try decoder.decode([LinkedPartnerResponseDTO].self, from: data)
        } else {
            let reason = parseServerError(data: data, code: httpResponse.statusCode)
            throw NetworkError.serverError(reason: reason)
        }
    }

    /// 照護者端獲取單一病患資訊
    /// - Parameter token: 使用者驗證 Token
    /// - Returns: 被照護者資訊 LinkedPartnerResponseDTO
    func getBoundPatient(token: String) async throws -> LinkedPartnerResponseDTO {
        guard let url = URL(string: "\(baseURL)/patient") else {
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
            throw NetworkError.serverError(reason: "目前尚未綁定任何病患")
        } else {
            let reason = parseServerError(data: data, code: httpResponse.statusCode)
            throw NetworkError.serverError(reason: reason)
        }
    }

    /// 發起雙向驗證綁定請求（限照護者端呼叫）
    /// - Parameters:
    ///   - token: 使用者驗證 Token
    ///   - patientEmail: 病患的電子郵件
    ///   - pairingCode: 病患提供的配對碼
    /// - Returns: 綁定成功後回傳的 LinkedPartnerResponseDTO
    func linkPatient(token: String, patientEmail: String, pairingCode: String) async throws -> LinkedPartnerResponseDTO {
        guard let url = URL(string: "\(baseURL)/link") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let bodyObj = LinkPatientRequestDTO(
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

    /// 解除照護者與被照護者綁定關係
    /// - Parameters:
    ///   - token: 使用者驗證 Token
    ///   - request: 病患端指定解除用參數，照護者端傳入 nil
    func unlinkBond(token: String, request: UnlinkBondRequestDTO? = nil) async throws {
        guard let url = URL(string: "\(baseURL)/unlink") else {
            throw NetworkError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "DELETE"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let request = request {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noData
        }

        guard [200, 204].contains(httpResponse.statusCode) else {
            let reason = parseServerError(data: data, code: httpResponse.statusCode)
            throw NetworkError.serverError(reason: reason)
        }
    }
    
    /// 更新照護者權限（限病患端呼叫）
    /// - Parameters:
    ///   - token: 使用者驗證 Token (Patient JWT)
    ///   - caregiverID: 照護者 ID
    ///   - canManageMedPlan: 是否能管理用藥清單 (選填)
    ///   - canAddMedRecord: 是否能新增用藥紀錄 (選填)
    func updateCaregiverPermissions(
        token: String,
        caregiverID: Int,
        canManageMedPlan: Bool? = nil,
        canAddMedRecord: Bool? = nil
    ) async throws {
        guard let url = URL(string: "\(baseURL)/permissions") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let bodyObj = PermissionRequestDTO(
            caregiverID: caregiverID,
            canManageMedPlan: canManageMedPlan,
            canAddMedRecord: canAddMedRecord
        )
        request.httpBody = try JSONEncoder().encode(bodyObj)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noData
        }

        // 成功回傳 200 OK
        guard [200, 204].contains(httpResponse.statusCode) else {
            let reason = parseServerError(data: data, code: httpResponse.statusCode)
            throw NetworkError.serverError(reason: reason)
        }
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
