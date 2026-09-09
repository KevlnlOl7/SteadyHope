import Foundation

class SymptomRepository {
    private let apiService = SymptomService()

    /// 取得特定日期的所有症狀紀錄清單
    /// - Parameter date: 查詢目標日期字串
    /// - Returns: 轉換完成之 SymptomRecord 領域模型陣列
    /// - Throws: 網路請求失敗或資料解碼異常時拋出錯誤
    func getAllSymptoms(for date: String) async throws -> [SymptomRecord] {
        let dtos = try await apiService.fetchSymptoms(for: date)
        return dtos.map { $0.toModel() }
    }

    /// 新增一筆症狀紀錄至遠端伺服器
    /// - Parameter record: 欲新增之 SymptomRecord 領域模型實例
    /// - Returns: 新增成功回傳 true，否則回傳 false
    /// - Throws: 網路請求失敗或伺服器回應異常時拋出錯誤
    func addSymptom(_ record: SymptomRecord) async throws -> Bool {
        let dto = record.toDTO()
        return try await apiService.addSymptom(record: dto)
    }

    /// 根據症狀紀錄 ID 刪除遠端伺服器上的紀錄
    /// - Parameter id: 欲刪除之症狀紀錄 ID
    /// - Returns: 刪除成功回傳 true，否則回傳 false
    /// - Throws: 網路請求失敗或伺服器回應異常時拋出錯誤
    func deleteSymptom(id: Int) async throws -> Bool {
        try await apiService.deleteSymptom(id: id)
    }
}
