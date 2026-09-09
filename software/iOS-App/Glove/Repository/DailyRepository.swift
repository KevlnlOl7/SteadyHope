import Foundation

class DailyRepository {
    private let service = DailyService.shared

    /// 同步每日留言紀錄（便利貼）到伺服器
    /// - Parameters:
    ///   - id: 紀錄唯一識別碼
    ///   - content: 使用者留言內容
    ///   - date: 紀錄時間
    ///   - colorHex: 卡片代表顏色 Hex 色碼
    ///   - sender: 發送者標籤或名稱
    ///   - moodName: 心情狀態名稱
    /// - Throws: Token 過期拋出認證錯誤，或網路請求失敗錯誤
    func syncDailyRecord(
        id: String,
        content: String,
        date: Date,
        colorHex: String,
        sender: String,
        moodName: String?,
        isCaregiverOnly: Bool?
    ) async throws {
        guard let token = AuthManager.shared.getToken() else {
            throw NetworkError.serverError(reason: "認證憑證過期，請重新登入")
        }

        let dto = DailyRequestDTO(
            id: id,
            content: content,
            date: date,
            colorHex: colorHex,
            sender: sender,
            moodName: moodName,
            isCaregiverOnly: isCaregiverOnly
        )

        try await service.syncRecord(token: token, record: dto)
    }

    /// 獲取當前看板的所有紀錄並轉為 SwiftData 模型陣列
    /// - Returns: 解碼並轉換後的 Daily 模型陣列
    /// - Throws: Token 過期拋出認證錯誤，或網路請求失敗錯誤
    func fetchAllDailies() async throws -> [Daily] {
        guard let token = AuthManager.shared.getToken() else {
            throw NetworkError.serverError(reason: "認證憑證過期，請重新登入")
        }

        let responseDTOs = try await service.getAllRecords(token: token)

        return responseDTOs.map { dto in
            Daily(
                id: dto.id,
                content: dto.content,
                date: dto.date,
                colorHex: dto.colorHex,
                sender: dto.sender,
                moodName: dto.moodName,
                isCaregiverOnly: dto.isCaregiverOnly
            )
        }
    }

    /// 從伺服器刪除指定識別碼的每日紀錄
    /// - Parameter recordID: 待刪除紀錄之唯一識別碼
    /// - Throws: Token 過期拋出認證錯誤，或網路請求失敗錯誤
    func removeDailyRecord(recordID: String) async throws {
        guard let token = AuthManager.shared.getToken() else {
            throw NetworkError.serverError(reason: "認證憑證過期，請重新登入")
        }

        try await service.deleteRecord(token: token, recordID: recordID)
    }
}
