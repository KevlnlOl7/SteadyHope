import Foundation

class UserBondRepository {
    private let bondService = UserBondService.shared
    
    /// 被照護者（病患）要求產生一組新的 6 位數安全配對碼
    /// - Returns: 包含配對碼與過期時間的 PairingCodeResponseDTO
    /// - Throws: 未登入或 Token 過期時拋出認證錯誤，或網路請求失敗錯誤
    func requestPairingCode() async throws -> PairingCodeResponseDTO {
        // 從 AuthManager 自動取得 Token
        guard let token = AuthManager.shared.getToken() else {
            throw UserBondService.NetworkError.serverError(reason: "認證已過期，請重新登入")
        }
        return try await bondService.fetchPairingCode(token: token)
    }
    
    /// 獲取目前綁定對象（照護者或被照護者）的基本資料
    /// - Returns: 包含綁定對象詳細資料的 LinkedPartnerResponseDTO
    /// - Throws: 未登入或 Token 過期時拋出認證錯誤，或網路請求失敗錯誤
    func fetchMyBoundPartnerInfo() async throws -> LinkedPartnerResponseDTO {
        // 從 AuthManager 自動取得 Token
        guard let token = AuthManager.shared.getToken() else {
            throw UserBondService.NetworkError.serverError(reason: "認證已過期，請重新登入")
        }
        return try await bondService.getMyBoundPartner(token: token)
    }
    
    /// 照護者輸入病患 Email 與配對碼進行安全綁定
    /// - Parameters:
    ///   - email: 病患的電子郵件
    ///   - code: 病患產生的 6 位數配對碼
    /// - Returns: 綁定成功後回傳的 LinkedPartnerResponseDTO
    /// - Throws: 未登入或 Token 過期時拋出認證錯誤，或配對碼無效/過期等網路錯誤
    func linkWithPatient(email: String, code: String) async throws -> LinkedPartnerResponseDTO {
        // 從 AuthManager 自動取得 Token
        guard let token = AuthManager.shared.getToken() else {
            throw UserBondService.NetworkError.serverError(reason: "認證已過期，請重新登入")
        }
        
        return try await bondService.linkPatient(token: token, patientEmail: email, pairingCode: code)
    }
}
