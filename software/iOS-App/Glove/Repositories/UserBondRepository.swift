import Foundation

class UserBondRepository {
    private let bondService = UserBondAPIService.shared

    /// 取得當前 Token 的輔助檢查
    private func getValidToken() throws -> String {
        guard let token = AuthManager.shared.getToken() else {
            throw NetworkError.serverError(reason: "認證已過期，請重新登入")
        }
        return token
    }

    /// 被照護者（病患）要求產生一組新的 6 位數安全配對碼
    /// - Returns: 包含配對碼與過期時間的 PairingCodeResponseDTO
    func requestPairingCode() async throws -> PairingCodeResponseDTO {
        let token = try getValidToken()
        return try await bondService.fetchPairingCode(token: token)
    }

    /// 病患端：獲取所有已綁定的照護者列表
    /// - Returns: [LinkedPartnerResponseDTO]
    func fetchBoundCaregivers() async throws -> [LinkedPartnerResponseDTO] {
        let token = try getValidToken()
        return try await bondService.getBoundCaregivers(token: token)
    }

    /// 照護者端：獲取目前綁定的病患資訊
    /// - Returns: LinkedPartnerResponseDTO
    func fetchBoundPatientInfo() async throws -> LinkedPartnerResponseDTO {
        let token = try getValidToken()
        return try await bondService.getBoundPatient(token: token)
    }

    /// 照護者輸入病患 Email 與配對碼進行安全綁定
    /// - Parameters:
    ///   - email: 病患的電子郵件
    ///   - code: 病患產生的 6 位數配對碼
    /// - Returns: 綁定成功後回傳的 LinkedPartnerResponseDTO
    func linkWithPatient(email: String, code: String) async throws -> LinkedPartnerResponseDTO {
        let token = try getValidToken()
        return try await bondService.linkPatient(token: token, patientEmail: email, pairingCode: code)
    }

    /// 病患端：解除指定照護者的綁定關係
    /// - Parameters:
    ///   - caregiverEmail: 指定欲解除之照護者 Email（二選一）
    ///   - caregiverID: 指定欲解除之照護者 ID（二選一）
    func unlinkCaregiver(caregiverEmail: String? = nil, caregiverID: Int? = nil) async throws {
        let token = try getValidToken()
        let requestDTO = UnlinkBondRequestDTO(
            caregiverEmail: caregiverEmail,
            caregiverID: caregiverID
        )
        try await bondService.unlinkBond(token: token, request: requestDTO)
    }

    /// 照護者端：自動解除與當前被照護者的綁定（無需帶 Body）
    func unlinkCurrentPatient() async throws {
        let token = try getValidToken()
        try await bondService.unlinkBond(token: token, request: nil)
    }
    
    /// 更新指定照護者的權限（限病患端呼叫）
    /// - Parameters:
    ///   - caregiverID: 照護者 ID
    ///   - canManageMedPlan: 是否能管理用藥清單
    ///   - canAddMedRecord: 是否能新增用藥紀錄
    func updateCaregiverPermissions(caregiverID: Int,canManageMedPlan: Bool? = nil,canAddMedRecord: Bool? = nil) async throws {
        let token = try getValidToken()
        try await bondService.updateCaregiverPermissions(
            token: token,caregiverID: caregiverID,canManageMedPlan: canManageMedPlan,canAddMedRecord: canAddMedRecord
        )
    }
}
