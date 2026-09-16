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

        return try await NetworkManager.shared.request(request)
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

        return try await NetworkManager.shared.request(request)
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
        
        return try await NetworkManager.shared.request(request)
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
        do {
            request.httpBody = try JSONEncoder().encode(bodyObj)
        } catch {
            throw NetworkError.encodingFailed
        }

        return try await NetworkManager.shared.request(request)
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
            do {
                urlRequest.httpBody = try JSONEncoder().encode(request)
            } catch {
                throw NetworkError.encodingFailed
            }
        }

        try await NetworkManager.shared.requestData(urlRequest)
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
        do {
            request.httpBody = try JSONEncoder().encode(bodyObj)
        } catch {
            throw NetworkError.encodingFailed
        }

        try await NetworkManager.shared.requestData(request)
    }
}
