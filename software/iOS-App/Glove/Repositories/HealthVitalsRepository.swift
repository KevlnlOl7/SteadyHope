import Foundation

class HealthVitalsRepository {
    private let apiService = HealthVitalsAPIService.shared

    /// 取得特定日期的生理數據紀錄清單
    /// - Parameter date: 查詢日期字串（格式：yyyy-MM-dd），若為 nil 則查詢全部紀錄
    /// - Returns: 解碼完成之 HealthVitalsResponseDTO 陣列
    /// - Throws: 網路請求失敗或伺服器回應異常時拋出錯誤
    func fetchVitals(for date: String? = nil) async throws -> [HealthVitalsResponseDTO] {
        try await apiService.fetchVitals(for: date)
    }

    /// 新增一筆生理數據紀錄至遠端伺服器
    /// - Parameter record: 欲新增之生理量測請求傳輸物件
    /// - Returns: 伺服器建立成功後回傳之 HealthVitalsResponseDTO 實例
    /// - Throws: 網路請求失敗或驗證異常時拋出錯誤
    func addVitals(_ record: CreateHealthVitalsRequestDTO) async throws -> HealthVitalsResponseDTO {
        try await apiService.addVitals(record: record)
    }

    /// 編輯指定 ID 之生理數據紀錄
    /// - Parameters:
    ///   - id: 欲更新之生理量測紀錄 ID
    ///   - record: 欲更新欄位之傳輸物件
    /// - Returns: 伺服器更新完成後回傳之 HealthVitalsResponseDTO 實例
    /// - Throws: 網路請求失敗或驗證異常時拋出錯誤
    func updateVitals(id: Int, record: UpdateHealthVitalsRequestDTO) async throws -> HealthVitalsResponseDTO {
        try await apiService.updateVitals(recordID: id, record: record)
    }

    /// 根據生理量測紀錄 ID 刪除遠端伺服器上的紀錄
    /// - Parameter id: 欲刪除之生理量測紀錄 ID
    /// - Returns: 刪除成功回傳 true，否則回傳 false
    /// - Throws: 網路請求失敗或伺服器回應異常時拋出錯誤
    func deleteVitals(id: Int) async throws -> Bool {
        try await apiService.deleteVitals(recordID: id)
    }
}
