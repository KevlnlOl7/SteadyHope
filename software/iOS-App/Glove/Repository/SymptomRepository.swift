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
    
    /// 更新指定症狀紀錄並同步至遠端伺服器
    /// - Parameters:
    ///   - id: 欲更新之症狀紀錄 ID
    ///   - record: 包含更新內容之 UpdateSymptomRequestDTO 實體
    /// - Returns: 更新成功回傳 true，否則回傳 false
    /// - Throws: 網路請求異常或驗證錯誤時拋出錯誤
    func updateSymptom(id: Int, record: UpdateSymptomRequestDTO) async throws -> Bool {
        try await apiService.updateSymptom(id: id, record: record)
    }
}
