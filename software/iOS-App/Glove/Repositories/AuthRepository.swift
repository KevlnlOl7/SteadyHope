import Foundation

///驗證與帳號資料的數據存取層
class AuthRepository {

    /// 底層網路服務實例
    private let authService = AuthAPIService()

    /// 執行登入邏輯
    /// - Parameter request: 登入用的數據傳輸物件 (Account)
    /// - Returns: 登入成功後包含 Token 與使用者資訊的 LoginResponseDTO
    /// - Throws: 網路傳輸或資料解析錯誤
    func login(request: Account) async throws -> LoginResponseDTO {
        let data = try await authService.login(
            email: request.email,
            password: request.password
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        /// 解碼成 LoginResponseDTO 取得 Token 與個人資訊
        let response = try decoder.decode(LoginResponseDTO.self, from: data)

        /// 登入成功後即刻持久化 Token
        AuthManager.shared.saveToken(response.token)

        return response
    }

    /// 執行註冊邏輯
    /// - Parameter request: 註冊用的數據傳輸物件 (RegisterData)
    /// - Returns: 註冊成功後的 UserData 物件
    /// - Throws: 網路傳輸或伺服器驗證錯誤
    func register(request: RegisterData) async throws -> UserData {
        /// 呼叫底層 Service 執行註冊
        return try await authService.register(request: request)
    }

    /// 更新個人資料與密碼設定
    /// - Parameter request: 欲更新之欄位與密碼資訊 (UpdateProfileRequestDTO)
    /// - Returns: 伺服器回傳更新後之最新 UserDataDTO；若伺服器未回傳內文則回傳 nil
    /// - Throws: 網路傳輸或伺服器驗證錯誤
    func updateProfile(request: UpdateProfileRequestDTO) async throws -> UserDataDTO? {
        let data = try await authService.updateProfile(request: request)

        /// 如果伺服器回傳空內容（HTTP 204 或空 body）
        if data.isEmpty {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)

            /// 支援標準日期格式 (yyyy-MM-dd)
            let formatter1 = DateFormatter()
            formatter1.dateFormat = "yyyy-MM-dd"
            formatter1.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = formatter1.date(from: dateStr) { return date }

            /// 支援 ISO8601 完整時間格式
            let formatter2 = ISO8601DateFormatter()
            if let date = formatter2.date(from: dateStr) { return date }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "無法解析日期: \(dateStr)"
            )
        }

        /// 解碼成 UserDataDTO，若解析失敗則回傳 nil
        return try? decoder.decode(UserDataDTO.self, from: data)
    }
}
